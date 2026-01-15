#!/bin/bash

# ==============================================================================
# Fail2ban Interactive Manager (F2B Panel) - Chinese Version
# Description: Linux Fail2ban 管理脚本 (中文版)
#              无需手动编辑配置文件，通过菜单管理封禁、白名单和参数。
#
# Author: Kequans & ISFZY
# License: MIT License
# ==============================================================================

# --- 全局变量 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
GRAY="\033[90m"
PLAIN="\033[0m"

JAIL_CONF="/etc/fail2ban/jail.local"
LOG_FILE="/var/log/fail2ban.log"

# --- 预检步骤 ---

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误:${PLAIN} 必须使用 root 用户运行此脚本！" && exit 1

# 检查是否安装 Fail2ban
check_install() {
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 Fail2ban 服务。${PLAIN}"
        read -p "是否立即安装 Fail2ban 和 Rsyslog？(y/n): " install_confirm
        if [[ "$install_confirm" == "y" ]]; then
            echo -e "${BLUE}正在安装 Fail2ban 和 Rsyslog...${PLAIN}"
            
            # 简单的包管理器检测
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y fail2ban rsyslog
            elif command -v yum >/dev/null 2>&1; then
                yum install -y fail2ban rsyslog
            else
                echo -e "${RED}未识别的包管理器，请手动安装 Fail2ban。${PLAIN}"
                exit 1
            fi

            # 确保 sshd 日志文件存在
            if [ ! -f /var/log/auth.log ]; then touch /var/log/auth.log; fi
            systemctl enable rsyslog && systemctl start rsyslog
            
            # 初始化 jail.local
            if [ ! -f "$JAIL_CONF" ]; then
                echo -e "${BLUE}正在初始化默认配置 (jail.local)...${PLAIN}"
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
            echo -e "${GREEN}安装并启动完成！${PLAIN}"
            sleep 2
        else
            echo -e "${RED}已取消安装。${PLAIN}"
            exit 0
        fi
    fi
    
    # 检查配置文件是否存在
    if [ ! -f "$JAIL_CONF" ]; then
        echo -e "${YELLOW}警告: 未找到 $JAIL_CONF${PLAIN}"
        echo -e "${BLUE}正在根据默认模板创建配置...${PLAIN}"
        cp /etc/fail2ban/jail.conf "$JAIL_CONF"
    fi
}

# --- 辅助函数 ---

# 读取配置值
get_conf() {
    local key=$1
    # 提取值并去除空格
    grep "^${key}\s*=" "$JAIL_CONF" | awk -F'=' '{print $2}' | tr -d ' '
}

# 写入配置值
set_conf() {
    local key=$1; local val=$2
    if grep -q "^${key}\s*=" "$JAIL_CONF"; then
        sed -i "s/^${key}\s*=.*/${key} = ${val}/" "$JAIL_CONF"
    else
        # 如果 key 不存在，尝试插入到 [sshd] 下方或文件末尾
        if grep -q "\[sshd\]" "$JAIL_CONF"; then
            sed -i "/\[sshd\]/a ${key} = ${val}" "$JAIL_CONF"
        else
            echo "${key} = ${val}" >> "$JAIL_CONF"
        fi
    fi
}

