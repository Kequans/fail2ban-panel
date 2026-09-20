#!/bin/bash

# ==============================================================================
# Fail2ban Interactive Manager (F2B Panel) - English Version
# Description: Fail2ban Management Script for Linux
#              Manage bans, whitelists, and parameters without manual config editing.
#              v1.6: Multiport and jail management with validated configuration updates.
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

PANEL_LANG="en"
CONF_DIR="/etc/fail2ban"
JAIL_CONF="$CONF_DIR/jail.local"
PANEL_CONF="$CONF_DIR/jail.d/zz-f2b-panel.local"
LOG_FILE="/var/log/fail2ban.log"
TARGET_JAIL="sshd"

# --- Pre-checks ---

check_install() {
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${YELLOW}Fail2ban service not detected.${PLAIN}"
        read -r -p "Install Fail2ban and Rsyslog now? (y/n): " install_confirm
        if [[ "$install_confirm" == "y" ]]; then
            echo -e "${BLUE}Installing Fail2ban and Rsyslog...${PLAIN}"
            
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y fail2ban rsyslog || return 1
            elif command -v yum >/dev/null 2>&1; then
                yum install -y fail2ban rsyslog || return 1
            else
                echo -e "${RED}Unrecognized package manager. Please install Fail2ban manually.${PLAIN}"
                exit 1
            fi

            if [ ! -f /var/log/auth.log ]; then touch /var/log/auth.log; fi
            systemctl enable rsyslog && systemctl start rsyslog || return 1
            
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
            
            fail2ban-client -t || return 1
            systemctl enable fail2ban && systemctl restart fail2ban || return 1
            echo -e "${GREEN}Installation and startup complete!${PLAIN}"
            sleep 2
        else
            echo -e "${RED}Installation cancelled.${PLAIN}"
            exit 0
        fi
    fi

}

# --- Helper Functions ---

# Configuration and validation helpers are identical in both standalone editions.
message() {
    if [[ "$PANEL_LANG" == zh ]]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
}

pause_panel() {
    local prompt
    prompt=$(message 'Press any key to continue...' '按任意键继续...')
    read -n 1 -s -r -p "$prompt" || true
}

# The setting belongs to fail2ban.conf's Definition, not a jail section.
ensure_ipv6_default() {
    local output path="$CONF_DIR/fail2ban.d/zz-f2b-panel.local" tmp
    if ! output=$(fail2ban-client -t 2>&1); then
        printf '%s\n' "$output"
        return 1
    fi
    if [[ "$output" != *"WARNING 'allowipv6' not defined in 'Definition'. Using default one: 'auto'"* ]]; then
        printf '%s\n' "$output"
        return 0
    fi
    # Retain the original diagnostics; later operations no longer repeat this warning.
    printf '%s\n' "$output"
    # Only respond to the reader's missing-setting warning, preserving explicit values.
    mkdir -p "${path%/*}" || return 1
    if [[ -e "$path" ]]; then
        printf '%s\n' "$output"
        message "Check $path: IPv6 default could not be set automatically." "请检查 ${path}：无法自动补全 IPv6 默认设置。"
        return 1
    fi
    tmp=$(mktemp "${path}.tmp.XXXXXX") || return 1
    printf '[Definition]\nallowipv6 = auto\n' > "$tmp"
    # Hard-link creation is atomic and refuses to overwrite a concurrent writer.
    if ! chmod 600 "$tmp" || ! ln "$tmp" "$path"; then
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    if output=$(fail2ban-client -t 2>&1) &&
        [[ "$output" != *"WARNING 'allowipv6' not defined in 'Definition'. Using default one: 'auto'"* ]]; then
        printf '%s\n' "$output"
        message 'Saved the existing IPv6 default (auto); missing-setting warning resolved.' \
            '已显式保存 IPv6 默认值 auto，缺失配置警告已修复。'
        return 0
    fi
    rm -f "$path"
    printf '%s\n' "$output"
    message 'IPv6 default validation failed; the new file was removed.' 'IPv6 默认配置校验失败，已移除新增文件。'
    return 1
}

