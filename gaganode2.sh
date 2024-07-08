#!/bin/bash
sudo ./apps/gaganode/gaganode config set --token=mgmxwoxomweqsoltac31d1c1adf6b598
./apphub restart
sleep 10
./apphub status
