#!/bin/bash
# Pre-requisites:
# apt-get install rclone
# rclone config (and configure new remote WITHOUT autoconfig). See: https://itsfoss.com/use-onedrive-linux-rclone/
# SCHEDULE: crontab -e and use 0 5 * * * /root/multimoodle/backuponedrive.sh 2>&1 >/tmp/cron_backup

cd "${0%/*}" # change dir to script folder
[[ ! -f ./config ]] && { echo "No hay fichero de configuración" ;exit;}
# Carga entorno de ejecución, que debe tener al menos las variables: BASE, MARIADB_PWD, MOODLE_PWD_DATABASE, MOODLE_PWD_USER
. ./config 

if [ $(date +%d) -eq 04 ]; # Monthly backup each first day of month
then
    period=monthly
elif [ $(date +%u) -eq 01 ]; # Weekly backup each monday
then 
    period=weekly
else
    period=daily
fi

echo This is a $period copy

mkdir ~/OneDrive 
rclone --vfs-cache-mode writes mount "onedrive":  ~/OneDrive & 
echo -n "Waiting for onedrive to mount"
while [ ! -f ~/OneDrive/multimoodle.txt ]; do echo -n "."; sleep 1; done
echo

mkdir -p ~/OneDrive/$period/mariadb # -p no protesta si existe, y crea directorios intermedios si no hay

for d in moodle-*/ ; do
    prefijo=${d//moodle-/}
    prefijo=${prefijo//\//}
    echo "Backup of: $prefijo in $period/mariadb/$prefijo.backup.sql"
    docker exec -i multimoodle_mariadb_1 mysqldump $prefijo -u root -p$MARIADB_PWD > ~/OneDrive/$period/mariadb/$prefijo.backup.sql
done

tar  -zpcvf ~/OneDrive/$period/multimoodle.tar.gz --exclude='./mariadb' .

kill -SIGINT %1 # kill to umount onedrive
sleep 3 # allow to umount
rmdir ~/OneDrive 