# Follow Fail2ban file precedence. Preserve spaces in lists and continuation lines.
# Values containing interpolation are intentionally left for Fail2ban to resolve.
get_conf() {
    local key=$1 runtime file
    case "$key" in
        maxretry|bantime|findtime|ignoreip)
            if [[ "${CONFIG_ONLY:-false}" != true ]] && runtime=$(fail2ban-client get "$TARGET_JAIL" "$key" 2>/dev/null); then
                if [[ "$key" == ignoreip ]]; then
                    printf '%s\n' "$runtime" | sed -n 's/^[| `+-]* //p' | paste -sd ' ' -
                else
                    printf '%s\n' "$runtime"
                fi
                return
            fi ;;
    esac
    local files=()
    for file in "$CONF_DIR/jail.conf" "$CONF_DIR"/jail.d/*.conf \
        "$JAIL_CONF" "$CONF_DIR"/jail.d/*.local; do
        [[ -f "$file" ]] && files+=("$file")
    done
    ((${#files[@]})) || return 0
    awk -v jail="$TARGET_JAIL" -v key="$key" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        FNR == 1 { section=""; last="" }
        /^[ \t]*[#;]/ { next }
        /^[ \t]*\[/ {
            section=$0; sub(/^[ \t]*\[/, "", section); sub(/\].*$/, "", section)
            last=""; next
        }
        /^[ \t]+[^=]+$/ {
            if (last == key) values[section]=values[section] " " trim($0)
            next
        }
        index($0, "=") {
            pos=index($0, "="); last=trim(substr($0, 1, pos-1))
            if (last == key) { values[section]=trim(substr($0,pos+1)); found[section]=1 }
        }
        END { if (found[jail]) print values[jail]; else if (found["DEFAULT"]) print values["DEFAULT"] }
    ' "${files[@]}"
}

# Only edit the panel-owned override; compare keys literally, including dots.
set_conf() {
    local key=$1 val=$2 tmp
    [[ "$TARGET_JAIL" =~ ^[a-zA-Z0-9_-]+$ && "$key" =~ ^[a-z.]+$ ]] || return 1
    [[ "$val" != *$'\n'* && "$val" != *$'\r'* && "$val" != *'\'* ]] || return 1
    mkdir -p "${PANEL_CONF%/*}" || return 1
    tmp=$(mktemp "${PANEL_CONF}.tmp.XXXXXX") || return 1
    [[ -f "$PANEL_CONF" ]] || : > "$PANEL_CONF"
    awk -v jail="$TARGET_JAIL" -v key="$key" -v value="$val" '
        /^[ \t]*\[/ {
            section=$0; sub(/^[ \t]*\[/, "", section); sub(/\].*$/, "", section)
            active=(section == jail)
            print
            if (active) { print key " = " value; found=1 }
            skip=0; next
        }
        active && index($0,"=") {
            name=substr($0,1,index($0,"=")-1); gsub(/^[ \t]+|[ \t]+$/, "", name)
            skip=(name == key); if (skip) next
        }
        skip && /^[ \t]+/ { next }
        { skip=0; print }
        END { if (!found) print "\n[" jail "]\n" key " = " value }
    ' "$PANEL_CONF" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$PANEL_CONF"
    local result=$?
    [[ ! -e "$tmp" ]] || rm -f "$tmp"
    return "$result"
}

# Write and validate the complete group before a single reload.
write_conf_pairs() {
    local key val
    while (($#)); do
        key=$1; val=$2; shift 2
        set_conf "$key" "$val" || return 1
        [[ "$(CONFIG_ONLY=true get_conf "$key")" == "$val" ]] || return 1
    done
}

apply_conf() {
    local backup existed=false attempted=false was_active=false result=1
    (($# > 0 && $# % 2 == 0)) || return 1
    mkdir -p "${PANEL_CONF%/*}" || return 1
    # Serialize panel writers. A stale lock after SIGKILL must be removed manually.
    if ! mkdir "${PANEL_CONF}.lock" 2>/dev/null; then
        message 'Configuration is locked by another panel.' '配置已被其他面板锁定。'
        return 1
    fi
    backup=$(mktemp "${PANEL_CONF}.backup.XXXXXX") || {
        rmdir "${PANEL_CONF}.lock"; return 1;
    }
    if [[ -f "$PANEL_CONF" ]]; then
        existed=true
        cp -p "$PANEL_CONF" "$backup" || {
            rm -f "$backup"; rmdir "${PANEL_CONF}.lock"; return 1;
        }
    fi
    if write_conf_pairs "$@" && fail2ban-client -t; then
        if fail2ban-client status "$TARGET_JAIL" >/dev/null 2>&1; then was_active=true; fi
        attempted=true
        # Restart this jail's actions so changed ports reach the firewall rules.
        if fail2ban-client reload --restart "$TARGET_JAIL" &&
            fail2ban-client status "$TARGET_JAIL" >/dev/null 2>&1; then
            message 'Configuration applied.' '配置已生效。'
            result=0
        fi
    fi
    if ((result != 0)); then
        if [[ "$existed" == true ]]; then
            if ! cp -p "$backup" "$PANEL_CONF"; then
                message "Restore failed. Backup: $backup" "恢复失败，备份位置：$backup"
                rmdir "${PANEL_CONF}.lock"
                return 1
            fi
        else
            rm -f "$PANEL_CONF"
        fi
        message 'Change failed (check validation and later overrides); previous configuration restored.' '修改失败（请检查配置校验与后续覆盖文件），已恢复原配置。'
        if [[ "$attempted" == true && "$was_active" == false ]]; then
            # A failed new-jail activation may have partially started its actions.
            if fail2ban-client status "$TARGET_JAIL" >/dev/null 2>&1; then
                fail2ban-client stop "$TARGET_JAIL" || message 'Could not stop partially created jail.' '无法停止部分创建的 Jail。'
            fi
        elif [[ "$attempted" == true ]]; then
            fail2ban-client reload --restart "$TARGET_JAIL" ||
                message 'Recovery failed. Check systemctl status fail2ban.' '服务恢复失败，请检查 systemctl status fail2ban。'
        fi
    fi
    rm -f "$backup"
    rmdir "${PANEL_CONF}.lock"
    return "$result"
}

# Numeric ports and inclusive ranges; normalize leading zeros and duplicates.
normalize_ports() {
    local input=$1 item first last output='' seen=',' slots=0
    input=${input//[[:space:]]/}
    [[ -n "$input" && "$input" != ,* && "$input" != *, && "$input" != *,,* ]] || return 1
    local items=()
    IFS=',' read -r -a items <<< "$input"
    for item in "${items[@]}"; do
        [[ "$item" =~ ^[0-9]{1,5}(:[0-9]{1,5})?$ ]] || return 1
        first=$((10#${item%%:*}))
        last=$((10#${item##*:}))
        ((first >= 1 && last <= 65535 && first <= last)) || return 1
        item=$first
        [[ "$first" == "$last" ]] || item="$first:$last"
        [[ "$seen" != *",$item,"* ]] || continue
        seen+="$item,"
        output+="${output:+,}$item"
        ((slots += 1))
        [[ "$first" == "$last" ]] || ((slots += 1))
    done
    # iptables-multiport accepts 15 slots; a range consumes two slots.
    ((slots <= 15)) || return 1
    printf '%s\n' "$output"
}

manage_ports() {
    local input ports
    message "Jail: $TARGET_JAIL | Configured ports: $(get_conf port)" \
        "Jail：$TARGET_JAIL | 配置端口：$(get_conf port)"
    message 'Ports affect bans, not listening services. Use the matching service filter/logs.' \
        '端口决定封禁范围，不修改监听服务。其他服务需要对应的过滤器和日志。'
    message 'Replace ports, e.g. 22,2222,8000:8010 (empty cancels; at most 15 slots):' \
        '设置完整端口列表，例如 22,2222,8000:8010（留空取消；最多 15 槽位）：'
    read -r input || return
    [[ -n "$input" ]] || return
    if ! ports=$(normalize_ports "$input"); then
        message 'Invalid ports: use 1-65535; ranges consume two slots.' '端口无效：范围为 1-65535；每个区间占两个槽位。'
        pause_panel
        return 1
    fi
    message "Apply $ports to $TARGET_JAIL? (y/n)" "将 $ports 应用到 ${TARGET_JAIL}？(y/n)"
    read -r input || return
    [[ "$input" == y ]] || return
    apply_conf port "$ports"
    pause_panel
}

select_jail() {
    local status list input jail
    status=$(fail2ban-client status) || return 1
    list=$(printf '%s\n' "$status" | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' ')
    message "Enabled jails: $list" "已启用的 Jail：$list"
    message 'Enter jail name (empty cancels):' '输入 Jail 名称（留空取消）：'
    read -r input || return
    [[ -n "$input" ]] || return
    for jail in $list; do
        if [[ "$input" == "$jail" && "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            TARGET_JAIL=$input
            return 0
        fi
    done
    message 'Select an enabled jail from the list.' '请选择列表中已启用的 Jail。'
    pause_panel
    return 1
}

# --- Service setup, whitelist removal, diagnostics and statistics ---
validate_log_path() {
    # Restrict to one literal readable file, avoiding glob and INI interpolation.
    [[ "$1" == /* && "$1" != *[[:space:]%\;\#\[\]\*\?\\]* && -f "$1" && -r "$1" ]]
}

filter_path() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    [[ -f "$CONF_DIR/filter.d/$1.conf" ]] || return 1
    printf '%s/filter.d/%s.conf\n' "$CONF_DIR" "$1"
}

jail_exists() {
    local file
    fail2ban-client status "$1" >/dev/null 2>&1 && return 0
    for file in "$CONF_DIR/jail.conf" "$CONF_DIR"/jail.d/*.conf \
        "$JAIL_CONF" "$CONF_DIR"/jail.d/*.local; do
        [[ -f "$file" ]] || continue
        if awk -v jail="$1" '
            /^[ \t]*\[/ {
                section=$0; sub(/^[ \t]*\[/,"",section); sub(/\].*$/, "",section)
                if (section == jail) found=1
            }
            END { exit !found }
        ' "$file"; then return 0; fi
    done
    return 1
}

create_service_jail() {
    local jail=$1 filter=$2 ports=$3 backend=$4 log=$5 previous=$TARGET_JAIL result=0
    [[ "$jail" =~ ^panel-[a-zA-Z0-9_-]+$ ]] || return 1
    filter_path "$filter" >/dev/null || return 1
    ports=$(normalize_ports "$ports") || return 1
    jail_exists "$jail" && {
        message 'Jail already exists; select it to edit.' 'Jail 已存在，请切换到该 Jail 修改。'
        return 1
    }
    local settings=(enabled true filter "$filter" port "$ports" backend "$backend"
        maxretry 5 findtime 600 bantime 600)
    case "$backend" in
        auto) validate_log_path "$log" || return 1; settings+=(logpath "$log") ;;
        systemd) [[ "$filter" == sshd ]] || return 1 ;;
        *) return 1 ;;
    esac
    TARGET_JAIL=$jail
    apply_conf "${settings[@]}" || result=$?
    ((result == 0)) || TARGET_JAIL=$previous
    return "$result"
}

service_wizard() {
    local choice filter ports backend=auto log='' suffix confirm
    message 'Service: 1 SSH, 2 Nginx HTTP auth, 3 Apache auth (empty cancels)' \
        '服务：1 SSH，2 Nginx HTTP 认证，3 Apache 认证（留空取消）'
    read -r choice || return
    case "$choice" in
        1) filter=sshd ;;
        2) filter=nginx-http-auth ;;
        3) filter=apache-auth ;;
        *) return ;;
    esac
    filter_path "$filter" >/dev/null || {
        message "Missing installed filter: $filter" "缺少已安装过滤器：$filter"; pause_panel; return 1;
    }
    message "Jail name suffix (created as panel-<suffix>; e.g. $filter; empty cancels):" \
        "Jail 名称后缀（创建为 panel-<后缀>，例如 ${filter}；留空取消）："
    read -r suffix || return
    [[ -n "$suffix" ]] || return
    [[ "$suffix" =~ ^[a-zA-Z0-9_-]+$ ]] || { message 'Invalid name.' '名称无效。'; pause_panel; return 1; }
    message 'Enter listening ports, e.g. 22,2222 or 80,443 (empty cancels):' \
        '输入服务实际监听端口，例如 22,2222 或 80,443（留空取消）：'
    read -r ports || return
    [[ -n "$ports" ]] || return
    ports=$(normalize_ports "$ports") || { message 'Invalid ports.' '端口无效。'; pause_panel; return 1; }
    if [[ "$filter" == sshd ]]; then
        message 'Log source: 1 file, 2 systemd journal (empty cancels)' '日志来源：1 文件，2 systemd journal（留空取消）'
        read -r choice || return
        case "$choice" in 1) backend=auto ;; 2) backend=systemd ;; *) return ;; esac
    fi
    if [[ "$backend" == auto ]]; then
        message 'Enter one existing log file (absolute path, no spaces/globs; empty cancels):' \
            '输入一个已存在的日志文件（绝对路径，不含空格或通配符；留空取消）：'
        read -r log || return
        [[ -n "$log" ]] || return
        validate_log_path "$log" || { message 'Unreadable or invalid log path.' '日志路径无效或不可读。'; pause_panel; return 1; }
    fi
    message "Create panel-$suffix: filter=$filter ports=$ports backend=$backend log=$log" \
        "创建 panel-${suffix}：过滤器=$filter 端口=$ports 后端=$backend 日志=$log"
    message 'Retries=5, findtime=600s, bantime=600s; action and whitelist inherit existing defaults.' \
        '重试次数=5，监测窗口=600秒，封禁=600秒；封禁动作及白名单继承已有默认配置。'
    message 'Enable this jail now? Avoid duplicate monitoring of an existing jail. (y/n)' \
        '立即启用该 Jail？请避免与已有 Jail 重复监控同一服务。(y/n)'
    read -r confirm || return
    [[ "$confirm" == y ]] || return 0
    create_service_jail "panel-$suffix" "$filter" "$ports" "$backend" "$log"
    pause_panel
}

# Read the runtime whitelist so inherited entries survive a per-jail override.
runtime_whitelist() {
    local output
    output=$(fail2ban-client get "$TARGET_JAIL" ignoreip) || return 1
    printf '%s\n' "$output" | sed -n 's/^[| `+-]* //p' | paste -sd ' ' -
}

whitelist_without() {
    local list=$1 remove=$2 entry result='' found=false
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        if [[ "$entry" == "$remove" ]]; then found=true; continue; fi
        result+="${result:+ }$entry"
    done < <(printf '%s\n' "$list" | tr ' \t' '\n')
    [[ "$found" == true ]] || return 1
    printf '%s\n' "$result"
}

remove_whitelist() {
    local current entry updated confirm
    current=$(runtime_whitelist) || { message 'Cannot read active whitelist.' '无法读取生效中的白名单。'; pause_panel; return 1; }
    message "Whitelist ($TARGET_JAIL): $current" "白名单（${TARGET_JAIL}）：$current"
    message 'Enter the exact IP/CIDR/hostname to remove (empty cancels):' '输入要删除的完整 IP/CIDR/主机名（留空取消）：'
    read -r entry || return
    [[ -n "$entry" ]] || return
    updated=$(whitelist_without "$current" "$entry") || {
        message 'Exact entry not found.' '没有找到完全匹配的条目。'; pause_panel; return 1;
    }
    message "Remove $entry for this jail? It may become bannable, including your SSH address. (y/n)" \
        "从当前 Jail 删除 ${entry}？此地址将可能被封禁，包括当前 SSH 地址。(y/n)"
    read -r confirm || return
    [[ "$confirm" == y ]] || return 0
    apply_conf ignoreip "$updated"
    pause_panel
}

run_log_diagnostic() {
    local source=$1 filter=$2 path
    path=$(filter_path "$filter") || return 1
    command -v fail2ban-regex >/dev/null 2>&1 || {
        message 'fail2ban-regex is not installed.' '未安装 fail2ban-regex。'; return 1;
    }
    if [[ "$source" == systemd-journal ]]; then
        [[ "$filter" == sshd ]] || return 1
    else
        validate_log_path "$source" || return 1
    fi
    fail2ban-regex "$source" "$path"
}

log_diagnostic() {
    local filter source input
    filter=$(get_conf filter)
    source=$(get_conf logpath)
    [[ "$(get_conf backend)" != systemd ]] || source=systemd-journal
    message "Filter name [$filter] (Enter uses default; q cancels):" "过滤器名称 [$filter]（回车使用默认值；q 取消）："
    read -r input || return
    [[ "$input" != q ]] || return
    filter=${input:-$filter}
    filter_path "$filter" >/dev/null || { message 'Choose an installed filter name without options.' '请选择已安装的过滤器名称，不含附加参数。'; pause_panel; return 1; }
    message "Log file [$source] (Enter uses default; q cancels; SSH also accepts systemd-journal):" \
        "日志文件 [$source]（回车使用默认值；q 取消；SSH 可填 systemd-journal）："
    read -r input || return
    [[ "$input" != q ]] || return
    source=${input:-$source}
    message 'Read-only filter test. Check matched/missed counts; no bans are applied.' \
        '只读过滤器测试：请查看匹配与未匹配数量，不会执行封禁。'
    run_log_diagnostic "$source" "$filter" || message 'Diagnostic failed; check path, filter and journal support.' '诊断失败，请检查路径、过滤器和 journal 支持。'
    pause_panel
}

# Parse exact action tokens; retain IPv6 and exclude other jails / Restore Ban.
ban_events() {
    awk -v jail="$TARGET_JAIL" '
        { for (i=1; i<NF; i++) if ($i == "[" jail "]" && $(i+1) == "Ban" && i+2 <= NF)
            print $1, $(i+2) }
    ' "$LOG_FILE"
}

ban_statistics() {
    local events
    message "Live counters ($TARGET_JAIL):" "实时计数（${TARGET_JAIL}）："
    fail2ban-client status "$TARGET_JAIL" || message 'Jail status unavailable.' '无法读取 Jail 状态。'
    if [[ ! -f "$LOG_FILE" || ! -r "$LOG_FILE" ]]; then
        message "No readable file: $LOG_FILE. Journal/rotated logs are not counted." \
            "日志文件不可读：${LOG_FILE}。不统计 journal 或轮转日志。"
        pause_panel
        return 1
    fi
    events=$(ban_events) || return 1
    message "File statistics: $LOG_FILE (selected jail; excludes rotated logs and Restore Ban)" \
        "文件统计：${LOG_FILE}（仅当前 Jail；不含轮转日志及 Restore Ban）"
    message 'Ban events / distinct IPs:' '封禁事件数 / 独立 IP 数：'
    printf '%s\n' "$events" | awk 'NF==2 {total++; ips[$2]=1} END {for (ip in ips) n++; print total+0, n+0}'
    message 'Top 10 IPs (events, IP):' '前 10 个 IP（事件数、IP）：'
    printf '%s\n' "$events" | awk 'NF==2 {counts[$2]++} END {for(ip in counts) print counts[ip], ip}' | sort -k1,1nr -k2,2 | head -n 10
    message 'Daily events (date, count):' '每日事件（日期、数量）：'
    printf '%s\n' "$events" | awk 'NF==2 {counts[$1]++} END {for(day in counts) print day, counts[day]}' | sort
    pause_panel
}

get_status() {
    if fail2ban-client ping >/dev/null 2>&1; then
        if ! fail2ban-client status "$TARGET_JAIL" >/dev/null 2>&1; then
            message "Service active; jail $TARGET_JAIL is inactive." "服务运行中；Jail $TARGET_JAIL 未启用。"
            return
        fi
        local count
        count=$(fail2ban-client status "$TARGET_JAIL" 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
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
validate_int() { [[ "$1" =~ ^[0-9]+$ && "$1" =~ [1-9] ]]; }
validate_factor() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ && "$1" =~ [1-9] ]]; }

# --- Feature Modules ---

change_param() {
    local name=$1 key=$2 type=$3 new_val
    local current
    current=$(get_conf "$key")
    echo -e "\n${BLUE}Modifying: ${name}${PLAIN}"
    echo -e "Current Value: ${GREEN}$(fmt_unit "$current" "$type")${PLAIN}"
    if [ "$type" == "time" ]; then echo -e "${GRAY}(Suffixes: s=sec, m=min, h=hour, d=day)${PLAIN}"; fi
    
    while true; do
        read -r -p "Enter new value (Leave empty to cancel): " new_val || return
        if [ -z "$new_val" ]; then return; fi
        if [ "$type" == "time" ] && validate_time "$new_val"; then break; fi
        if [ "$type" == "int" ] && validate_int "$new_val"; then break; fi
        if [ "$type" == "factor" ] && validate_factor "$new_val"; then break; fi
        echo -e "${RED}Invalid format. Please try again.${PLAIN}"
    done
    
    apply_conf "$key" "$new_val"
    pause_panel
}

toggle_service() {
    echo -e "\n${BLUE}--- Service Toggle ---${PLAIN}"
    if fail2ban-client ping >/dev/null 2>&1; then
        read -r -p "Stop and disable Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            systemctl stop fail2ban; systemctl disable fail2ban
            echo -e "${RED}Service stopped.${PLAIN}"
        fi
    else
        read -r -p "Enable and start Fail2ban? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then 
            echo -e "${BLUE}Starting service (please wait)...${PLAIN}"
            systemctl enable fail2ban
            systemctl start fail2ban
            
            # Loop check for startup
            local attempt
            for ((attempt=0; attempt<5; attempt++)); do
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
    local banned_list
    banned_list=$(fail2ban-client status "$TARGET_JAIL" 2>/dev/null | grep "Banned IP list" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^[ \t]*//')
    [ -z "$banned_list" ] && banned_list="None"

    echo -e "Current Banned List: ${RED}${banned_list}${PLAIN}"
    read -r -p "Enter IP to unban (Empty to cancel): " target_ip
    [ -z "$target_ip" ] && return
    
    fail2ban-client set "$TARGET_JAIL" unbanip "$target_ip"
    if [ $? -eq 0 ]; then echo -e "${GREEN}Unbanned successfully: $target_ip${PLAIN}"; else echo -e "${RED}Operation failed.${PLAIN}"; fi
    read -n 1 -s -r -p "Press any key to continue..."
}

