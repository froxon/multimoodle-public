#!/bin/bash
# Pre-requisites:
# apt-get install rclone
# rclone config (and configure new remote WITHOUT autoconfig). See: https://itsfoss.com/use-onedrive-linux-rclone/

[[ ! -f ./config ]] && { echo "No hay fichero de configuración" ;exit;}
# Carga entorno de ejecución, que debe tener al menos las variables: BASE, MARIADB_PWD, MOODLE_PWD_DATABASE, MOODLE_PWD_USER
. ./config 

mkdir ~/OneDrive 
rclone --vfs-cache-mode writes mount "onedrive":  ~/OneDrive & 
echo -n "Waiting for onedrive to mount"
while [ ! -f ~/OneDrive/multimoodle.txt ]; do echo -n "."; sleep 1; done # "multimoodle.txt" MUST exist in OneDrive root
echo

mkdir -p ~/OneDrive/multimoodle/mariadb # -p doesn't fail if directory exists, and it creates all intermediate directories

for d in moodle-*/ ; do
    prefijo=${d//moodle-/}
    prefijo=${prefijo//\//}
    echo "Backup de: $prefijo en ./mariadb/$prefijo.backup.sql"
    docker exec -i multimoodle_mariadb_1 mysqldump $prefijo -u root -p$MARIADB_PWD > ~/OneDrive/multimoodle/mariadb/$prefijo.backup.sql
done

tar  -zpcvf ~/OneDrive/multimoodle/multimoodle.tar.gz --exclude='./mariadb' .

kill -SIGINT %1 # kill to umount onedrive
sleep 3 # allow to umount
rmdir ~/OneDrive 
