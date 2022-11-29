#!/bin/bash

function getNextPort() {
        INIT_PORT="${1}"
        LIMIT_PORT="${2}"
        FINAL_PORT=$(( $INIT_PORT + $LIMIT_PORT ))
        for PORT in $(seq ${INIT_PORT} ${FINAL_PORT})
        do
                NETSTAT=$(netstat -utna | grep ${PORT})
                if [[ $NETSTAT == "" ]]; then
                        AVAILABLE_PORT=$PORT
                        break
                fi
        done
}

# Send error output and exit with status code 1
function errout {
  echo "ERROR: $*, exiting..." >&2
  echo "========================================================="
  docker-compose down
  sed -i "s/$HOSTNAME/HOST_NAME/g" ./docker-compose.yml .env ./activatelogin.sh
  rm -rf /etc/nginx/upstream/${HOSTNAME}.conf
  exit 1
}

HOSTNAME="localhost"
HOSTNAME_ENV=$(grep HOSTNAME .env | awk -F '=' '{printf $2}')

CONTAINERS=$(docker ps | grep "openhim-core_${HOSTNAME}")
CONTAINERS_ENV=$(docker ps | grep "openhim-core_${HOSTNAME_ENV}")

if [[ $CONTAINERS != "" ]]; then
  echo "OpenHIM containers are already running in localhost"
  exit 1
fi

if [[ $CONTAINERS_ENV != "" ]]; then
  echo "OpenHIM containers are already running with current hostname in .env: ${HOSTNAME_ENV}"
  exit 1
fi

# Change exposed port to the next available one. Parameters: Initial Port and Limit Port
OPENHIM_CORE_API_EXPOSED_PORT=$(grep OPENHIM_CORE_API_EXPOSED_PORT .env | awk -F '=' '{printf $2}')
getNextPort "$OPENHIM_CORE_API_EXPOSED_PORT" "1000"
sed -i "s/OPENHIM_CORE_API_EXPOSED_PORT=$OPENHIM_CORE_API_EXPOSED_PORT/OPENHIM_CORE_API_EXPOSED_PORT=$AVAILABLE_PORT/g" .env
echo "OpenHIM-core API docker service will be exposed on port: $AVAILABLE_PORT"
OPENHIM_CORE_API_EXPOSED_PORT=$AVAILABLE_PORT

OPENHIM_CORE_HTTPS_EXPOSED_PORT=$(grep OPENHIM_CORE_HTTPS_EXPOSED_PORT .env | awk -F '=' '{printf $2}')
getNextPort "$OPENHIM_CORE_HTTPS_EXPOSED_PORT" "1000"
sed -i "s/OPENHIM_CORE_HTTPS_EXPOSED_PORT=$OPENHIM_CORE_HTTPS_EXPOSED_PORT/OPENHIM_CORE_HTTPS_EXPOSED_PORT=$AVAILABLE_PORT/g" .env
echo "OpenHIM-core HTTPS docker service will be exposed on port: $AVAILABLE_PORT"
OPENHIM_CORE_HTTPS_EXPOSED_PORT=$AVAILABLE_PORT

OPENHIM_CORE_HTTP_EXPOSED_PORT=$(grep OPENHIM_CORE_HTTP_EXPOSED_PORT .env | awk -F '=' '{printf $2}')
getNextPort "$OPENHIM_CORE_HTTP_EXPOSED_PORT" "1000"
sed -i "s/OPENHIM_CORE_HTTP_EXPOSED_PORT=$OPENHIM_CORE_HTTP_EXPOSED_PORT/OPENHIM_CORE_HTTP_EXPOSED_PORT=$AVAILABLE_PORT/g" .env
echo "OpenHIM-core HTTP docker service will be exposed on port: $AVAILABLE_PORT"
OPENHIM_CORE_HTTP_EXPOSED_PORT=$AVAILABLE_PORT

OPENHIM_CORE_POOLING_EXPOSED_PORT=$(grep OPENHIM_CORE_POOLING_EXPOSED_PORT .env | awk -F '=' '{printf $2}')
getNextPort "$OPENHIM_CORE_POOLING_EXPOSED_PORT" "1000"
sed -i "s/OPENHIM_CORE_POOLING_EXPOSED_PORT=$OPENHIM_CORE_POOLING_EXPOSED_PORT/OPENHIM_CORE_POOLING_EXPOSED_PORT=$AVAILABLE_PORT/g" .env
echo "OpenHIM-core Pooling docker service will be exposed on port: $AVAILABLE_PORT"
OPENHIM_CORE_POOLING_EXPOSED_PORT=$AVAILABLE_PORT

