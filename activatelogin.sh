CONTAINER_ID=docker ps | grep 'openhim-core' | grep -v celery | awk '{print $1}'
docker exec -ti $CONTAINER_ID apk add curl; curl -k https://HOST_NAME:8080/authenticate/root@openhim.org

