#!/bin/bash
sudo ufw allow 1:65000/udp
sudo ufw allow 1:65000/tcp
curl -o apphub-linux-amd64.tar.gz https://assets.coreservice.io/public/package/60/app-market-gaga-pro/1.0.4/app-market-gaga-pro-1_0_4.tar.gz && tar -zxf apphub-linux-amd64.tar.gz && rm -f apphub-linux-amd64.tar.gz && cd ./apphub-linux-amd64
sudo ./apphub service remove && sudo ./apphub service install
sudo ./apphub service start
sleep 15
sudo ./apps/gaganode/gaganode config set --token=mgmxwoxomweqsoltac31d1c1adf6b598
./apphub restart
sleep 10
./apphub status
