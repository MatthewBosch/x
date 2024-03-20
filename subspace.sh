cd /home
curl -s https://github.com/MatthewBosch/x/blob/main/docker-compose.yaml -o docker-compose.yml
iptables -P INPUT ACCEPT   
iptables -P OUTPUT ACCEPT 
docker compose up -d 
docker compose logs --tail=1000 -f
