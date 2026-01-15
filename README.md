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
<img width="350" height="250" alt="image" src="https://github.com/user-attachments/assets/641cacd8-1c71-4f94-8b36-6f48808d311d" />

<img width="400" height="200" alt="image" src="https://github.com/user-attachments/assets/1d8f534c-e0f9-4daf-913b-d13014eb3a3d" />


## 🚀 快速开始

在您的服务器上执行以下命令下载并运行：# 下载脚本&赋予执行权限&运行脚本

```bash
wget -O f2b.sh https://raw.githubusercontent.com/Kequans/fail2ban-panel/main/f2b_panel_zh.sh && chmod +x f2b.sh && sudo ./f2b.sh
```
——————————————————————————————————————————————————————————————————————————————————————————————————————————————————

# F2B Manager (Fail2ban Shell Panel) 🇺🇸English

A lightweight, standalone Shell script to manage Fail2ban on Linux servers. No more manually editing config files!

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
