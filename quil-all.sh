#!/bin/bash

ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
ITALIC='\033[3m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

echo ""
echo ""
echo ""
echo -e "${BLUE}"
echo "  ██╗  ██╗ █████╗ ███████╗██╗  ██╗ █████╗ ██╗    "
echo "  ██║  ██║██╔══██╗██╔════╝██║  ██║██╔══██╗██║    "
echo "  ███████║███████║███████╗███████║███████║██║    "
echo "  ██╔══██║██╔══██║╚════██║██╔══██║██╔══██║██║    "
echo -e "  ██║  ██║██║  ██║███████║██║  ██║██║  ██║██║ "
echo -e "  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝ "
echo ""
echo -e "${CYAN}                 MINING TOOLS                  ${RESET}"
echo -e "${ITALIC}${BOLD}             WWW.ADVANCED-HASH.AI              ${RESET}"
echo ""
echo -e " ${BOLD}   QUIL - Cluster Tools ${RED}${ITALIC}(Linux BETA v0.1.1) 🛠️   ${RESET}"
echo ""

CONFIG_PATH="$HOME/ceremonyclient/node/.config/config.yml"

generate_data_worker_multiaddrs() {
  local ip=$1
  local threads=$2
  local start_port=40001
  local ports=()

  if [[ $is_master == "true" ]]; then
    threads=$((threads - 1))
  fi

  for ((i=0; i<threads; i++)); do
    ports+=("'/ip4/$ip/tcp/$((start_port + i))'")
  done

  echo "${ports[@]}"
}

update_remote_config() {
  local ip=$1

  temp_config="/tmp/remote_config_$ip.yml"
  echo -e "$cluster_config" > "$temp_config"

  echo -e "\n⏳ Updating configuration on ${BOLD}$ip...${RESET}"

  sshpass -p "$password" scp -o StrictHostKeyChecking=no "$temp_config" "$session_"@$ip:/tmp/cluster_config.yml

  SSH_COMMAND="
    sed -i '/engine:/r /tmp/cluster_config.yml' $CONFIG_PATH &&
    rm /tmp/cluster_config.yml
  "

  sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$session_"@$ip "$SSH_COMMAND"

  if [ $? -eq 0 ]; then
    echo -e ""
    echo -e "✅ Configuration successfully updated on${BOLD} $ip.${RESET}"
  else
    echo -e ""
    echo -e "❌ Error: Failed to update configuration on${BOLD} $ip.${RESET}"
  fi

  rm -f "$temp_config"
}

check_rigs_accessible() {
  local rigs=("${@}")
  for rig in "${rigs[@]}"; do
    echo -e ""
    echo -e "🟡  Checking accessibility of node ${BOLD}$rig...${RESET}"

    if ! ping -c 1 "$rig" &> /dev/null; then
      echo -e ""
      echo -e "❌ ${RED}${BOLD} Error: Unable to reach node $rig. Please check the connection.${RESET}"
      exit 1
    fi
  done
}

generate_suggested_commands() {
  local master_threads=$1
  local master_ip=$2
  local slaves_ips=("${@:3}")
  
  echo -e "\n\n\nℹ️ ${GREEN}${BOLD} Commands to start the cluster:${RESET}${RESET}"
  echo -e ""
  # Command for the master
  echo -e "${ORANGE}${BOLD}Master${RESET}${RESET} ($master_ip) :"
  echo "screen -dmS quil bash para.sh linux amd64 0 $master_threads 2.0.4"

  # Commands for the slaves
  local previous_threads=$((master_threads - 1)) # Threads for the first slave
  for i in "${!slaves_ips[@]}"; do
    local slave_ip="${slaves_ips[$i]}"
    echo -e ""
    echo -e "${YELLOW}Slave${RESET} ($slave_ip) :"
    echo "screen -dmS quil bash para.sh linux amd64 $previous_threads $master_threads 2.0.4"
    # Update for the next slave
    previous_threads=$((previous_threads + master_threads))
  done

}

