# MULTIMOODLE 
Creación dinámica de sucesivos "moodles" configurados sobre la misma base de datos mariadb, todos ellos detrás de un HAProxy (reparto de carga, proxy inverso SSL)
La idea es: llegar, instalar docker, bajar 10 ficheros de github, hacer una mínima configuración y ejecutar un script que vaya construyendo la configuración.

**Prerrequisitos**: docker *y docker-compose* instalado. Puertos 80 y 443 abiertos a la máquina en el firewall. Todo lo demás se instala dinámicamente mediante contenedores estándar. En ubuntu lo hicimos con https://docs.docker.com/engine/install/ubuntu/ 

**Advertencia**: usar mariadb en un contenedor puede no dar el rendimiento esperado... sería trivial modificar esto para que usara una base de datos en otro host o fuera del contenedor.

**Componentes:**
* config: configuración de la carpeta base del multimoodle y varias claves (ver más abajo). *Para no almacenar contraseñas en github, hay un config.example sin datos, que puede renombrarse*
* creadmoodle.sh - Pide un nombre de dominio y añade al multimoodle existente un nuevo moodle que atiende ahí por SSL.
* clonamoodle.sh - Toma como parámetro el "prefijo" (de un dominio "prefijo.ejemplo.com") ya existente en el multimoodle y un nuevo dominio y "clona" otro moodle exacto que ahora atiende en el nuevo dominio.
* borratodo.sh   - borra todos el multimoodle (usar con cuidado ;-)
* Dockerfile.moodle - pequeñas modificaciones a la imagen docker de bitnami para moodle.
* Ficheros de configuración que los scripts instalan luego en su sitio y manipulan para añadir nuevos componentes al multimoodle:
    * certbot.base.sh: script para arrancar certbot (un contenedor que encapsula la descarga de certificados de letsencrypt.org). La primera vez que se ejcuta creamoodle.sh, se copia a la carpeta certbot como certbot.sh
    * docker-compose-base.yml: esquema de partida del `docker-compose.yml` donde hay "placeholders" para ir añadiendo nuevos contenedores.
    * haproxy.base.cfg: esquema de partida del `haproxy.cfg` donde hay "placeholders" para ir añadiendo el acceso a los nuevos contenedores creados.

## Configuración inicial
* Instalar docker en el host.
* Crear una carpeta específica "multimoodle"
* Dentro de esa carpeta, hacer `git clone https://github.com/froxon/multimoodle-public.git .`
* Renombrar **MUY IMPORTANTE** config.example a config y ajustar las variables de configuración
    * BASE: la carpeta que hemos creado, por ejemplo "/root/multimoodle"
    * MARIADB_PWD una clave no especialmente fácil para el acceso root a la base de datos. La base de datos no es visible, pero... está bien que tenga una clave no trivial.
    * MOODLE_PWD_DATABASE: el prefijo por el que van a empezar todas las claves de acceso a la base de datos para el moodle. Por ejemplo, si aquí ponemos "#x98y", para un moodle en subdominio.ejemplo.com la clave de acceso a la base de datos será "#x98y_subdominio". **No es algo que vaya a verse desde fuera**
    * MOODLE_PWD_USER: el prefijo por el que van a empezar todas las claves de acceso al moodle. Por ejemplo, si aquí ponemos "ref!!23", para un moodle en subdominio.ejemplo.com la clave de acceso a la base de datos será "ref!!23_subdominio". **Esto sí se ve desde fuera, pero se puede cambiar luego**
* Para cada dominio que se quiera configurar:
    * Configurar el DNS: si quiero atender en "subdominio.ejemplo.com", en el hosting configuro "subdominio" como un CNAME del dominio principal (ejemplo.com), suponiendo que ejemplo.com está apuntando al host.
    * OJO: "subdominio" tiene que ser algo "normal", preferentemente letras y números sin nada más (no está probado otra cosa).
    * Si hay algún servicio corriendo en el puerto 80, hay que pararlo (necesario solo para certbot)
    * Lanzar creamoodle.sh
    * Una vez configurado todo, conectar con https://subdominio.ejemplo.com y entrar con usuario `admin_subdominio` y contraseña `ref!!23_subdominio`(la contraseña depende de cómo hayamos configurado MOODLE_PWD_USER).

## Funcionamiento de creamoodle.sh

1. Pide el dominio y hace un par de comprobaciones básicas para que no colisiones con otros.
2. Si es la primera vez que se ejecuta el script, se crean el `docker-compose.yml` y las carpetas `certbot` (con su `certbot.sh`), `mariadb` y `haproxy` con su `haproxy.cfg`. 
3. Obtención de certificado SSL: llama al certbot (cerbot.sh) para crear un certificado para dominio nuevo sub1.certbot.sh
4. Crea la nueva base de datos en mariadb: arranca el multimooodle si no está, y manda al contenedor de la base de datos los comandos necesarios.
5. **Tira todo el multimoodle para tocar los ficheros de configuración** Podría probar sin hacer este paso, pero es aceptable en el entorno original del script.
6. Añade al `docker-compose.yml` un nuevo contenedor bitnami-moodle configurado según se necesite y modifica la lista de dependencias del mariadb.
7. Añade al `haproxy.cfg` el nuevo certificado, la configuración de un nuevo subdominio para escuchar en el puerto 443 y la configuración del "backend" donde escucha el nuevo contenedor con moodle.
8. Levanta todo el multimoodle.
9. El nuevo contenedor lanza internamente la instalación de moodle (no se ve mucho)
10. Se "machaca" la configuración del moodle para decirle que está detrás de un proxyssl y cuál es el dominio para el que debe generar las URLs. Reinicia el moodle recién creado para tomar esta configuración.

* Referencias:
    * https://moodle.org/mod/forum/discuss.php?d=402281
    * https://www.blai.blog/2020/05/moodle-tras-un-reverse-proxy-nginx.html (OJO, que de esta receta no se puede hacer "reverse proxy". O sea, **no se debe poner** `$CFG->reverseproxy = true;`)
Alternativamente, se podría haber utilizado la misma base de código (carpeta moodle) utilizando una configuración específica por sitio. Generamos así ficheros **haproxy-moodle-config-XXXX.php** (donde XXXX es el nombre del sitio, por ejemplo "subdominio"). Esta configuración se carga después **siempre** con el mismo nombre en cada imagen. Por ejemplo, la configuración del *docker-compose.yml* para "subdominio" incluirá en la sección "volumes" la línea:
`      - '/root/localcir//haproxy-moodle-config-subdominio.php:/bitnami/moodle/haproxy-moodle-config.php'`en volumes.
Además, habría que poner en el config.php de moodle la línea `require_once(__DIR__ . '/haproxy-moodle-config.php');` (vale ponerla al final del config.php. **Configuración desechada, porque se pretende que la base de código de cada moodle pueda evolucionar de formas distintas. Son unos 340 MB en cada instalación.**)


