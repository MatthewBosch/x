cd /home
curl -s https://github.com/MatthewBosch/x/blob/main/docker-compose.yaml -o docker-compose.yml
iptables -P INPUT ACCEPT   
iptables -P OUTPUT ACCEPT 
wget -qO- https://get.docker.com/ | sh
docker compose up -d 
docker compose logs --tail=1000 -f
