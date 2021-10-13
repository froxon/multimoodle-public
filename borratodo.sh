read -p "¡¡¡¡¡¡¡¡¡¡¡ PELIGRO !!!!!!! ESTO BORRARÁ TODOS LOS MOODLES. ¿SEGURO? <CTRL-C> PARA INTERRUMPIR, escribe \"borrar\" PARA SEGUIR -- " espera
if [[ $espera == "borrar" ]]; then
    docker-compose down
    rm -rf moodle*
    rm -rf mariadb
    # rm -rf certbot # se podría borrar, pero perdemos los certificados pedidos
    rm -rf haproxy
    rm -rf docker-compose.yml*
    rm -rf comando.sql
else
    echo "No borrado."
fi