# 重启并验证
restart_f2b() {
    echo -e "${BLUE}正在重载 Fail2ban 配置...${PLAIN}"
    systemctl restart fail2ban
    sleep 1
    if fail2ban-client ping >/dev/null 2>&1; then
        echo -e "${GREEN}成功！配置已生效。${PLAIN}"
    else
        echo -e "${RED}Fail2ban 重启失败。${PLAIN}"
        echo -e "${YELLOW}请检查配置文件语法或系统日志。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# 获取服务状态
get_status() {
    if fail2ban-client ping >/dev/null 2>&1; then
        local count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
        echo -e "${GREEN}运行中 (Active)${PLAIN} | 当前封禁数: ${RED}${count:-0}${PLAIN}"
    else
        echo -e "${RED}已停止 (Stopped)${PLAIN}"
    fi
}

# 格式化单位显示
fmt_unit() {
    local val=$1; local type=$2
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        if [ "$type" == "time" ]; then echo "${val}秒"; 
        elif [ "$type" == "factor" ]; then echo "${val}倍"; 
        else echo "$val"; fi
    else
        echo "$val"
    fi
}

# 校验函数
validate_time() { [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; }
validate_int() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# --- 功能模块 ---

change_param() {
    local name=$1; local key=$2; local type=$3
    local current=$(get_conf "$key")
    echo -e "\n${BLUE}正在修改: ${name}${PLAIN}"
    echo -e "当前值: ${GREEN}$(fmt_unit "$current" "$type")${PLAIN}"
    if [ "$type" == "time" ]; then echo -e "${GRAY}(支持后缀: s=秒, m=分, h=小时, d=天)${PLAIN}"; fi
    
    while true; do
        read -p "请输入新值 (留空取消): " new_val
        if [ -z "$new_val" ]; then return; fi
        if [ "$type" == "time" ] && validate_time "$new_val"; then break; fi
        if [ "$type" == "int" ] && validate_int "$new_val"; then break; fi
        if [ "$type" == "factor" ] && validate_int "$new_val"; then break; fi
        echo -e "${RED}格式错误，请重试。${PLAIN}"
    done
    
    set_conf "$key" "$new_val"
    restart_f2b
}

toggle_service() {
    echo -e "\n${BLUE}--- 服务开关 ---${PLAIN}"
    if fail2ban-client ping >/dev/null 2>&1; then
        read -p "是否停止并禁用 Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            systemctl stop fail2ban; systemctl disable fail2ban
            echo -e "${RED}服务已停止。${PLAIN}"
        fi
    else
        read -p "是否启用并启动 Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            systemctl enable fail2ban; systemctl start fail2ban
            echo -e "${GREEN}服务已启动。${PLAIN}"
        fi
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

unban_ip() {
    echo -e "\n${BLUE}--- 手动解封 IP ---${PLAIN}"
    local banned_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | sed 's/^[ \t]*//')
    [ -z "$banned_list" ] && banned_list="无"

    echo -e "当前被封禁列表: ${RED}${banned_list}${PLAIN}"
    read -p "输入要解封的 IP (留空取消): " target_ip
    [ -z "$target_ip" ] && return
    
    fail2ban-client set sshd unbanip "$target_ip"
    if [ $? -eq 0 ]; then echo -e "${GREEN}解封成功: $target_ip${PLAIN}"; else echo -e "${RED}操作失败。${PLAIN}"; fi
    read -n 1 -s -r -p "按任意键继续..."
}

add_whitelist() {
    echo -e "\n${BLUE}--- 白名单管理 ---${PLAIN}"
    local current_list=$(grep "^ignoreip" "$JAIL_CONF" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    
    echo -e "当前白名单: ${YELLOW}${current_list:-无}${PLAIN}"
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')
    
    read -p "输入要放行的 IP (回车默认本机 ${current_ip}): " input_ip
    [ -z "$input_ip" ] && input_ip="$current_ip"
    [ -z "$input_ip" ] && echo -e "${RED}无法获取 IP。${PLAIN}" && return
    
    if echo "$current_list" | grep -Fq "$input_ip"; then
        echo -e "${YELLOW}该 IP 已在白名单中。${PLAIN}"
    else
        sed -i "/^ignoreip/ s/$/ ${input_ip}/" "$JAIL_CONF"
        restart_f2b
    fi
}

view_logs() {
    clear
    echo -e "${BLUE}=== 审计日志 (最近 20 条) ===${PLAIN}"
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}日志文件不存在: $LOG_FILE${PLAIN}"
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
    read -n 1 -s -r -p "按任意键返回..."
}

# --- 菜单逻辑 ---

menu_exponential() {
    while true; do
        clear
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        [ "$inc" == "true" ] && S_INC="${GREEN}开启${PLAIN}" || S_INC="${RED}关闭${PLAIN}"

        echo -e "${BLUE}=== 高级: 指数封禁设置 ===${PLAIN}"
        echo -e "说明: 对重复犯错的 IP 封禁时间成倍增加。"
        echo -e "-------------------------------------------"
        echo -e "  1. 递增模式开关   [${S_INC}]"
        echo -e "  2. 增长系数       [${YELLOW}${fac:-未设置}${PLAIN}] $(fmt_unit "${fac}" "factor")"
        echo -e "  3. 封禁上限       [${YELLOW}${max:-未设置}${PLAIN}] $(fmt_unit "${max}" "time")"
        echo -e "-------------------------------------------"
        echo -e "  0. 返回"
        echo -e ""
        read -p "请选择 [0-3]: " sc
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; set_conf "bantime.increment" "$ns"; restart_f2b ;;
            2) change_param "增长系数 (倍数)" "bantime.factor" "factor" ;;
            3) change_param "封禁上限 (时间)" "bantime.maxtime" "time" ;;
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
        echo -e "${BLUE}#            Fail2ban 管理面板 (v1.0)          #${PLAIN}"
        echo -e "${BLUE}################################################${PLAIN}"
        echo -e "  状态: $(get_status)"
        echo -e "------------------------------------------------"
        echo -e "  1. 最大重试次数     [${YELLOW}${VAL_MAX}${PLAIN}]"
        echo -e "  2. 初始封禁时长     [${YELLOW}${VAL_BAN}${PLAIN}] $(fmt_unit "${VAL_BAN}" "time")"
        echo -e "  3. 监测时间窗口     [${YELLOW}${VAL_FIND}${PLAIN}] $(fmt_unit "${VAL_FIND}" "time")"
        echo -e "------------------------------------------------"
        echo -e "  4. 手动解封 IP"
        echo -e "  5. 添加白名单"
        echo -e "  6. 查看封禁日志"
        echo -e "  7. 指数封禁设置 ->"
        echo -e "------------------------------------------------"
        echo -e "  8. 开启/停止 服务"
        echo -e "  0. 退出"
        echo -e ""
        read -p "请选择 [0-8]: " choice

        case "$choice" in
            1) change_param "最大重试次数" "maxretry" "int" ;;
            2) change_param "初始封禁时长" "bantime"  "time" ;;
            3) change_param "监测时间窗口" "findtime" "time" ;;
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

# --- 启动脚本 ---
menu_main
