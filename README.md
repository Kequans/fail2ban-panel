# F2B Manager (Fail2ban Shell Panel) 🇨🇳中文

F2B Manager 是一个轻量级的 Shell 脚本，旨在简化 Linux 服务器上 Fail2ban 的安装与管理。无需手动编辑复杂的配置文件，通过交互式菜单即可完成大部分日常操作。

## ✨ 功能特性

- 📊 **可视化仪表盘**：实时查看服务运行状态、当前被封禁的 IP 数量。
- ⚙️ **参数热修改**：轻松修改核心参数，如最大重试次数 (`maxretry`)、封禁时长 (`bantime`) 和监测窗口 (`findtime`)。
- 🔓 **一键解封**：列出当前被封禁的 IP 列表，并支持指定 IP 一键解封。
- 🛡️ **白名单管理**：自动检测当前 SSH 连接的 IP，支持快速将其或自定义 IP 加入白名单。
- 📜 **日志审计**：内置日志查看器，支持颜色高亮，快速回溯最近的封禁/解封记录。
- 🚀 **自动部署**：智能检测环境，如果系统未安装 Fail2ban，脚本将自动完成安装与初始化（支持 Debian/Ubuntu/CentOS），并自动修复日志缺失问题。

## ✨ 界面展示
<img width="350" height="250" alt="image" src="https://github.com/user-attachments/assets/6b69e491-9636-47ba-99d9-a4911df351dc" />

<img width="400" height="200" alt="image" src="https://github.com/user-attachments/assets/c4df1851-afbb-47e1-8188-05f4e3e71f22" />

## 🚀 快速开始

在您的服务器上执行以下命令下载并运行：# 下载脚本&赋予执行权限&运行脚本

```bash
wget -O f2b.sh https://raw.githubusercontent.com/Kequans/fail2ban-panel/main/f2b_panel_zh.sh && chmod +x f2b.sh && sudo ./f2b.sh
```
## 更新日志（v1.3）的详细内容：
### 1. 修复显示错乱 Bug (针对 openEuler/CentOS)

问题：在某些系统上，配置文件中存在重复的参数定义，导致脚本读取到多行数据，撑破菜单界面。

修复：修改读取逻辑，强制只读取配置文件的最后一行生效值，确保菜单显示整洁。

### 2. 限制修改范围 (防止误伤)

问题：旧版本使用全局替换，修改 maxretry 会同时改变 Nginx、Apache 等所有模块的设置。

修复：脚本现在通过 [sshd] 标签锁定范围，仅修改 SSH 相关的配置区块，不影响其他服务。

### 3. 修复“重启失败”误报

问题：Fail2ban 重启需要几秒钟加载，脚本检查速度太快，导致服务明明启动成功却提示“失败”。

修复：在重启和启动功能中增加了智能轮询机制（循环检查 5 次，每次 1 秒）。脚本会耐心等待服务就绪，彻底消除了假警报。
——————————————————————————————————————————————————————————————————————————————————————————————————————————————————

# F2B Manager (Fail2ban Shell Panel) 🇺🇸English

A lightweight, standalone Shell script to manage Fail2ban on Linux servers. No more manually editing config files!

## UI

<img width="350" height="250" alt="image" src="https://github.com/user-attachments/assets/641cacd8-1c71-4f94-8b36-6f48808d311d" />

<img width="400" height="200" alt="image" src="https://github.com/user-attachments/assets/1d8f534c-e0f9-4daf-913b-d13014eb3a3d" />

## Features

- 📊 **Dashboard**: View current service status and banned IP count.
- ⚙️ **Config Manager**: Easily modify `maxretry`, `bantime`, and `findtime`.
- 🔓 **Unban Manager**: List currently banned IPs and unban them with one click.
- 🛡️ **Whitelist**: Add your current IP or custom IPs to the whitelist.
- 📜 **Log Viewer**: View the latest ban/unban actions with color highlighting.
- 🚀 **Auto-Install**: Automatically detects if Fail2ban is missing and installs it (Debian/Ubuntu/CentOS).

## Quick Start

Download and run the script:

```bash
wget -O f2b.sh https://raw.githubusercontent.com/Kequans/fail2ban-panel/main/f2b_panel.sh && chmod +x f2b.sh && sudo ./f2b.sh
```
## Update log
### 1. Fixed Display Bug (for openEuler/CentOS)

Issue: On some systems, duplicate parameter definitions in the config file caused the script to read multiple lines, breaking the menu layout.

Fix: Updated the read logic to force fetching only the last effective line, ensuring a clean menu display.

### 2. Scoped Configuration (Preventing Side Effects)

Issue: The previous version used global replacement. Changing maxretry would accidentally alter settings for all jails (e.g., Nginx, Apache).

Fix: The script now locks the scope to the [sshd] block. It only modifies SSH-related configurations, leaving other services untouched.

### 3. Fixed "Restart Failed" False Positives

Issue: Fail2ban takes a few seconds to reload. The script checked the status too quickly, reporting "Failed" even when the service started successfully.

Fix: Implemented a smart polling mechanism (checks 5 times with a 1-second interval) for restart and start actions. The script now waits for the service to be ready, eliminating false alarms.
