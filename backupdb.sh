#!/bin/bash

[[ ! -f ./config ]] && { echo "No hay fichero de configuración" ;exit;}
# Carga entorno de ejecución, que debe tener al menos las variables: BASE, MARIADB_PWD, MOODLE_PWD_DATABASE, MOODLE_PWD_USER
. ./config 


for d in moodle-*/ ; do
    prefijo=${d//moodle-/}
    prefijo=${prefijo//\//}
    echo "Backup de: $prefijo en ./mariadb/$prefijo.backup.sql"
    docker exec -i multimoodle_mariadb_1 mysqldump $prefijo -u root -p$MARIADB_PWD > ./mariadb/$prefijo.backup.sql
done