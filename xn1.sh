sysctl -w net.ipv6.conf.all.disable_ipv6=1 
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.core.rmem_max=2500000
sysctl -w net.core.wmem_max=2500000
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
rm -rf /etc/resolv.conf
    cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 8.8.8.8 
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
EOF
    cat > /etc/sysctl.conf << EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv6.conf.all.accept_dad = 1
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.all.accept_redirects = 1
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
vm.swappiness = 10
EOF
wget -qO- https://get.docker.com/ | sh
cd ${SATURN_HOME:-$HOME}
    cat > .env<< EOF
SATURN_NETWORK="main"
FIL_WALLET_ADDRESS="f1vfyzyjuvdwmwfjw4xzonc5ueuo2bdkff5tmtzki"
NODE_OPERATOR_EMAIL="x@xscp.org"
SPEEDTEST_SERVER_CONFIG=""
SATURN_HOME=""
EOF
curl -s https://raw.githubusercontent.com/filecoin-saturn/L1-node/main/docker-compose.yml -o docker-compose.yml
curl -s https://raw.githubusercontent.com/filecoin-saturn/L1-node/main/docker_compose_update.sh -o docker_compose_update.sh
chmod +x docker_compose_update.sh
apt-get install cron -y
(crontab -l 2>/dev/null; echo "*/5 * * * * cd $SATURN_HOME && sh docker_compose_update.sh >> docker_compose_update.log 2>&1") | crontab -
sudo docker compose up -d
docker logs -f -n 100 saturn-node
