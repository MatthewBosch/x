iptables -P INPUT ACCEPT   
iptables -P OUTPUT ACCEPT  
wget -qO- https://get.docker.com/ | sh
    cat > docker-compose.yaml<< EOF
version: "3.7"
services:
  node:
    image: ghcr.io/subspace/node:gemini-3h-2024-mar-14
    volumes:
      - node-data:/var/subspace:rw
    ports:
      - "0.0.0.0:30333:30333/udp"
      - "0.0.0.0:30333:30333/tcp"
      - "0.0.0.0:30433:30433/udp"
      - "0.0.0.0:30433:30433/tcp"
    restart: unless-stopped
    command:
      [
        "run",
        "--chain", "gemini-3h",
        "--base-path", "/var/subspace",
        "--listen-on", "/ip4/0.0.0.0/tcp/30333",
        "--dsn-listen-on", "/ip4/0.0.0.0/udp/30433/quic-v1",
        "--dsn-listen-on", "/ip4/0.0.0.0/tcp/30433",
        "--rpc-cors", "all",
        "--rpc-methods", "unsafe",
        "--rpc-listen-on", "0.0.0.0:9944",
        "--farmer",
        "--name", "subspace"
      ]
    healthcheck:
      timeout: 5s
      interval: 30s
      retries: 60

  farmer:
    depends_on:
      node:
        condition: service_healthy
    image: ghcr.io/subspace/farmer:gemini-3h-2024-mar-14
    volumes:
      - farmer-data:/var/subspace:rw
    ports:
      - "0.0.0.0:30533:30533/udp"
      - "0.0.0.0:30533:30533/tcp"
    restart: unless-stopped
    command:
      [
        "farm",
        "--node-rpc-url", "ws://node:9944",
        "--listen-on", "/ip4/0.0.0.0/udp/30533/quic-v1",
        "--listen-on", "/ip4/0.0.0.0/tcp/30533",
        "--reward-address", "stBjdw2Kp3rxxc6m16gBHYWNeA9FJcJkSDELk7uiA5mfdrYJP",
        "path=/var/subspace,size=500G"
      ]
volumes:
  node-data:
  farmer-data:            
EOF
docker compose up -d 
docker compose logs --tail=1000 -f
