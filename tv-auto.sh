#!/bin/bash

# Create docker-compose.yml file
cat <<EOF > docker-compose.yml
version: '3.0'
services:

  titan1: 
    image: aron666/aron-titan-edge
    container_name: titan1
    environment:
      AppConfig__TITAN_NETWORK_LOCATORURL: "https://test-locator.titannet.io:5000/rpc/v0"
      AppConfig__TITAN_STORAGE_STORAGEGB: "22"
      AppConfig__TITAN_STORAGE_PATH: ""
      AppConfig__TITAN_EDGE_BINDING_URL: "https://api-test1.container1.titannet.io/api/v2/device/binding"
      AppConfig__TITAN_EDGE_ID: "EFCF32A4-16D5-4559-B7E1-74F60FCB7D48"
    restart: always
    volumes:
      - ~/.titanedge:/root/.titanedge
    ports:
    - 1234:1234/tcp
    - 1234:1234/udp

EOF

# Install Docker
wget -qO- https://get.docker.com/ | sh

# Run Docker Compose
docker compose up -d
