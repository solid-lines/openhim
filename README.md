# OpenHIM-docker-compose

Run: ./install.sh \<HOSTNAME\>

1. Update server
2. Add the given \<HOSTNAME\> to the configuration files
3. Build and create docker containers
4. Update Nginx configuration files
  
Activate root login executing ./activatelogin.sh  (Port 8080 has to be open)
Go to https://\<HOSTNAME\> (root@openhim.org/openhim-password) and change root@openhim.org password


![docker-compose-openhim yml](https://user-images.githubusercontent.com/48926694/193571492-1858d6e5-97d0-4014-9647-670d9a315a55.png)

