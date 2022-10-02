# OpenHIM-docker-compose

Run: ./install.sh \<HOSTNAME\>

1. Update server
2. Add the given \<HOSTNAME\> to the configuration files
3. Build and create docker containers
4. Update Nginx configuration files
  
Activate root login executing ./activatelogin.sh  (Port 8080 has to be open)
Go to https://\<HOSTNAME\> (root@openhim.org/openhim-password) and change root@openhim.org password