add_whitelist() {
    echo -e "\n${BLUE}--- Whitelist Management ---${PLAIN}"
    local current_list
    current_list=$(get_conf "ignoreip")
    
    echo -e "Current Whitelist ($TARGET_JAIL): ${YELLOW}${current_list:-Inherited global or None}${PLAIN}"
    local current_ip
    current_ip=$(printf '%s\n' "$SSH_CLIENT" | awk '{print $1}')
    
    read -r -p "Enter IP to whitelist (Default local: ${current_ip}): " input_ip
    [ -z "$input_ip" ] && input_ip="$current_ip"
    [ -z "$input_ip" ] && echo -e "${RED}Unable to get IP.${PLAIN}" && return
    
    if echo "$current_list" | tr ' ' '\n' | grep -Fxq -- "$input_ip"; then
        echo -e "${YELLOW}IP is already whitelisted.${PLAIN}"
    else
        if [ -z "$current_list" ]; then
            apply_conf "ignoreip" "$input_ip"
        else
            apply_conf "ignoreip" "$current_list $input_ip"
        fi
        pause_panel
    fi
}

view_logs() {
    clear
    echo -e "${BLUE}=== Audit Logs (Last 20 lines) ===${PLAIN}"
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}Log file not found: $LOG_FILE${PLAIN}"
    else
        grep -F "[$TARGET_JAIL]" "$LOG_FILE" | grep -E "(Ban|Unban)" 2>/dev/null | tail -n 20 | \
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
        local inc
        inc=$(get_conf "bantime.increment")
        local fac
        fac=$(get_conf "bantime.factor")
        local max
        max=$(get_conf "bantime.maxtime")
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        echo -e "${BLUE}=== Advanced: Exponential Ban Settings ($TARGET_JAIL) ===${PLAIN}"
        echo -e "Description: Ban time increases exponentially for repeated offenders."
        echo -e "-------------------------------------------"
        echo -e "  1. Increment Mode   [${S_INC}]"
        echo -e "  2. Growth Factor    [${YELLOW}${fac:-Not Set}${PLAIN}] $(fmt_unit "${fac}" "factor")"
        echo -e "  3. Max Ban Time     [${YELLOW}${max:-Not Set}${PLAIN}] $(fmt_unit "${max}" "time")"
        echo -e "-------------------------------------------"
        echo -e "  0. Back"
        echo -e ""
        read -r -p "Select [0-3]: " sc || return
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; apply_conf "bantime.increment" "$ns"; pause_panel ;;
            2) change_param "Growth Factor (Multiplier)" "bantime.factor" "factor" ;;
            3) change_param "Max Ban Time" "bantime.maxtime" "time" ;;
            0) return ;;
        esac
    done
}

