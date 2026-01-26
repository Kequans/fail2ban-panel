#!/bin/bash

# ==============================================================================
# Fail2ban Interactive Manager (F2B Panel) - English Version
# Description: Fail2ban Management Script for Linux
#              Manage bans, whitelists, and parameters without manual config editing.
#              v1.3 Fixes: Restart detection, Scope limitation, Multi-line config bug.
#
# Author: Kequans & ISFZY
# License: MIT License
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
TARGET_JAIL="sshd"

# --- Pre-checks ---

[[ $EUID -ne 0 ]] && echo -e "${RED}Error:${PLAIN} This script must be run as root!" && exit 1

check_install() {
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${YELLOW}Fail2ban service not detected.${PLAIN}"
        read -p "Install Fail2ban and Rsyslog now? (y/n): " install_confirm
        if [[ "$install_confirm" == "y" ]]; then
            echo -e "${BLUE}Installing Fail2ban and Rsyslog...${PLAIN}"
            
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y fail2ban rsyslog
            elif command -v yum >/dev/null 2>&1; then
                yum install -y fail2ban rsyslog
            else
                echo -e "${RED}Unrecognized package manager. Please install Fail2ban manually.${PLAIN}"
                exit 1
            fi

            if [ ! -f /var/log/auth.log ]; then touch /var/log/auth.log; fi
            systemctl enable rsyslog && systemctl start rsyslog
            
            if [ ! -f "$JAIL_CONF" ]; then
                echo -e "${BLUE}Initializing default configuration (jail.local)...${PLAIN}"
                cat > "$JAIL_CONF" << EOF
[${TARGET_JAIL}]
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
            echo -e "${GREEN}Installation and startup complete!${PLAIN}"
            sleep 2
        else
            echo -e "${RED}Installation cancelled.${PLAIN}"
            exit 0
        fi
    fi
    
    if [ ! -f "$JAIL_CONF" ]; then
        echo -e "${YELLOW}Warning: $JAIL_CONF not found.${PLAIN}"
        echo -e "${BLUE}Creating configuration from default template...${PLAIN}"
        cp /etc/fail2ban/jail.conf "$JAIL_CONF"
    fi
}

# --- Helper Functions ---

get_conf() {
    local key=$1
    sed -n "/^\[$TARGET_JAIL\]/,/^\[/p" "$JAIL_CONF" | grep "^${key}\s*=" | tail -n 1 | awk -F'=' '{print $2}' | tr -d ' '
}

set_conf() {
    local key=$1; local val=$2
    if sed -n "/^\[$TARGET_JAIL\]/,/^\[/p" "$JAIL_CONF" | grep -q "^${key}\s*="; then
        sed -i "/^\[$TARGET_JAIL\]/,/^\[/ s/^${key}\s*=.*/${key} = ${val}/" "$JAIL_CONF"
    else
        sed -i "/^\[$TARGET_JAIL\]/a ${key} = ${val}" "$JAIL_CONF"
    fi
}

# Fixed restart function with loop check
restart_f2b() {
    echo -e "${BLUE}Reloading Fail2ban configuration...${PLAIN}"
    systemctl restart fail2ban
    
    # Check 5 times, wait 1 sec each time
    for i in {1..5}; do
        if fail2ban-client ping >/dev/null 2>&1; then
            echo -e "${GREEN}Success! Configuration applied.${PLAIN}"
            read -n 1 -s -r -p "Press any key to continue..."
            return
        fi
        sleep 1
    done

    echo -e "${RED}Fail2ban restart timed out or failed.${PLAIN}"
    echo -e "${YELLOW}Please run 'systemctl status fail2ban' manually to troubleshoot.${PLAIN}"
    read -n 1 -s -r -p "Press any key to continue..."
}

