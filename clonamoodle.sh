#!/bin/bash

# Carga entorno de ejecución, que debe tener al menos las variables: BASE, MARIADB_PWD, MOODLE_PWD_DATABASE
. ./config 

BASE=${BASE//\//\\\/} # sustituir todas las ocurrencias (// en lugar de /) para que funcione en SED
origen=$1
dominio=$2
[ -z "$dominio" ] && echo "Cancelado" && exit
#[[ $dominio =~ "(^(.+)\..+\..+$" ]] || echo 'Formato no válido. Ejemplo: "curso1.ejemplo.com"' && exit
regex="^([0-9a-zA-Z]+)\\..+\\..+$"
[[ $dominio =~ $regex ]] || { echo 'Formato de dominio no válido. Ejemplo: "curso1.ejemplo.com"' && exit; } # Ojo no paréntesis!!! https://unix.stackexchange.com/questions/88850/precedence-of-the-shell-logical-operators
prefijo=${BASH_REMATCH[1]}
{ [ $prefijo == "mariadb" ] || [ $prefijo == "certbot" ] || [ $prefijo == "haproxy" ]; } && echo "Prefijo no puede ser certbot ni mariadb ni haproxy" && exit; 

[[ -d ./moodle-$prefijo ]] && { echo "Ya existe la carpeta moodle-$prefijo dentro de multimoodle" ;exit;}
[[ ! -d ./moodle-$origen ]] && { echo "No existe la carpeta $origen dentro de multimoodle" ;exit;}


cat << EOF
#############################################################################################################
Voy a clonar del moodle denominado $origen a uno nuevo: $dominio
EOF
read -p "Pulsa <Ctrl>-C para interrumpir. <ENTER> para continuar" espera

# 2. Creación del certificado
./certbot/certbot.sh
read -p "Si hubo algún error, pulsa <Ctrl>-C para interrumpir. <ENTER> para continuar" espera
# Recogemos el certificado y la clave privada y los unimos en la carpeta del proxy
cat "./certbot/etc-letsencrypt/live/$dominio/fullchain.pem" "./certbot/etc-letsencrypt/live/$dominio/privkey.pem" > "./haproxy/$prefijo.pem"


# 3. Crear la nueva base de datos
# 3.1 Arranco el tingladillo si no está
echo "Arrancando el tingladillo si no está, para crear la base de datos. Espera a que arranque..."
docker-compose up &
sleep 5
echo "\n\n-------\n"
read -p "Si hubo algún error, pulsa <Ctrl>-C para interrumpir. <ENTER> para continuar" espera
# 3.2 Envío los comandos de creación de la base de datos
# Cuando hay un backtick (`) dentro de un cat <<EOF hay que escaparlo dos veces. una putada en mysql:
sql=`
cat << EOF
CREATE DATABASE \\\`$prefijo\\\`;
create user \\\`u_$prefijo\\\`@\\\`%\\\` identified by '${MOODLE_PWD_DATABASE}_$prefijo';
GRANT ALL PRIVILEGES ON \\\`$prefijo\\\`.* TO  \\\`u_$prefijo\\\`@\\\`%\\\`;
show databases;
EOF
`
echo $sql> ./comando.sql
docker exec -i multimoodle_mariadb_1 mariadb -u root -p$MARIADB_PWD < ./comando.sql
# Clonamos la base de datos
docker exec -i multimoodle_mariadb_1 mysqldump $origen -u root -p$MARIADB_PWD > ./comando.sql
docker exec -i multimoodle_mariadb_1 mariadb $prefijo -u root -p$MARIADB_PWD < ./comando.sql

read -p "Si hubo algún error, pulsa <Ctrl>-C para interrumpir. <ENTER> para continuar" espera


# Para lo siguiente, mejor parar:
docker-compose down


# 4. Actualizar el docker-compose.yml para poner el nuevo host

# 4.1 preparo las carpetas y reconfiguro el config.php
read -p "Voy a copiar carpetas (puede tardar). <Ctrl>-C para interrumpir. <ENTER> para continuar" espera
# Muy importante cp -rp preserva los permisos (la "p")!!
cp -rp ./moodle-$origen ./moodle-$prefijo
cp -rp ./moodledata-$origen ./moodledata-$prefijo
sed -i.bak "s/'$origen'/'$prefijo'/" ./moodle-$prefijo/config.php
sed -i.bak2 "s/'u_$origen'/'u_$prefijo'/" ./moodle-$prefijo/config.php
sed -i.bak3 "s/'${MOODLE_PWD_DATABASE}_$origen'/'${MOODLE_PWD_DATABASE}_$prefijo'/" ./moodle-$prefijo/config.php
sed -i.bak4 "s/'${MOODLE_PWD_DATABASE}_$origen'/'${MOODLE_PWD_DATABASE}_$prefijo'/" ./moodle-$prefijo/config.php
sed -i.bak5 "s/'https:\/\/$origen\..*\..*'/'https:\/\/$dominio'/" ./moodle-$prefijo/config.php

# 4.2 modifico el compose:
compose=`
cat << EOF

  $prefijo:
    build:
      context: .
      dockerfile: Dockerfile.moodle
      args:
        - EXTRA_LOCALES=es_ES.UTF-8 UTF-8, pt_PT.UTF-8 UTF-8
    expose:
      - 8080
    environment:
      - MOODLE_DATABASE_HOST=mariadb
      - MOODLE_DATABASE_PORT_NUMBER=3306
      - MOODLE_DATABASE_USER=u_$prefijo
      - MOODLE_DATABASE_NAME=$prefijo
      - MOODLE_USERNAME=admin_$prefijo
      - MOODLE_PASSWORD=${MOODLE_PWD_USER}_$prefijo
      - MOODLE_SITE_NAME='$prefijo MOOC'
      - MOODLE_DATABASE_PASSWORD=${MOODLE_PWD_DATABASE}_$prefijo
    volumes:
      - '$BASE\/moodle-$prefijo:\/bitnami\/moodle'
      - '$BASE\/moodledata-$prefijo:\/bitnami\/moodledata'
    depends_on:
      - mariadb

EOF
`
compose=${compose//$'\n'/\\n} # sustituir todas las ocurrencias (// en lugar de /)
sed -i.bak "s/\(.*\# MOODLELIST.*\)/\n$compose\n\n\n\1/" docker-compose.yml # deja versión anterior en bak -i.bak
compose="      - $prefijo"
sed -i.bak2 "s/\(.*\# DEPENDLIST.*\)/$compose\n\1/" docker-compose.yml # deja versión anterior en bak -i.bak


# 5. Actualizar la configuración del haproxy con el nuevo host
haproxy="crt \/usr\/local\/etc\/haproxy\/$prefijo.pem"
sed -i.bak "s/\(.*\)\(\# CRTLIST.*\)/\1$haproxy \2/" ./haproxy/haproxy.cfg # deja versión anterior en bak -i.bak
haproxy="    use_backend web_$prefijo if { ssl_fc_sni $dominio } \# content switching basado en SNI"
sed -i.bak2 "s/\(.*\# USEBACKENDLIST.*\)/$haproxy\n\1/" ./haproxy/haproxy.cfg # deja versión anterior en bak2 -i.bak2
# Ojo, si no pones llaves ahora, se cree que hay una variable denominada "$prefijo_1"
haproxy=`
cat << EOF
backend web_$prefijo
    balance roundrobin
    server $prefijo multimoodle_${prefijo}_1:8080 check
EOF
`
haproxy=${haproxy//$'\n'/\\n} # sustituir todas las ocurrencias (// en lugar de /)
sed -i.bak3 "s/\(.*\# BACKENDCONFIG.*\)/\n$haproxy\n\n\1/" ./haproxy/haproxy.cfg # deja versión anterior en bak3 -i.bak3

# 6. Arrancamos
docker-compose up & 