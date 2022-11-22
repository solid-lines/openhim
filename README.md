# OpenHIM-docker-compose
All the commands are assuming that the target installation folder for OpenHIM is `/opt/openhim-docker'

## Install OpenHIM docker containers
1. `cd /opt`
2. `git clone https://github.com/solid-lines/openhim-docker.git`
3. `cd /opt/openhim-docker`
4. You can modify the environment variables used by OpenHIM containers by editing the .env file
5. `./install.sh HOSTNAME`
6. Go to https://HOSTNAME/authenticate/root@openhim.org  to activate root login
7. Go to https://HOSTNAME (root@openhim.org/openhim-password) and change root@openhim.org password
8. You can create a superuser running the script `./createsuperuser.sh`


Run: ./install.sh \<HOSTNAME\>

1. Update server
2. Add the given \<HOSTNAME\> to the configuration files
3. Build and create docker containers
4. Update Nginx configuration files
  
## Uninstall OpenHIM docker containers
1. `cd /opt/openhim-docker`
2. `./uninstall.sh`

## Modify OpenHIM docker containers
1. `cd /opt/openhim-docker`
2. Modify the environment variables used by OpenHIM containers by editing the .env file
3. `./restart_containers.sh`

## .env file settings
### Set up the OpenHIM-core, OpenHIM-console and MongoDB version
* OPENHIM_CORE_VERSION (default is 7.0.2)
* OPENHIM_CONSOLE_VERSION (default is 1.14.3)
* MONGO_VERSION (default is 3.4)
### Set up Logger Level
* LOGGER_LEVEL