# --- Categorized navigation: jail -> policy -> addresses -> diagnostics -> service ---
menu_header() {
    clear
    message '=== Fail2ban Manager v1.6 ===' '=== Fail2ban 管理面板 v1.6 ==='
    message "Current jail: $TARGET_JAIL | Ports: $(get_conf port)" "当前 Jail：$TARGET_JAIL | 端口：$(get_conf port)"
    printf '%s
' '------------------------------------------------'
}

menu_category() {
    local category=$1 choice
    while true; do
        menu_header
        case "$category" in
            jails)
                message 'Jails and ports' '监控与端口'
                message '  1. Select enabled jail
  2. Configure ports
  3. Create service jail' \
                    '  1. 切换已启用 Jail
  2. 配置监控端口
  3. 新建服务监控' ;;
            policy)
                message 'Ban policy' '封禁策略'
                message "  1. Max retries [$(get_conf maxretry)]" "  1. 最大重试次数 [$(get_conf maxretry)]"
                message "  2. Initial ban time [$(get_conf bantime)]" "  2. 初始封禁时长 [$(get_conf bantime)]"
                message "  3. Find time [$(get_conf findtime)]" "  3. 监测时间窗口 [$(get_conf findtime)]"
                message '  4. Exponential bans' '  4. 指数封禁设置' ;;
            addresses)
                message 'IP and whitelist management' 'IP 与白名单'
                message '  1. Unban IP
  2. Add whitelist entry
  3. Remove whitelist entry' \
                    '  1. 手动解封 IP
  2. 添加白名单
  3. 删除白名单' ;;
            diagnostics)
                message 'Logs and diagnostics' '日志与诊断'
                message '  1. Ban statistics
  2. Recent ban logs
  3. Test log matches' \
                    '  1. 封禁统计
  2. 最近封禁日志
  3. 日志匹配诊断' ;;
            service)
                message 'Service management (all jails)' '服务管理（影响所有 Jail）'
                printf '%s
