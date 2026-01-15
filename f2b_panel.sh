#!/bin/bash

# ==============================================================================
# Fail2ban Interactive Manager (F2B Panel)
# Description: A user-friendly Shell script to manage Fail2ban configuration,
#              bans, whitelists, and logs without editing config files manually.
#
# Author: [Kequans] Thank https://github.com/ISFZY/Xray-Auto
# License: MIT License
# Repository: [https://github.com/Kequans/fail2ban-panel]
# ==============================================================================

# --- Global Variables ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
GRAY="\033[90m"
PLAIN="\033[0m"

JAIL_CONF="/etc/fail2ban/jail.local"
LOG_FILE="/var/log/fail2ban.log"

# --- Pre-flight Checks ---

# Check Root
[[ $EUID -ne 0 ]] && echo -e "${RED}Error:${PLAIN} This script must be run as root!" && exit 1

# Check if Fail2ban is installed
check_install() {
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${YELLOW}Fail2ban is not installed on this system.${PLAIN}"
        read -p "Do you want to install Fail2ban and Rsyslog now? (y/n): " install_confirm
        if [[ "$install_confirm" == "y" ]]; then
            echo -e "${BLUE}Installing Fail2ban and Rsyslog...${PLAIN}"
            
            # Detect Package Manager (Simple version)
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y fail2ban rsyslog
            elif command -v yum >/dev/null 2>&1; then
                yum install -y fail2ban rsyslog
            else
                echo -e "${RED}Unsupported package manager. Please install Fail2ban manually.${PLAIN}"
                exit 1
            fi

            # Ensure log file exists for sshd jail
            if [ ! -f /var/log/auth.log ]; then touch /var/log/auth.log; fi
            systemctl enable rsyslog && systemctl start rsyslog
            
            # Initialize jail.local if not exists
            if [ ! -f "$JAIL_CONF" ]; then
                echo -e "${BLUE}Initializing default jail.local...${PLAIN}"
                cat > "$JAIL_CONF" << 'EOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 600
findtime = 3600
backend = auto
banaction = iptables-multiport
ignoreip = 127.0.0.1/8
EOF
            fi
            
            systemctl enable fail2ban
            systemctl restart fail2ban
            echo -e "${GREEN}Installation Complete!${PLAIN}"
            sleep 2
        else
            echo -e "${RED}Aborted.${PLAIN}"
            exit 0
        fi
    fi
    
    # Check config file existence
    if [ ! -f "$JAIL_CONF" ]; then
        echo -e "${YELLOW}Warning: $JAIL_CONF not found.${PLAIN}"
        echo -e "${BLUE}Creating a basic configuration...${PLAIN}"
        cp /etc/fail2ban/jail.conf "$JAIL_CONF"
    fi
}

# --- Helper Functions ---

# Read config value
get_conf() {
    local key=$1
    # Extract value from jail.local, handle spaces
    grep "^${key}\s*=" "$JAIL_CONF" | awk -F'=' '{print $2}' | tr -d ' '
}

# Write config value
set_conf() {
    local key=$1; local val=$2
    if grep -q "^${key}\s*=" "$JAIL_CONF"; then
        sed -i "s/^${key}\s*=.*/${key} = ${val}/" "$JAIL_CONF"
    else
        # If key doesn't exist, insert it after [sshd] or at top
        if grep -q "\[sshd\]" "$JAIL_CONF"; then
            sed -i "/\[sshd\]/a ${key} = ${val}" "$JAIL_CONF"
        else
            echo "${key} = ${val}" >> "$JAIL_CONF"
        fi
    fi
}

# Restart and verify
restart_f2b() {
    echo -e "${BLUE}Reloading Fail2ban configuration...${PLAIN}"
    systemctl restart fail2ban
    sleep 1
    if fail2ban-client ping >/dev/null 2>&1; then
        echo -e "${GREEN}Success! Configuration applied.${PLAIN}"
    else
        echo -e "${RED}Failed to restart Fail2ban.${PLAIN}"
        echo -e "${YELLOW}Please check configuration syntax or system logs.${PLAIN}"
    fi
    read -n 1 -s -r -p "Press any key to continue..."
}

# Get Service Status
get_status() {
    if fail2ban-client ping >/dev/null 2>&1; then
        local count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
        echo -e "${GREEN}Running${PLAIN} | Banned IPs: ${RED}${count:-0}${PLAIN}"
    else
        echo -e "${RED}Stopped${PLAIN}"
    fi
}

# Format units for display
fmt_unit() {
    local val=$1; local type=$2
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        if [ "$type" == "time" ]; then echo "${val}s"; 
        elif [ "$type" == "factor" ]; then echo "${val}x"; 
        else echo "$val"; fi
    else
        echo "$val"
    fi
}

