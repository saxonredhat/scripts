#!/bin/bash
#author:sheyinsong
#date:20230810
currentDir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
yestodayBakDate=$(date +%Y%m%d -d "-1 days")
todayBakDate=$(date +%Y%m%d)
yestodayBakList=$currentDir/.yestodayBakList.txt
todayBakList=$currentDir/.todayBakList.txt
reduceDbList=""
reduceDBSizeList=""
bakFilePercentSizeLimt="2"
isNeedDingTalkNotice=false
serverIpList=""
/opt/oss/ossutil64 ls oss://jh-db-bk/$yestodayBakDate --config-file /opt/oss/.ossutilconfig|grep .sql.gz >$yestodayBakList
/opt/oss/ossutil64 ls oss://jh-db-bk/$todayBakDate --config-file /opt/oss/.ossutilconfig|grep .sql.gz >$todayBakList

#清空文件
while read serverIp;do
        if [ x"$serverIpList" == x"" ];then
                serverIpList="$serverIp"
        else
                serverIpList="$serverIpList $serverIp"
        fi
        > $currentDir/.${serverIp}.txt
done < <(cat $todayBakList |awk '{ print $8}'|awk -F/ '{print $5}'|sort|uniq)

while read back_entry;do
        fileSize=$(echo $back_entry|awk '{ print $5}')
        serverIp=$(echo $back_entry|awk '{ print $NF}'|awk -F/ '{print $5}')
        dbName=$(echo $back_entry|awk '{ print $NF}'|awk -F/ '{print $NF}'|sed 's/.................sql.gz$//g')
        bakFile=$(echo $back_entry|awk '{ print $NF}'|awk -F/ '{print $NF}')
        today_back_entry=$(grep -E /${dbName}_.{8}_.{6}.sql.gz $todayBakList)
        today_fileSize=$(echo $today_back_entry|awk '{ print $5}')
        today_serverIp=$(echo $today_back_entry|awk '{ print $NF}'|awk -F/ '{print $5}')
        today_dbName=$(echo $today_back_entry|awk '{ print $NF}'|awk -F/ '{print $NF}'|sed 's/.................sql.gz$//g')
        today_bakFile=$(echo $today_back_entry|awk '{ print $NF}'|awk -F/ '{print $NF}')
        if [ x"$today_back_entry" == x"" ];then
                if [ x"$reduceDbList" == x"" ];then
                        reduceDbList="$dbName ($serverIp)"
                else
                        reduceDbList="$reduceDbList $dbName ($serverIp)"
                fi
        else
                #判断今天和昨天备份大小差异不超过昨天备份文件10%
                echo $bakFile,$today_bakFile
                if [ $today_fileSize -lt $fileSize ];then
                        #计算备份文件变化百分比
                        percentSize=$(echo "scale=2;($fileSize - $today_fileSize) / $fileSize*100"|bc)
                        if [ `echo "$percentSize > $bakFilePercentSizeLimt" | bc` -ge 1 ];then
                                if [ x"$reduceDBSizeList" == x"" ];then
                                        reduceDBSizeList="$dbName ($serverIp)(昨天备份大小:$fileSize 字节,今天备份大小:$today_fileSize 字节)"
                                else
                                        reduceDBSizeList="$reduceDBSizeList $dbName ($serverIp)(昨天备份大小:$fileSize 字节,今天备份大小:$today_fileSize 字节)"
                                fi
                        fi
                fi
        fi
done < $yestodayBakList

while read back_entry;do
        fileSize=$(echo $back_entry|awk '{ print $5}')
        serverIp=$(echo $back_entry|awk '{ print $NF}'|awk -F/ '{print $5}')
        dbName=$(echo $back_entry|awk '{ print $NF}'|awk -F/ '{print $NF}'|sed 's/.................sql.gz$//g')
        bakFile=$(echo $back_entry|awk '{ print $NF}'|awk -F/ '{print $NF}')
        echo "$dbName" >> $currentDir/.${serverIp}.txt
done < $todayBakList

msg="日期:`date +%Y-%m-%d` "
if [ x"$reduceDbList" != x"" ];then
        msg="$msg 今天比昨天备份减少的库：$reduceDbList"
        isNeedDingTalkNotice=true
fi

if [ x"$reduceDBSizeList" != x"" ];then
        msg="$msg 今天比昨天备份大小减少超过${bakFilePercentSizeLimt}%的库：$reduceDBSizeList"
        isNeedDingTalkNotice=true
fi

if $isNeedDingTalkNotice;then
        echo "日期:`date +%Y-%m-%d` 数据库备份到OSS异常"
        curl https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -H 'Content-Type: application/json' -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"服务器报警:{$msg}\"}}"
else
        msg="$msg 数据库备份到OSS正常, 备份明细如下："
        while read serverIp;do
                msg="$msg\n$serverIp 数据库数量:`cat $currentDir/.${serverIp}.txt|wc -l`" ;
        done< <(echo "$serverIpList"|sed 's/ /\n/g')
        curl https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -H 'Content-Type: application/json' -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"服务器报警:{$msg}\"}}"
fi
