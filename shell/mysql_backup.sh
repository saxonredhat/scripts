#!/bin/bash
#author:sheyinsong
currentDir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
bakPublicHost=x.x.x.x
bakHost=127.0.0.1
bakUser=user
bakPwd=x.x.x.x
bakPort=3306
backup=/disk1/backups/oss_backup/$bakPublicHost
BakDate=$(date +%Y%m%d)
BakDir=$(date +%Y%m%d_%H%M%S)
BakFullPath=$backup/$BakDir
mkdir -p $BakFullPath
echoConsoleFile(){
        echo "`date` $@"
        echo "`date` $@" >>$currentDir/logs/backup_${bakPublicHost}_db_to_oss.log
}
echoConsoleFile "备份开始"
mysql -h$bakHost -u$bakUser -p$bakPwd -P$bakPort -e "show databases;"|grep -Ev "^information_schema|performance_schema|sys$"|sed 1d|while read db;do
        echoConsoleFile "备份db:$db ..."
        echoConsoleFile "备份路径:$BakFullPath/${db}_${BakDir}.sql"
        mysqldump -h$bakHost -u$bakUser -p$bakPwd -P$bakPort -R -E --single-transaction --databases $db >$BakFullPath/${db}_${BakDir}.sql
        echoConsoleFile "备份db:$db done."
done
echoConsoleFile "备份完成"
echoConsoleFile "压缩开始"
find $BakFullPath -name *.sql|while read sql;do
        sqlFileSize=$(ls -lh $sql|awk '{print $5}')
        echoConsoleFile "compress $sql sizes($sqlFileSize)"
        gzip $sql
        gzipFileSize=$(ls -lh ${sql}.gz|awk '{print $5}')
        echoConsoleFile "compressed ${sql}.gz sizes($gzipFileSize)."
done
echoConsoleFile "压缩完成"
echoConsoleFile "上传OSS开始"
/opt/oss/ossutil64 mkdir oss://jh-db-bk/$BakDate/$bakPublicHost --config-file /opt/oss/.ossutilconfig
/opt/oss/ossutil64 cp -r $BakFullPath oss://jh-db-bk/$BakDate/$bakPublicHost --config-file /opt/oss/.ossutilconfig
echoConsoleFile "上传OSS完成"