OPENHIM_CONSOLE_EXPOSED_PORT=$(grep OPENHIM_CONSOLE_EXPOSED_PORT .env | awk -F '=' '{printf $2}')
getNextPort "$OPENHIM_CONSOLE_EXPOSED_PORT" "1000"
sed -i "s/OPENHIM_CONSOLE_EXPOSED_PORT=$OPENHIM_CONSOLE_EXPOSED_PORT/OPENHIM_CONSOLE_EXPOSED_PORT=$AVAILABLE_PORT/g" .env
echo "OpenHIM-console docker service will be exposed on port: $AVAILABLE_PORT"
OPENHIM_CONSOLE_EXPOSED_PORT=$AVAILABLE_PORT

MONGO_EXPOSED_PORT=$(grep MONGO_EXPOSED_PORT .env | awk -F '=' '{printf $2}')
getNextPort "$MONGO_EXPOSED_PORT" "1000"
sed -i "s/MONGO_EXPOSED_PORT=$MONGO_EXPOSED_PORT/MONGO_EXPOSED_PORT=$AVAILABLE_PORT/g" .env
echo "Mongo docker service will be exposed on port: $AVAILABLE_PORT"
MONGO_EXPOSED_PORT=$AVAILABLE_PORT

#Configure OpenHIM-core
OPENHIM_CORE_VERSION=$(grep OPENHIM_CORE_VERSION .env | awk -F '=' '{printf $2}')
mkdir -p ./conf/openhim-core
wget https://raw.githubusercontent.com/jembi/openhim-core-js/v${OPENHIM_CORE_VERSION}/config/default.json -O ./conf/openhim-core/default.json &> /dev/null
LOGGER_LEVEL=$(grep LOGGER_LEVEL .env | awk -F '=' '{printf $2}')
jq -r --arg LOGGER "$LOGGER_LEVEL" '.logger.level = $LOGGER' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq -r --arg HOST "$HOSTNAME" '.router.externalHostname = $HOST' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq -r '.certificateManagement.watchFSForCert = true' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq -r '.certificateManagement.certPath = "/app/resources/certs/fullchain.pem"' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq -r '.certificateManagement.keyPath = "/app/resources/certs/privkey.pem"' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json

#Configure OpenHIM-console
OPENHIM_CONSOLE_VERSION=$(grep OPENHIM_CONSOLE_VERSION .env | awk -F '=' '{printf $2}')
mkdir -p ./conf/openhim-console
wget https://raw.githubusercontent.com/jembi/openhim-console/v${OPENHIM_CONSOLE_VERSION}/app/config/default.json -O ./conf/openhim-console/default.json &> /dev/null
jq -r --arg HOST "$HOSTNAME" '.host = $HOST' ./conf/openhim-console/default.json > ./conf/openhim-console/default.tmp && mv ./conf/openhim-console/default.tmp ./conf/openhim-console/default.json
jq -r '.hostPath = "api"' ./conf/openhim-console/default.json > ./conf/openhim-console/default.tmp && mv ./conf/openhim-console/default.tmp ./conf/openhim-console/default.json
jq -r '.port = 443' ./conf/openhim-console/default.json > ./conf/openhim-console/default.tmp && mv ./conf/openhim-console/default.tmp ./conf/openhim-console/default.json

echo "Installing docker and docker-compose"
apt update &> /dev/null
apt install docker docker-compose jq unzip -y &> /dev/null

echo "Setting hostname: $HOSTNAME"
sed -i "s/HOST_NAME/${HOSTNAME}/g" ./docker-compose.yml .env ./activatelogin.sh

GREP=$(grep -l $HOSTNAME /etc/hosts)
if [[ $GREP != "/etc/hosts" ]]; then
  echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
fi

echo "Building and creating docker containers"
if ! docker-compose up --build -d; then
  errout "Failed docker-compose" 1>&2
fi

#Update bundle.js
docker exec -ti $(docker container ls | grep openhim-console_${HOSTNAME} | awk '{printf $1}') sed -i "s/\"host\":\"localhost\"/\"host\":\"${HOSTNAME}\"/g" /usr/share/nginx/html/bundle.js
docker exec -ti $(docker container ls | grep openhim-console_${HOSTNAME} | awk '{printf $1}') sed -i "s/\"port\":8080/\"port\":${OPENHIM_CORE_API_EXPOSED_PORT}/g" /usr/share/nginx/html/bundle.js

echo "Successfully installed openhim."
echo ""
echo "Go to https://$HOSTNAME/authenticate/root@openhim.org  to activate root login"
echo ""
echo "Go to https://$HOSTNAME (root@openhim.org/openhim-password) and change root@openhim.org password"
