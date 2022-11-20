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

function install_nginx {
cat <<EOF > /etc/nginx/nginx.conf
        user   www-data;
        worker_processes  auto;

        error_log  /var/log/nginx/error.log info;
        pid        /var/run/nginx.pid;

        events {
                worker_connections  1024;
        }

        http {
          include       mime.types;
          default_type  application/octet-stream;

          log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                                                '\$status \$body_bytes_sent "\$http_referer" '
                                                '"\$http_user_agent" "\$http_x_forwarded_for"';
          access_log  /var/log/nginx/access.log  main;

          # Include separate files in the main "http{}" configuration
          include  conf.d/*.conf;

          # Allow status requests from localhost
          server
          {
                listen 127.0.0.1;
                server_name localhost;

                location /nginx_status {
                  stub_status on; # activate stub_status module
                  access_log off;
                  allow 127.0.0.1; # localhost
                  allow ::1; # localhost
                  deny all;
                }
          }

          include upstream/*.conf;
        }
EOF

cat <<EOF > /etc/nginx/conf.d/performance.conf
sendfile              on;
tcp_nopush            on;
tcp_nodelay           on;
keepalive_timeout     10;
send_timeout 10;
types_hash_max_size   2048;
client_max_body_size  20M;
client_body_timeout 10;
client_header_timeout 10;
large_client_header_buffers 8 16k;
EOF

cat <<EOF > /etc/nginx/conf.d/gzip.conf
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
EOF

mkdir -p /etc/nginx/ssl
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
chmod 400 /etc/nginx/ssl/dhparam.pem

cat <<EOF > /etc/nginx/conf.d/ssl.conf
# Diffie-Hellman parameters
ssl_dhparam /etc/nginx/ssl/dhparam.pem;

# SSL settings
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;

ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

ssl_session_cache shared:SSL:20m;
ssl_session_timeout 20m;
ssl_session_tickets off;

# SSL OCSP stapling
ssl_stapling         on;
ssl_stapling_verify  on;

# DNS resolver configuration for OCSP response
resolver          8.8.4.4 8.8.8.8 valid=300s ipv6=off;
resolver_timeout  10s;
EOF

cat <<EOF > /etc/nginx/conf.d/security.conf
# Hide nginx server version
server_tokens off;
EOF

}

function install_upstream {
        mkdir -p /etc/nginx/upstream
        cat <<EOF > /etc/nginx/upstream/${HOSTNAME}.conf
          server {
                server_name  $HOSTNAME;
                location / {
                  proxy_pass        http://localhost:${OPENHIM_CONSOLE_EXPOSED_PORT};
                  proxy_set_header   Host \$host;
                  proxy_set_header   X-Real-IP \$remote_addr;
                  proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
                  proxy_set_header   X-Forwarded-Host \$server_name;
                }
				
				location /api/ {
                  proxy_pass        http://localhost:${OPENHIM_CORE_API_EXPOSED_PORT};
                  proxy_set_header   Host \$host;
                  proxy_set_header   X-Real-IP \$remote_addr;
                  proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
                  proxy_set_header   X-Forwarded-Host \$server_name;
                }

                listen 443 ssl; # managed by Certbot
                ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;
                ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;
          }


          server {
                if (\$host = $HOSTNAME) {
                        return 301 https://\$host\$request_uri;
                }


                server_name  $HOSTNAME;

            listen 80;
                return 404;
          }
EOF
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

if [ $# -ne 1 ]; then
        echo "Usage: install.sh <HOSTNAME>"
        exit 1
fi

HOSTNAME="$1"
HOSTNAME_ENV=$(grep HOSTNAME .env | awk -F '=' '{printf $2}')

CONTAINERS=$(docker ps | grep "_${HOSTNAME}")
CONTAINERS_ENV=$(docker ps | grep "_${HOSTNAME_ENV}")

if [[ $CONTAINERS != "" ]]; then
  echo "OpenHIM containers are already running with provided hostname: ${HOSTNAME}"
  exit 1
fi

if [[ $CONTAINERS_ENV != "" ]]; then
  echo "OpenHIM containers are already running with current hostname in .env: ${HOSTNAME_ENV}"
  exit 1
fi

#Configure OpenHIM-core
OPENHIM_CORE_VERSION=$(grep OPENHIM_CORE_VERSION .env | awk -F '=' '{printf $2}')
mkdir -p ./conf/openhim-core
wget https://raw.githubusercontent.com/jembi/openhim-core-js/v${OPENHIM_CORE_VERSION}/config/default.json -O ./conf/openhim-core/default.json &> /dev/null
LOGGER_LEVEL=$(grep LOGGER_LEVEL .env | awk -F '=' '{printf $2}')
jq '.logger.level = "${LOGGER_LEVEL}"' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq '.router.externalHostname = "${HOSTNAME}"' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq '.certificateManagement.watchFSForCert = true' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq '.certificateManagement.certPath = "/app/resources/certs/fullchain.pem"' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json
jq '.certificateManagement.keyPath = "/app/resources/certs/privkey.pem"' ./conf/openhim-core/default.json > ./conf/openhim-core/default.tmp && mv ./conf/openhim-core/default.tmp ./conf/openhim-core/default.json

#Configure OpenHIM-console
OPENHIM_CONSOLE_VERSION=$(grep OPENHIM_CONSOLE_VERSION .env | awk -F '=' '{printf $2}')
mkdir -p ./conf/openhim-console
wget https://raw.githubusercontent.com/jembi/openhim-console/v${OPENHIM_CONSOLE_VERSION}/app/config/default.json -O ./conf/openhim-console/default.json &> /dev/null
jq '.host = "${HOSTNAME}"' ./conf/openhim-console/default.json > ./conf/openhim-console/default.tmp && mv ./conf/openhim-console/default.tmp ./conf/openhim-console/default.json
jq '.hostPath = "api"' ./conf/openhim-console/default.json > ./conf/openhim-console/default.tmp && mv ./conf/openhim-console/default.tmp ./conf/openhim-console/default.json
jq '.port = 443' ./conf/openhim-console/default.json > ./conf/openhim-console/default.tmp && mv ./conf/openhim-console/default.tmp ./conf/openhim-console/default.json

echo "Installing docker and docker-compose"
apt update &> /dev/null
apt install docker docker-compose jq unzip -y &> /dev/null

echo "Setting hostname: $HOSTNAME"
sed -i "s/HOST_NAME/${HOSTNAME}/g" ./docker-compose.yml .env ./activatelogin.sh

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

echo "Configuring nginx"
if ! which nginx 1>/dev/null; then
  apt update &> /dev/null
  apt install nginx -y &> /dev/null
  install_nginx
fi

if ! which certbot 1>/dev/null; then
  sudo snap install --classic certbot &> /dev/null
  sudo ln -s /snap/bin/certbot /usr/bin/certbot &> /dev/null
  service nginx stop
  if ! certbot certonly -d $HOSTNAME --standalone -m daniel.castelao@solidlines.io --agree-tos -n --no-eff-email; then
    errout "Failed when installing certificate"
  fi
  install_upstream
  service nginx start
else
  service nginx stop
  if ! certbot certonly -d $HOSTNAME --standalone -m daniel.castelao@solidlines.io --agree-tos -n --no-eff-email; then
    errout "Failed when installing certificate"
  fi
  install_upstream
  service nginx start
fi

GREP=$(grep -l $HOSTNAME /etc/hosts)
if [[ $GREP != "/etc/hosts" ]]; then
  echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
fi

echo "Building and creating docker containers"
if ! docker-compose up --build -d; then
  errout "Failed docker-compose" 1>&2
fi

echo "Successfully installed openhim."
echo "Activate root login executing ./activatelogin.sh  (Port 8080 has to be open)"
echo "Go to https://$HOSTNAME (root@openhim.org/openhim-password) and change root@openhim.org password"

