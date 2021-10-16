#!/bin/bash

# Carga entorno de ejecución, que debe tener al menos las variables: BASE, MARIADB_PWD, MOODLE_PWD_DATABASE
. ./config 

BASE=${BASE//\//\\\/} # sustituir todas las ocurrencias (// en lugar de /) para que funcione en SED


cat << EOF
#############################################################################################################
Creación de nuevo moodle en la estructura HAProxy.
Punto de partida: 
- Docker instalado.
- Un dominio en la forma XXXX.ejemplo.com, que tiene que estar dado de alta en el DNS
  del hosting para que lo redirija a esta máquina.
- La máquina tiene que tener abierto el puerto 443 (conveniente también el 80 para redirigirlo correctamente)
- El XXXX del dominio no puede coincidir con un XXXX previo (incluso de otro dominio).
- El XXXX del dominio no puede ser "certbot" ni "mariadb" ni "haproxy".

Escribe a continuación el dominio (por ejemplo: "curso1.ejemplo.com") o simplemente <ENTER> para cancelar:
EOF
read dominio
[ -z "$dominio" ] && echo "Cancelado" && exit
#[[ $dominio =~ "(^(.+)\..+\..+$" ]] || echo 'Formato no válido. Ejemplo: "curso1.ejemplo.com"' && exit
regex="^([0-9a-zA-Z]+)\\..+\\..+$"
[[ $dominio =~ $regex ]] || { echo 'Formato no válido. Ejemplo: "curso1.ejemplo.com"' && exit; } # Ojo no paréntesis!!! https://unix.stackexchange.com/questions/88850/precedence-of-the-shell-logical-operators
prefijo=${BASH_REMATCH[1]}


# 1. Comprobación de requisitos básicos de entrada
{ [ $prefijo == "mariadb" ] || [ $prefijo == "certbot" ] || [ $prefijo == "haproxy" ]; } && echo "Prefijo no puede ser certbot ni mariadb ni haproxy" && exit; 
[[ -d ./moodle-$prefijo ]] && { echo "Ya existe la carpeta moodle-$prefijo dentro de multimoodle" ;exit;}
if [ ! -f docker-compose.yml ]; then
    echo "docker-compose.yml: no existe y lo creo"
    haproxy="crt \/usr\/local\/etc\/haproxy\/$prefijo.pem"
    sed "s/\(.*\)\(\# MARIADB_PWD\)/\1$MARIADB_PWD/" ./docker-compose-base.yml > ./docker-compose.yml
fi
if [ ! -d ./mariadb ]; then
    echo "mariadb: carpeta no existe y la creo"
    mkdir ./mariadb
    chmod a+w mariadb
fi
if [ ! -d ./certbot ]; then
    echo "certbot: carpeta no existe y la creo, con su script y carpetas"
    mkdir ./certbot
    mkdir ./certbot/etc-letsencrypt
    mkdir ./certbot/var-lib-letsencrypt
    cp ./certbot.base.sh ./certbot/certbot.sh
    chmod a+x ./certbot/certbot.sh
fi
if [ ! -d ./haproxy ]; then
    echo "haproxy: carpeta no existe y la creo con su yml"
    mkdir haproxy
    cp ./haproxy.base.cfg ./haproxy/haproxy.cfg
fi


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
read -p "Si hubo algún error, pulsa <Ctrl>-C para interrumpir. <ENTER> para continuar" espera
# Para lo siguiente, mejor parar:
docker-compose down


# 4. Actualizar el docker-compose.yml para poner el nuevo host

# 4.1 preparo las carpetas
mkdir ./moodle-$prefijo
chmod a+w ./moodle-$prefijo
mkdir ./moodledata-$prefijo
chmod a+w ./moodledata-$prefijo

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
      - MOODLE_PASSWORD=$MOODLE_PWD_USER_$prefijo
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
sed -i.bak2 "s/\(.*\# DEPENDLIST.*\)/$compose\n\1/" docker-compose.yml # deja versión anterior en bak2 -i.bak2


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

# 6. configurar el proxy inverso en moodle
echo ""
echo ""
read -p "Estamos a punto de acabar. Ahora se instalará moodle en el nuevo host. Pulsa enter, espera a que se instale y luego vuelve a pulsar" espera
docker-compose up &
read espera
echo "Aquí actualizamos el config.php"
# Ojo al "doble escape" en \\\\\$CFG, donde tenemos que escapar el dólar, pero también la barra dos veces,
# una para la asignación ("config.php=...") y otra para el sed que viene más tarde!
configphp=`
cat << EOF
# HAPROXY CONFIGURATION
\\\\\\\$CFG->wwwroot = 'https:\/\/$dominio';
\\\\\\\$CFG->sslproxy = true;
EOF
`
configphp=${configphp//$'\n'/\\n} # sustituir todas las ocurrencias (// en lugar de /)
sed -i.bak "s/^\$CFG\->dataroot/$configphp\n\n\$CFG\->dataroot/" ./moodle-$prefijo/config.php


echo "Falta simplemente bajar y subir el moodle, que es lo que voy a hacer:"
# Ojo, si no pones llaves ahora, se cree que hay una variable denominada "$prefijo_1"
docker stop multimoodle_${prefijo}_1
docker start multimoodle_${prefijo}_1
echo " - TODO DEBERÍA ESTAR OK - "