generate_start_commands() {
  local threads=$1
  local master_ip=$2
  local slaves_ips=("${@:3}")

  master_command="screen -dmS quil bash para.sh linux amd64 0 $threads 2.0.4"
  
  slave_commands=()
  slave_idx=1
  slave_threads=$((threads - 1))  # Slave 1 starts with threads - 1
  
  for ip in "${slaves_ips[@]}"; do
    # Calculate threads for each slave
    slave_command="screen -dmS quil bash para.sh linux amd64 $slave_threads $threads 2.0.4"
    slave_commands+=("$slave_command")
    # Update thread count for the next slave
    slave_threads=$((slave_threads + threads))
  done

  echo -e "\n\n\nℹ️ ${GREEN}${BOLD} Commands to start the cluster:${RESET}${RESET}"
  echo -e "\n${ORANGE}${BOLD}Master${RESET}${RESET} ($master_ip) : $master_command"
  for i in "${!slaves_ips[@]}"; do
    echo -e "${YELLOW}Slave${RESET} (${slaves_ips[$i]}) : ${slave_commands[$i]}"
  done
  
  read -p "Do you want to execute these commands on remote nodes? (y/n) : " confirm
  if [[ "$confirm" == "y" ]]; then
  echo ""
  read -p "Enter the username for your machines: " session_
  echo ""
  read -sp "Enter the password for the session: " password
  echo ""
    for i in "${!slave_commands[@]}"; do
      slave_ip="${slaves_ips[$i]}"
      slave_command="${slave_commands[$i]}"
      echo ""
      echo -e "🟡 ${YELLOW}Executing command for the slave on ${BOLD}$slave_ip...${RESET}"
      echo ""
      sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$session_"@"$slave_ip" "cd $HOME/ceremonyclient/node && $slave_command"
      if [ $? -eq 0 ]; then
        echo -e "🟢 ${GREEN} Command for the slave successfully sent to${RESET} $slave_ip."
      else
        echo -e "🔴 ${RED} Error sending command for the slave to${RESET} $slave_ip."
      fi
    done
    echo ""
    echo -e "⏳ Waiting 15 seconds before executing the command for the master..."
    sleep 15
    echo ""
    echo -e "🟡 ${YELLOW} Executing command for the master on ${BOLD}$master_ip...${RESET}"
    echo ""
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$session_"@"$master_ip" "cd $HOME/ceremonyclient/node && $master_command"
    if [ $? -eq 0 ]; then
      echo -e "🟢 ${GREEN} Command for the ${BOLD}Master${RESET} successfully sent to${RESET} $master_ip."
    else
      echo -e "🔴 ${RED} Error sending command for the Master to${RESET} $master_ip."
    fi

    echo -e "✅ ${GREEN}${BOLD} Cluster successfully started on remote nodes.${RESET} 🚀"
  else
    echo -e "❌ ${RED}${BOLD} Operation cancelled by the user.${RESET}"
  fi
}

