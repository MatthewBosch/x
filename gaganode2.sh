#!/bin/bash
cd root/apphub-linux-amd64
./apphub status
sleep 20
sudo ./apps/gaganode/gaganode config set --token=mgmxwoxomweqsoltac31d1c1adf6b598
./apphub restart
sleep 10
./apphub status