get_status() {
    if fail2ban-client ping >/dev/null 2>&1; then
        local count=$(fail2ban-client status "$TARGET_JAIL" 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
        echo -e "${GREEN}Running (Active)${PLAIN} | Currently Banned: ${RED}${count:-0}${PLAIN}"
    else
        echo -e "${RED}Stopped${PLAIN}"
    fi
}

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

validate_time() { [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; }
validate_int() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# --- Feature Modules ---

change_param() {
    local name=$1; local key=$2; local type=$3
    local current=$(get_conf "$key")
    echo -e "\n${BLUE}Modifying: ${name}${PLAIN}"
    echo -e "Current Value: ${GREEN}$(fmt_unit "$current" "$type")${PLAIN}"
    if [ "$type" == "time" ]; then echo -e "${GRAY}(Suffixes: s=sec, m=min, h=hour, d=day)${PLAIN}"; fi
    
    while true; do
        read -p "Enter new value (Leave empty to cancel): " new_val
        if [ -z "$new_val" ]; then return; fi
        if [ "$type" == "time" ] && validate_time "$new_val"; then break; fi
        if [ "$type" == "int" ] && validate_int "$new_val"; then break; fi
        if [ "$type" == "factor" ] && validate_int "$new_val"; then break; fi
        echo -e "${RED}Invalid format. Please try again.${PLAIN}"
    done
    
    set_conf "$key" "$new_val"
    restart_f2b
}

toggle_service() {
    echo -e "\n${BLUE}--- Service Toggle ---${PLAIN}"
    if fail2ban-client ping >/dev/null 2>&1; then
        read -p "Stop and disable Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            systemctl stop fail2ban; systemctl disable fail2ban
            echo -e "${RED}Service stopped.${PLAIN}"
        fi
    else
        read -p "Enable and start Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            echo -e "${BLUE}Starting service (please wait)...${PLAIN}"
            systemctl enable fail2ban
            systemctl start fail2ban
            
            # Loop check for startup
            for i in {1..5}; do
                if fail2ban-client ping >/dev/null 2>&1; then
                    echo -e "${GREEN}Service started.${PLAIN}"
                    read -n 1 -s -r -p "Press any key to continue..."
                    return
                fi
                sleep 1
            done
            
            echo -e "${RED}Startup failed or timed out.${PLAIN}"
            echo -e "${YELLOW}Please run: 'systemctl status fail2ban' to view errors.${PLAIN}"
        fi
    fi
    read -n 1 -s -r -p "Press any key to continue..."
}

unban_ip() {
    echo -e "\n${BLUE}--- Unban IP ---${PLAIN}"
    local banned_list=$(fail2ban-client status "$TARGET_JAIL" 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | sed 's/^[ \t]*//')
    [ -z "$banned_list" ] && banned_list="None"

    echo -e "Current Banned List: ${RED}${banned_list}${PLAIN}"
    read -p "Enter IP to unban (Empty to cancel): " target_ip
    [ -z "$target_ip" ] && return
    
    fail2ban-client set "$TARGET_JAIL" unbanip "$target_ip"
    if [ $? -eq 0 ]; then echo -e "${GREEN}Unbanned successfully: $target_ip${PLAIN}"; else echo -e "${RED}Operation failed.${PLAIN}"; fi
    read -n 1 -s -r -p "Press any key to continue..."
}

add_whitelist() {
    echo -e "\n${BLUE}--- Whitelist Management ---${PLAIN}"
    local current_list=$(get_conf "ignoreip")
    
    echo -e "Current Whitelist (sshd): ${YELLOW}${current_list:-Inherited global or None}${PLAIN}"
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')
    
    read -p "Enter IP to whitelist (Default local: ${current_ip}): " input_ip
    [ -z "$input_ip" ] && input_ip="$current_ip"
    [ -z "$input_ip" ] && echo -e "${RED}Unable to get IP.${PLAIN}" && return
    
    if echo "$current_list" | grep -Fq "$input_ip"; then
        echo -e "${YELLOW}IP is already whitelisted.${PLAIN}"
    else
        if [ -z "$current_list" ]; then
            set_conf "ignoreip" "$input_ip"
        else
            set_conf "ignoreip" "$current_list $input_ip"
        fi
        restart_f2b
    fi
}

view_logs() {
    clear
    echo -e "${BLUE}=== Audit Logs (Last 20 lines) ===${PLAIN}"
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}Log file not found: $LOG_FILE${PLAIN}"
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

menu_exponential() {
    while true; do
        clear
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        echo -e "${BLUE}=== Advanced: Exponential Ban Settings (sshd) ===${PLAIN}"
        echo -e "Description: Ban time increases exponentially for repeated offenders."
        echo -e "-------------------------------------------"
        echo -e "  1. Increment Mode   [${S_INC}]"
        echo -e "  2. Growth Factor    [${YELLOW}${fac:-Not Set}${PLAIN}] $(fmt_unit "${fac}" "factor")"
        echo -e "  3. Max Ban Time     [${YELLOW}${max:-Not Set}${PLAIN}] $(fmt_unit "${max}" "time")"
        echo -e "-------------------------------------------"
        echo -e "  0. Back"
        echo -e ""
        read -p "Select [0-3]: " sc
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; set_conf "bantime.increment" "$ns"; restart_f2b ;;
            2) change_param "Growth Factor (Multiplier)" "bantime.factor" "factor" ;;
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
        echo -e "${BLUE}#           Fail2ban Manager (v1.3 EN)         #${PLAIN}"
        echo -e "${BLUE}################################################${PLAIN}"
        echo -e "  Status: $(get_status)"
        echo -e "------------------------------------------------"
        echo -e "  1. Max Retries      [${YELLOW}${VAL_MAX}${PLAIN}]"
        echo -e "  2. Initial Ban Time [${YELLOW}${VAL_BAN}${PLAIN}] $(fmt_unit "${VAL_BAN}" "time")"
        echo -e "  3. Find Time Window [${YELLOW}${VAL_FIND}${PLAIN}] $(fmt_unit "${VAL_FIND}" "time")"
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
            2) change_param "Initial Ban Time" "bantime"  "time" ;;
            3) change_param "Find Time Window" "findtime" "time" ;;
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

menu_main