' "$(get_status)"
                message '  1. Start/stop service
  2. Validate configuration / repair IPv6 default' \
                    '  1. 开启/停止服务
  2. 校验配置 / 修复 IPv6 默认设置' ;;
        esac
        message '  0. Back' '  0. 返回上一级'
        message 'Select:' '请选择：'
        read -r choice || return 0
        [[ "$choice" != 0 ]] || return 0
        case "$category:$choice" in
            jails:1) select_jail ;;
            jails:2) manage_ports ;;
            jails:3) service_wizard ;;
            policy:1) change_param "$(message 'Max retries' '最大重试次数')" maxretry int ;;
            policy:2) change_param "$(message 'Initial ban time' '初始封禁时长')" bantime time ;;
            policy:3) change_param "$(message 'Find time' '监测时间窗口')" findtime time ;;
            policy:4) menu_exponential ;;
            addresses:1) unban_ip ;;
            addresses:2) add_whitelist ;;
            addresses:3) remove_whitelist ;;
            diagnostics:1) ban_statistics ;;
            diagnostics:2) view_logs ;;
            diagnostics:3) log_diagnostic ;;
            service:1) toggle_service ;;
            service:2) ensure_ipv6_default; pause_panel ;;
            *) message 'Invalid selection.' '无效选项。'; pause_panel ;;
        esac
    done
}

menu_main() {
    local choice
    check_install || return 1
    ensure_ipv6_default
    pause_panel
    while true; do
        menu_header
        printf '%s
' "$(get_status)"
        message '  1. Jails and ports
  2. Ban policy
  3. IP and whitelist
  4. Logs and diagnostics
  5. Service management
  0. Exit' \
            '  1. 监控与端口
  2. 封禁策略
  3. IP 与白名单
  4. 日志与诊断
  5. 服务管理
  0. 退出'
        message 'Select [0-5]:' '请选择 [0-5]：'
        read -r choice || return 0
        case "$choice" in
            1) menu_category jails ;;
            2) menu_category policy ;;
            3) menu_category addresses ;;
            4) menu_category diagnostics ;;
            5) menu_category service ;;
            0) return 0 ;;
            *) message 'Invalid selection.' '无效选项。'; pause_panel ;;
        esac
    done
}

# Sourcing exposes helpers for tests without requiring root or starting the UI.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if ((EUID != 0)); then
        message 'Run this script as root.' '请使用 root 用户运行此脚本。'
        exit 1
    fi
    menu_main
fi
