version: '3.3'
services:  
  network3-01:    
    image: aron666/network3-ai    
    container_name: network3-01    
    ports:      
      - 8080:8080/tcp
    environment:
      # 自動綁定用，your-email-to-bind 改成你 network3 的 Email
      - EMAIL=matthews.macconaughey@gmail.com
    volumes:
      - /root/wireguard:/usr/local/etc/wireguard    
    healthcheck:      
      test: curl -fs http://localhost:8080/ || exit 1      
      interval: 30s      
      timeout: 5s      
      retries: 5      
      start_period: 30s    
    privileged: true    
    devices:      
      - /dev/net/tun    
    cap_add:      
      - NET_ADMIN    
    restart: always

  autoheal:    
    restart: always    
    image: willfarrell/autoheal    
    container_name: autoheal    
    environment:      
      - AUTOHEAL_CONTAINER_LABEL=all    
    volumes:      
      - /var/run/docker.sock:/var/run/docker.sock
