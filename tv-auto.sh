#!/bin/bash

# Install Docker
wget -qO- https://get.docker.com/ | sh

sleep 5

# Create docker-compose.yml file
cat <<EOF > /root/docker-compose.yml
version: '3.0'
services:

  titan1: 
    image: aron666/aron-titan-edge
    container_name: titan1
    environment:
      AppConfig__TITAN_NETWORK_LOCATORURL: "https://cassini-locator.titannet.io:5000/rpc/v0"
      AppConfig__TITAN_STORAGE_STORAGEGB: "22"
      AppConfig__TITAN_STORAGE_PATH: ""
      AppConfig__TITAN_EDGE_BINDING_URL: "https://api-test1.container1.titannet.io/api/v2/device/binding"
      AppConfig__TITAN_EDGE_ID: "1E80B06C-06E1-498E-AA11-4F1C3A5DAE5F"
    restart: always
    volumes:
      - ~/.titanedge:/root/.titanedge
    ports:
      - "1234:1234"
      - "1234:1234/udp"
EOF

sleep 5

# Run Docker Compose
docker compose up -d
