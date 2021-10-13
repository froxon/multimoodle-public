#!/bin/bash

# Arranca el contenedor y descarga certificados
#
# Esto lo deja en la carpeta etc-letsencrypt
# Que después copiaremos a donde se necesite (desde donde sea)

. ./config # Carga entorno de ejecución con variable BASE

cat << EOF
---
A continuación se arrancará el programa de generación del certificado, que conecta con letsencrypt.
Es necesario contestar a varias preguntas así:
1. "1: Spin up a temporary webserver (standalone)"
2. (SOLO LA PRIMERA VEZ) Una dirección real de correo electrónico para controlar las caducidades
3. (SOLO LA PRIMERA VEZ) "(Y)es", (o sea, pulsar la letra "Y")
4. (SOLO LA PRIMERA VEZ) "(N)o", (o sea pulsar "N", no es crítico)
5. MUY IMPORTANTE: EL DOMINIO COMPLETO TAL Y COMO SE QUIERE CREAR. Por ejemplo: curso1.ejemplo.com
Al final debe poner "Successfully received certificate"
ENTER continua. Ctrl-C para interrumpir
EOF
read x

docker run -it --rm --name certbot -v "$BASE/certbot/etc-letsencrypt:/etc/letsencrypt" -v "$BASE/certbot/var-lib-letsencrypt:/var/lib/letsencrypt" -p 80:80 certbot/certbot certonly

# En certbot/etc-letsencrypt/live/<DOMINIO>/fullchain.pem está el certificado
# En certbot/etc-letsencrypt/live/<DOMINIO>/privkey.pem está la clave privada
# para el haproxy hay que unirlas en el mismo archivo (un cat es suficiente)

