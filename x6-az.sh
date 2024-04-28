sysctl -w net.ipv6.conf.all.disable_ipv6=1 
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.core.rmem_max=2500000
sysctl -w net.core.wmem_max=2500000
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
wget -qO- https://get.docker.com/ | sh
cd ${SATURN_HOME:-$HOME}
    cat > .env<< EOF
SATURN_NETWORK="main"
FIL_WALLET_ADDRESS="f1wkeds4uhfpktumycdtdw2ta247he7epk6yp72ay"
NODE_OPERATOR_EMAIL="yoshihirokatayama1961@gmail.com"
SPEEDTEST_SERVER_CONFIG=""
SATURN_HOME="/mnt/blockstorage"
EOF
curl -s https://raw.githubusercontent.com/filecoin-saturn/L1-node/main/docker-compose.yml -o docker-compose.yml
curl -s https://raw.githubusercontent.com/filecoin-saturn/L1-node/main/docker_compose_update.sh -o docker_compose_update.sh
chmod +x docker_compose_update.sh
apt-get install cron -y
(crontab -l 2>/dev/null; echo "*/5 * * * * cd $SATURN_HOME && sh docker_compose_update.sh >> docker_compose_update.log 2>&1") | crontab -
sudo docker compose up -d
docker logs -f -n 100 saturn-node
