#!/bin/bash
#author:sheyinsong
#time:20230727
currentDir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
serviceRecordFile=$currentDir/serviceRecord.txt
ExceptionDurationTimes=5
cpuUsage=99
lockFile="$currentDir/service_monitor.lock"
lockExpireSeconds=600
psTempExportFile="$currentDir/psTempExportFile.txt"
logFile=$currentDir/service_monitor.log
jstackLogDir=$currentDir/jstackLog
jstackCommand="/usr/local/jdk/jdk1.8.0_321/bin/jstack"
jstackExportLogs=""
isNeedDingTalkNotice=false
ps -eo pid,%cpu,command --sort=-%cpu|sed 's/^[[:space:]]\+//g'|awk -v cpuUsage=$cpuUsage '$2 >= cpuUsage {print $0}' >$psTempExportFile

# 检查是否存在文件标记
if [ -f $lockFile ]; then
    time_diff=$(expr $(date +%s) - $(stat -c %Y $lockFile))
    if [ $time_diff -gt $lockExpireSeconds ]; then
        echo "锁文件$lockFile，创建时间超过$lockExpireSeconds秒，自动删除锁文件"
        rm $lockFile
    else
        echo "存在文件$lockFile，确认该脚本是否正在运行，如果没有运行，则删除该文件。"
        exit 1
    fi
fi
# 检查是否存在文件标记
#创建锁
touch $lockFile

[ ! -d $jstackLogDir ]&&mkdir $jstackLogDir

while read ps_entry;do
        #获取服务信息
        pid=$(echo $ps_entry|cut -d " " -f1)
        cpuUsage=$(echo $ps_entry|cut -d " " -f2)
        fullCommand=$(echo $ps_entry|sed 's/[[:space:]]\+/ /g'|cut -d " " -f 3-)
        serviceName=Unknow
        isJava=false
        #判断是否为java服务
        [[ $fullCommand =~ java ]]&&isJava=true
        #获取服务名
        if [[ $fullCommand =~ /disk1/data/service/ ]];then
                serviceName=$(echo $fullCommand|sed 's@^.*/disk1/data/service/\([^/]*\)/.*$@\1@g')
        else
                serviceName=$(echo $fullCommand|cut -d " " -f1)
        fi
        #判断记录文件是否存在
        [ ! -f $serviceRecordFile ]&&touch $serviceRecordFile
        #判断pid是否存在记录文件中,对pid条目信息做修改操作
        grep "^$pid|" $serviceRecordFile
        if [ $? -eq 0 ];then
                duration_time=$(grep "^$pid|" $serviceRecordFile|awk -F\| '{print $NF}')
                #判断持续次数是否超过设定的次数
                if [ $duration_time -gt $ExceptionDurationTimes ];then
                        if $isJava;then
                                #获取服务的上一次的导出时间戳
                                exportTimestamp=$(grep "^$pid|" $serviceRecordFile|awk -F\| '{print $(NF-1)}')
                                currentTimestamp=$(date +%s)
                                currentTime=$(date +%Y%m%d_%H_%M_%S)
                                #判断记录文件中的导出列是否为N，为N则表示没有导出过
                                if [ x"$exportTimestamp" == x"N" ];then
                                        #执行导出操作
                                        echo "`date` $pid $serviceName $fullCommand对应的服务负载很高，执行jstack操作" >> $logFile
                                        $jstackCommand $pid >$jstackLogDir/${pid}_${serviceName}_jstack_$currentTime.log
                                        jstackExportLogs="$jstackExportLogs $jstackLogDir/${pid}_${serviceName}_jstack_$currentTime.log"
                                        sed -i "s@^\([^|]*\)|\([^|]*\)|\([^|]*\)|\([^|]*\)\$@\1|\2|$currentTimestamp|\4@g" $serviceRecordFile
                                        isNeedDingTalkNotice=true
                                else
                                        #计算当前距离上次导出时间相差的秒数
                                        exportHasSeconds=$(expr $currentTimestamp - $exportTimestamp)
                                        if [ $exportHasSeconds -gt 3600 ];then
                                                #执行导出操作
                                                echo "`date` $pid $serviceName $fullCommand对应的服务负载很高，距离上次导出超过1个小时，执行jstack操作" >> $logFile
                                                $jstackCommand $pid >$jstackLogDir/${pid}_${serviceName}_jstack_$currentTime.log
                                                jstackExportLogs="$jstackExportLogs $jstackLogDir/${pid}_${serviceName}_jstack_$currentTime.log"
                                                sed -i "s@^\([^|]*\)|\([^|]*\)|\([^|]*\)|\([^|]*\)\$@\1|\2|$currentTimestamp|\4@g" $serviceRecordFile
                                                isNeedDingTalkNotice=true
                                        else
                                                echo "距离上次导出不到1个小时，忽略"
                                        fi
                                fi
                        else
                                #获取服务的上一次的通知时间戳
                                noticeTimestamp=$(grep "^$pid|" $serviceRecordFile|awk -F\| '{print $(NF-1)}')
                                currentTimestamp=$(date +%s)
                                if [ x"$noticeTimestamp" == x"N" ];then
                                        echo "`date` $pid 对应的服务负载很高，已经持续$ExceptionDurationTimes,对应的命令如下:$fullCommand" >> $logFile
                                        isNeedDingTalkNotice=true
                                else
                                        noticeHasSeconds=$(expr $currentTimestamp - $noticeTimestamp)
                                        if [ $noticeHasSeconds -gt 28800 ];then
                                                #执行导出操作
                                                echo "`date` $pid $serviceName $fullCommand对应的服务负载很高，距离上次通知超过8个小时" >> $logFile
                                                sed -i "s@^\([^|]*\)|\([^|]*\)|\([^|]*\)|\([^|]*\)\$@\1|\2|$currentTimestamp|\4@g" $serviceRecordFile
                                                isNeedDingTalkNotice=true
                                        else
                                                echo "距离上次导出不到1个小时，忽略"
                                        fi
                                fi
                        fi
                fi
                duration_time=$(expr $duration_time + 1)
                sed -i "s@^\($pid\).*|\([^|]*\)|[^|]*\$@\1|$serviceName|\2|$duration_time@g" $serviceRecordFile
        else
                #不存在该pid，做新增操作
                echo "$pid|$serviceName|N|1" >>$serviceRecordFile
        fi
done < <(cat $psTempExportFile)

#拷贝记录文件
cp $serviceRecordFile $currentDir/tempRecordFile.txt

#删除记录文件中负载已经恢复正常的记录
while read record_entry;do
        pid=$(echo $record_entry|awk -F\| '{ print $1}')
        grep "^$pid " $psTempExportFile
        [ $? -ne 0 ]&& sed -i "/$pid|/d" $serviceRecordFile
done < <(cat $currentDir/tempRecordFile.txt)

#判断是否需要需要发送钉钉通知
if $isNeedDingTalkNotice;then
        serviceList=$(cat $serviceRecordFile|awk -F\| '{ print $2}'|tr -s "\n" ",")
        msg="服务器：x.x.x.x上服务($serviceList)负载很高，持续$ExceptionDurationTimes分钟，$jstackExportLogs"
        curl https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxx -H 'Content-Type: application/json' -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"服务器报警:{$msg}\"}}"
fi

#清理文件
rm $psTempExportFile
rm $currentDir/tempRecordFile.txt
rm $lockFile