# Validation
validate_time() { [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; }
validate_int() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# --- Action Functions ---

change_param() {
    local name=$1; local key=$2; local type=$3
    local current=$(get_conf "$key")
    echo -e "\n${BLUE}Modify: ${name}${PLAIN}"
    echo -e "Current: ${GREEN}$(fmt_unit "$current" "$type")${PLAIN}"
    if [ "$type" == "time" ]; then echo -e "${GRAY}(Suffix: s=sec, m=min, h=hour, d=day)${PLAIN}"; fi
    
    while true; do
        read -p "New Value (Enter to cancel): " new_val
        if [ -z "$new_val" ]; then return; fi
        if [ "$type" == "time" ] && validate_time "$new_val"; then break; fi
        if [ "$type" == "int" ] && validate_int "$new_val"; then break; fi
        if [ "$type" == "factor" ] && validate_int "$new_val"; then break; fi
        echo -e "${RED}Invalid format. Try again.${PLAIN}"
    done
    
    set_conf "$key" "$new_val"
    restart_f2b
}

toggle_service() {
    echo -e "\n${BLUE}--- Service Control ---${PLAIN}"
    if fail2ban-client ping >/dev/null 2>&1; then
        read -p "Stop and Disable Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            systemctl stop fail2ban; systemctl disable fail2ban
            echo -e "${RED}Service Stopped.${PLAIN}"
        fi
    else
        read -p "Start and Enable Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            systemctl enable fail2ban; systemctl start fail2ban
            echo -e "${GREEN}Service Started.${PLAIN}"
        fi
    fi
    read -n 1 -s -r -p "Press any key to continue..."
}

unban_ip() {
    echo -e "\n${BLUE}--- Unban Manager ---${PLAIN}"
    local banned_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | sed 's/^[ \t]*//')
    [ -z "$banned_list" ] && banned_list="None"

    echo -e "Banned IPs: ${RED}${banned_list}${PLAIN}"
    read -p "IP to Unban (Enter to cancel): " target_ip
    [ -z "$target_ip" ] && return
    
    fail2ban-client set sshd unbanip "$target_ip"
    if [ $? -eq 0 ]; then echo -e "${GREEN}Unbanned: $target_ip${PLAIN}"; else echo -e "${RED}Failed.${PLAIN}"; fi
    read -n 1 -s -r -p "Press any key to continue..."
}

add_whitelist() {
    echo -e "\n${BLUE}--- Whitelist Manager ---${PLAIN}"
    local current_list=$(grep "^ignoreip" "$JAIL_CONF" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    
    echo -e "Whitelisted: ${YELLOW}${current_list:-None}${PLAIN}"
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')
    
    read -p "IP to Whitelist (Enter for current IP ${current_ip}): " input_ip
    [ -z "$input_ip" ] && input_ip="$current_ip"
    [ -z "$input_ip" ] && echo -e "${RED}Cannot detect IP.${PLAIN}" && return
    
    if echo "$current_list" | grep -Fq "$input_ip"; then
        echo -e "${YELLOW}IP already in whitelist.${PLAIN}"
    else
        sed -i "/^ignoreip/ s/$/ ${input_ip}/" "$JAIL_CONF"
        restart_f2b
    fi
}

view_logs() {
    clear
    echo -e "${BLUE}=== Audit Logs (Last 20 Actions) ===${PLAIN}"
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}Log file not found at $LOG_FILE${PLAIN}"
    else
        grep -E "(Ban|Unban)" "$LOG_FILE" 2>/dev/null | tail -n 20 | \
        awk '{
            gsub(/Unban/, "\033[32m&\033[0m");
            gsub(/Ban/, "\033[31m&\033[0m");
            if ($4 ~ /^\[.*\]:$/) { $4 = sprintf("%9s", $4) }
            print
        }'
    fi
    echo -e "----------------------------------------------"
    read -n 1 -s -r -p "Press any key to return..."
}

# --- Menus ---

menu_exponential() {
    while true; do
        clear
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        echo -e "${BLUE}=== Advanced: Exponential Ban ===${PLAIN}"
        echo -e "Description: Increase ban time for repeat offenders."
        echo -e "-------------------------------------------"
        echo -e "  1. Exponential Mode   [${S_INC}]"
        echo -e "  2. Increase Factor    [${YELLOW}${fac:-None}${PLAIN}] $(fmt_unit "${fac}" "factor")"
        echo -e "  3. Max Ban Time       [${YELLOW}${max:-None}${PLAIN}] $(fmt_unit "${max}" "time")"
        echo -e "-------------------------------------------"
        echo -e "  0. Back"
        echo -e ""
        read -p "Select [0-3]: " sc
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; set_conf "bantime.increment" "$ns"; restart_f2b ;;
            2) change_param "Increase Factor" "bantime.factor" "factor" ;;
            3) change_param "Max Ban Time" "bantime.maxtime" "time" ;;
            0) return ;;
        esac
    done
}

menu_main() {
    check_install
    while true; do
        clear
        VAL_MAX=$(get_conf "maxretry"); VAL_BAN=$(get_conf "bantime"); VAL_FIND=$(get_conf "findtime")
        
        echo -e "${BLUE}################################################${PLAIN}"
        echo -e "${BLUE}#            Fail2ban Manager (v1.0)           #${PLAIN}"
        echo -e "${BLUE}################################################${PLAIN}"
        echo -e "  Status: $(get_status)"
        echo -e "------------------------------------------------"
        echo -e "  1. Max Retries      [${YELLOW}${VAL_MAX}${PLAIN}]"
        echo -e "  2. Ban Time         [${YELLOW}${VAL_BAN}${PLAIN}] $(fmt_unit "${VAL_BAN}" "time")"
        echo -e "  3. Find Time        [${YELLOW}${VAL_FIND}${PLAIN}] $(fmt_unit "${VAL_FIND}" "time")"
        echo -e "------------------------------------------------"
        echo -e "  4. Unban IP"
        echo -e "  5. Add to Whitelist"
        echo -e "  6. View Ban Logs"
        echo -e "  7. Exponential Ban Settings ->"
        echo -e "------------------------------------------------"
        echo -e "  8. Start/Stop Service"
        echo -e "  0. Exit"
        echo -e ""
        read -p "Select [0-8]: " choice

        case "$choice" in
            1) change_param "Max Retries" "maxretry" "int" ;;
            2) change_param "Ban Time" "bantime"  "time" ;;
            3) change_param "Find Time" "findtime" "time" ;;
            4) unban_ip ;;
            5) add_whitelist ;;
            6) view_logs ;;
            7) menu_exponential ;;
            8) toggle_service ;;
            0) clear; exit 0 ;;
            *) ;;
        esac
    done
}

# --- Start ---
menu_main
