#!/bin/bash

[[ ! -f ./config ]] && { echo "No hay fichero de configuración" ;exit;}
# Carga entorno de ejecución, que debe tener al menos las variables: BASE, EMAIL
. ./config


daysbefore=14
declare -A moodles
moodles[prefijo1]=prefijo1.dominio.com
moodles[prefijo2]=prefijo2.dominio.com
# etcetera

docker stop multimoodle_proxy_1

for K in "${!moodles[@]}"; 
do 
    certdate=`openssl x509 -noout -enddate -in certbot/etc-letsencrypt/live/${moodles[$K]}/cert.pem`
    certdate=${certdate//notAfter=/} # delete "noAfter="
    expiry=`date -d "$certdate- $daysbefore day"` # substract X days
    expiry=$(date -d "$expiry" +%s) # convert to seconds
    now=$(date +%s) # now in seconds
    if [ $expiry -le $now ];
    then
        echo '--> ' $K: NEED UPDATE: $certdate
        ./actualizacerts.expect $BASE $EMAIL ${moodles[$K]}
        # Recogemos el certificado y la clave privada y los unimos en la carpeta del proxy
        cat "./certbot/etc-letsencrypt/live/${moodles[$K]}/fullchain.pem" "./certbot/etc-letsencrypt/live/${moodles[$K]}/privkey.pem" > "./haproxy/$K.pem"
    else
        echo $K: UP TO DATE: $certdate; 
    fi

done
docker start multimoodle_proxy_1