save_cluster_configuration() {
  local filename=$1
  local master_ip=$2
  local master_threads=$3
  shift 3
  local slaves_ips=("$@")

  local json_content="{\n"
  json_content+="  \"master_ip\": \"$master_ip\",\n"
  json_content+="  \"master_threads\": $master_threads,\n"
  json_content+="  \"slaves\": [\n"

  for i in "${!slaves_ips[@]}"; do
    if [ $i -lt $((${#slaves_ips[@]} - 1)) ]; then
      json_content+="    \"${slaves_ips[$i]}\",\n"
    else
      json_content+="    \"${slaves_ips[$i]}\"\n"
    fi
  done

  json_content+="  ]\n"
  json_content+="}"

  # Save to a file
  echo -e "$json_content" > "$filename"
  echo -e "\n\n\n📁 Configuration saved to file: ${YELLOW}${BOLD}$filename${RESET} \n"
}

start_cluster_from_file() {
  read -p "Enter the path to the configuration file (ex: /path/to/cluster.json) : " config_file

  if [ ! -f "$config_file" ]; then
    echo -e "\n❌ ${RED}File not found: ${BOLD}$config_file${RESET}"
    exit 1
  fi

  if ! jq empty "$config_file" &>/dev/null; then
    echo -e "\n❌ ${RED}The JSON file is invalid. Please check its syntax.${RESET}"
    exit 1
  fi

  master_ip=$(jq -r '.master_ip' "$config_file")
  master_threads=$(jq -r '.master_threads' "$config_file")
  
  slaves_ips=()
  while IFS= read -r slave; do
    slaves_ips+=("$slave")
  done < <(jq -r '.slaves[]' "$config_file")

  echo -e "\n📄 Loading configuration:"
  echo -e "   Master IP: $master_ip"
  echo -e "   Master Threads: $master_threads"
  echo -e "   Slaves: ${slaves_ips[*]}"

  generate_start_commands "$master_threads" "$master_ip" "${slaves_ips[@]}"
}

# Main menu
echo -e ""
echo -e "---------- ${CYAN}${BOLD}MAIN MENU${RESET}${RESET} ----------"
echo -e ""
echo -e "${BOLD}1.${RESET} ${YELLOW}Start a cluster manually${RESET} ⚡"
echo -e "${BOLD}2.${RESET} ${YELLOW}Start a cluster from a saved file${RESET} 📄"
echo -e "${BOLD}3.${RESET} ${YELLOW}Configure a new cluster${RESET} 🔧"
echo ""
read -p "Please choose an option (1, 2 or 3) : " choice

if [[ "$choice" == "1" ]]; then

  echo -e "\n--- ${CYAN}${BOLD}START A CLUSTER${RESET} ---"
  echo -e ""

  read -p "Enter the local IP address of the master (ex: 192.168.1.20) : " master_ip
  read -p "Enter the number of threads used by the master (ex: 32) : " master_threads

  slaves_ips=()
  while true; do
    read -p "Add a slave? (y/n) : " add_slave
    if [[ "$add_slave" == "n" ]]; then
      break
    fi
    read -p "Enter the local IP address of the slave (ex: 192.168.1.23) : " slave_ip
    # read -p "Enter the number of threads used by the slave (ex: 32) : " slave_threads
    slaves_ips+=("$slave_ip")
  done

  generate_start_commands "$master_threads" "$master_ip" "${slaves_ips[@]}"

elif [[ "$choice" == "2" ]]; then
    echo -e "\n--- ${CYAN}${BOLD}START A CLUSTER${RESET} ---"
    start_cluster_from_file

elif [[ "$choice" == "3" ]]; then
  echo -e "\n--- ${CYAN}${BOLD}CONFIGURE A NEW CLUSTER${RESET} ---"
  echo -e ""

  read -p "Enter the local IP address of the master (ex: 192.168.1.20) : " master_ip
  read -p "Enter the number of threads used by the master (ex: 32) : " master_threads

  is_master="true"
  master_multiaddrs=$(generate_data_worker_multiaddrs "$master_ip" "$master_threads")

  cluster_config="  dataWorkerMultiaddrs: ["

  cluster_config+="\n  $(echo "$master_multiaddrs" | sed 's/ /,\n  /g'),"

  slaves_ips=()
  while true; do
    read -p "Add a slave? (y/n) : " add_slave
    echo -e ""
    if [[ "$add_slave" == "n" ]]; then
      break
    fi

    read -p "Enter the local IP address of the slave (ex: 192.168.1.23) : " slave_ip
    # read -p "Enter the number of threads used by the slave (ex: 32) : " slave_threads

    is_master="false"
    slave_multiaddrs=$(generate_data_worker_multiaddrs "$slave_ip" "$master_threads")
    cluster_config+="\n  $(echo "$slave_multiaddrs" | sed 's/ /,\n  /g'),"
    slaves_ips+=("$slave_ip")
  done

    echo ""
    read -p "Enter the username for your machines: " session_
    echo ""
    read -sp "Enter the password for the session: " password
    echo ""
    read -p "Enter a configuration name: " name_file

  cluster_config+="\n  ]  # Generate from Quil - Cluster Tools"

  echo -e "\nℹ️ ${ORANGE}${BOLD} Configuration generated for the cluster:${RESET}${RESET}"
  echo ""
  echo -e "$cluster_config"
  echo ""
  rigs=("$master_ip" "${slaves_ips[@]}")
  check_rigs_accessible "${rigs[@]}"

  update_remote_config "$master_ip"

  for slave_ip in "${slaves_ips[@]}"; do
    update_remote_config "$slave_ip"
  done

  generate_suggested_commands "$master_threads" "$master_ip" "${slaves_ips[@]}"

  config_file="${master_ip##*.}-${master_threads}-${name_file}.json"
  save_cluster_configuration "$config_file" "$master_ip" "$master_threads" "${slaves_ips[@]}"

else
  echo -e "❌ ${RED} Invalid choice. Exiting the script.${RESET}"
fi
