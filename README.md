# F2B Manager (Fail2ban Shell Panel) 🇨🇳中文

F2B Manager 是一个轻量级的 Shell 脚本，旨在简化 Linux 服务器上 Fail2ban 的安装与管理。无需手动编辑复杂的配置文件，通过交互式菜单即可完成大部分日常操作。

## ✨ 功能特性

- 📊 **可视化仪表盘**：实时查看服务运行状态、当前被封禁的 IP 数量。
- ⚙️ **参数热修改**：轻松修改核心参数，如最大重试次数 (`maxretry`)、封禁时长 (`bantime`) 和监测窗口 (`findtime`)。
- 🔓 **一键解封**：列出当前被封禁的 IP 列表，并支持指定 IP 一键解封。
- 🛡️ **白名单管理**：自动检测当前 SSH 连接的 IP，支持快速将其或自定义 IP 加入白名单。
- 📜 **日志审计**：内置日志查看器，支持颜色高亮，快速回溯最近的封禁/解封记录。
- 🚀 **自动部署**：智能检测环境，如果系统未安装 Fail2ban，脚本将自动完成安装与初始化（支持 Debian/Ubuntu/CentOS），并自动修复日志缺失问题。

## 面板菜单（v1.6）

主菜单按管理流程组织，所有子菜单按 `0` 返回上一级，首页按 `0` 退出。每页顶部显示当前 Jail 与配置端口，切换 Jail 后在子菜单之间保留选择。

| 主菜单 | 子菜单顺序 |
| --- | --- |
| 1 监控与端口 | 1 切换 Jail · 2 配置端口 · 3 新建服务监控 |
| 2 封禁策略 | 1 最大重试次数 · 2 初始封禁时长 · 3 监测窗口 · 4 指数封禁 |
| 3 IP 与白名单 | 1 解封 IP · 2 添加白名单 · 3 删除白名单 |
| 4 日志与诊断 | 1 封禁统计 · 2 最近日志 · 3 日志匹配诊断 |
| 5 服务管理 | 1 开启/停止服务 · 2 校验配置 / 修复 IPv6 默认设置 |

`WARNING 'allowipv6' not defined in 'Definition'. Using default one: 'auto'` 表示 Fail2ban 使用了默认 IPv6 行为，不代表 Jail 参数修改失败，也与 `7d`、`maxretry = 3` 无关。

启动面板时会校验配置；仅当校验成功且出现这条确切警告时，自动创建 `/etc/fail2ban/fail2ban.d/zz-f2b-panel.local`：

```ini
[Definition]
allowipv6 = auto
```

该值与警告中的默认行为一致。新增文件再次校验，失败或警告持续则移除；已有文件与显式配置不会被覆盖。首次修复会显示原始诊断及修复结果，后续配置操作不再重复该缺失设置警告。其他警告和错误保留。也可从 **5 → 2** 手动运行检查。

## 多个 Jail 可以同时运行吗？

**可以。** 同一个 Fail2ban 服务可以同时运行多个已启用的 Jail。每个 Jail 使用自己的过滤器、日志来源和封禁策略，例如 `sshd` 保护 SSH，`panel-web` 保护 Nginx HTTP 认证。

“当前 Jail”只是面板当前查看和修改的对象。**切换 Jail 不会停止其他 Jail，退出面板也不会停止 Fail2ban。** 新建服务监控成功后，新 Jail 与已有 Jail 同时运行。

| 操作 | 作用范围 |
| --- | --- |
| 切换 Jail（1 → 1） | 仅切换面板当前管理对象 |
| 修改端口、封禁参数或白名单 | 修改并重载当前 Jail，其他 Jail 继续运行 |
| 手动解封 IP（3 → 1） | 仅解除当前 Jail 对该 IP 的封禁 |
| 查看日志、统计或运行匹配诊断 | 查看当前 Jail，或只读测试选定的日志与过滤器 |
| 新建服务监控（1 → 3） | 新增并启用一个 Jail，成功后选中它 |
| 开启/停止服务（5 → 1） | 作用于整个 Fail2ban 服务及全部 Jail，并启用/禁用开机启动 |

### 示例：同时保护 SSH 与 Nginx

1. 保留已运行的 `sshd` Jail；若 SSH 使用 `22,2222`，切换至它并在 **1 → 2** 设置这两个端口。
2. 通过 **1 → 3** 选择 Nginx HTTP 认证，名称后缀填写 `web`，端口填写 `80,443`，日志填写实际的 Nginx 错误日志路径。确认后创建 `panel-web`。
3. 通过 **1 → 1** 在 `sshd` 与 `panel-web` 之间切换，分别设置策略。两个 Jail 会继续同时运行。
4. 在服务器上查看运行状态：

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status panel-web
```

第一条命令的 `Jail list` 应包含两个名称；后两条分别查看它们的状态。需要服务已安装、日志正确、对应过滤器可用且 Jail 成功启用。

### 多 Jail 使用注意

- 同一 IP 可以同时被多个 Jail 封禁。在其中一个 Jail 解封后，其他 Jail 的封禁仍可能阻止访问。
- 白名单也是按 Jail 生效的；一个 Jail 放行某 IP，不代表其他 Jail 自动放行。面板修改白名单时会保存当前 Jail 的独立列表。
- 封禁影响哪些端口由 action 决定。默认多端口 action 使用配置端口；`allports` 或自定义 action 可能影响其他服务，所以不同 Jail 的网络影响可能重叠。
- 同一个 SSH 服务监听多个端口时，通常在一个 `sshd` Jail 中设置完整端口列表即可；不同服务使用各自匹配的过滤器与日志。避免创建配置相同、重复处理同一日志的 Jail。

## 端口与 Jail 管理

- 菜单 **1 → 2「配置监控端口」**：显示所选 Jail 的配置端口，输入完整列表替换原列表。例如 `22,2222`，或 `80,443,8000:8010`。要删除端口，输入不含该端口的新列表；留空取消。
- 菜单 **1 → 1「切换已启用 Jail」**：从已启用的 Jail 中选择管理对象。切换后参数、白名单、解封和日志都针对该 Jail；服务启停仍控制整个服务。
- 输入检查：端口必须为 `1–65535`，支持逗号分隔和冒号区间，自动去重。为兼容 `iptables-multiport`，最多 15 槽位，区间占两个槽位。
- 修改写入 `/etc/fail2ban/jail.d/zz-f2b-panel.local`。先备份、校验，再重载所选 Jail；失败自动恢复。中英文版功能一致。

**SSH 示例**：先确认 SSH 已监听 `2222`，再进入菜单 1 → 2，输入 `22,2222` 并确认。以后停止使用 22 时，可将列表改为 `2222`。

**其他服务示例**：先配置并启用 `nginx-http-auth` Jail（包括正确的 filter、logpath/backend），菜单 1 → 1 选择它，再用菜单 1 → 2 设置 `80,443`。

Fail2ban 通过日志识别攻击，`port` 决定封禁的目标端口，并不自动监控任意服务或修改服务监听端口。使用 `allports` 或自定义 action 时，端口列表可能不限制封禁范围。面板显示配置值；复杂插值、include 或条件配置请以 Fail2ban 实际配置和防火墙规则为准。需支持 `fail2ban-client -t` 和 `reload --restart <jail>` 的 Fail2ban 版本。

### 代码整理与修复

按配置读写、输入校验、功能和菜单分区，保留中英文脚本各自独立运行。修复了白名单空格丢失、IPv6 地址显示截断、最大重试次数允许小数、未启用 Jail 被误报为正常运行的问题，并让日志随当前 Jail 筛选。设计与限制见 [DESIGN.md](DESIGN.md)。

### 本地检查

```bash
bash -n f2b_panel.sh
bash -n f2b_panel_zh.sh
shellcheck -S warning f2b_panel.sh f2b_panel_zh.sh tests/test_panel.sh
bash tests/test_panel.sh
```

回归测试使用临时目录与模拟 Fail2ban，不会操作本机服务或防火墙。实际 Linux 封禁行为需要在目标环境验证。

## 服务向导、白名单删除、诊断和统计

| 菜单 | 功能 | 使用方式 |
| --- | --- | --- |
| 1 → 3 | 服务配置向导 | 选择 SSH、Nginx HTTP 认证或 Apache 认证，输入名称后缀、实际监听端口及日志来源，预览并确认启用 |
| 3 → 3 | 删除白名单条目 | 输入当前白名单中的完整 IP、CIDR 或主机名，确认后只修改所选 Jail |
| 4 → 3 | 日志匹配诊断 | 选择本机过滤器和日志文件，通过 `fail2ban-regex` 查看匹配与未匹配数量 |
| 4 → 1 | 封禁统计 | 查看实时 Jail 状态、历史封禁事件数、独立 IP 数、Top 10 IP 和每日事件数 |

### 服务配置向导

例如：菜单 1 → 3 → 选择 Nginx HTTP 认证 → 后缀 `web` → 端口 `80,443` → 日志 `/var/log/nginx/error.log` → 确认。面板创建 `panel-web` 并切换到该 Jail。请先确认所选日志确实包含对应的认证失败记录；HTTP 认证过滤器不覆盖所有 Web 攻击类型。

向导要求所选过滤器已安装在 `/etc/fail2ban/filter.d/`。文件后端只接受一个可读的绝对路径，不支持空格、通配符和配置插值。SSH 也可选择 `systemd journal`，实际支持由 Fail2ban 配置校验和启动结果确认。

新 Jail 默认重试 5 次，监测窗口与封禁时间均为 600 秒，封禁动作及白名单继承系统默认值。整组配置一次校验、一次重载，失败恢复整组配置，并尝试停止部分启动的新 Jail。已有同名 Jail 不会被覆盖。服务需由管理员预先安装并启动；向导不会修改监听设置。避免与已有 Jail 重复监控同一服务。

### 白名单删除

按完整条目匹配，支持删除 IPv4、IPv6、CIDR 和已有主机名，允许删除最后一项。面板从运行中的 Jail 获取白名单，删除后保存为该 Jail 的独立列表，因此后续全局白名单修改不会自动合并到此列表。删除当前 SSH 地址或其所在网段后，连接来源可能被封禁；操作前会提示确认。

### 日志诊断与统计范围

诊断只读取日志，不执行封禁。默认读取当前 Jail 的 `filter`、`logpath` 和 `backend`；复杂过滤器参数或多文件配置需手动指定一个已安装的过滤器名称和一个日志文件。SSH 可使用 `systemd-journal`。诊断按所选过滤器默认配置运行，不复现 Jail 中的自定义 failregex、日期模式或 journalmatch；命令成功不代表一定有匹配，请查看输出计数。

统计的实时部分来自 `fail2ban-client status`；历史部分只统计当前 `/var/log/fail2ban.log` 中所选 Jail 的 `Ban` 事件，包含 IPv6，排除 `Unban`、`Restore Ban` 和其他 Jail。轮转、压缩日志与 journal 不在统计范围内。日志缺失时仍显示实时状态，并明确提示历史统计不可用。

### 后续可扩展功能（尚未实现）

- IPv4/IPv6/CIDR 新增白名单校验。
- 配置历史备份、手动恢复和导出菜单。
- 轮转日志/journal 历史统计、手动封禁和通知。

## ✨ 界面展示

以下为历史版本截图，当前分类菜单以上方说明为准。

<img width="350" height="250" alt="image" src="https://github.com/user-attachments/assets/6b69e491-9636-47ba-99d9-a4911df351dc" />

<img width="400" height="200" alt="image" src="https://github.com/user-attachments/assets/c4df1851-afbb-47e1-8188-05f4e3e71f22" />

## 🚀 快速开始

在提供 systemd 的 Linux 服务器上下载并以 root 权限运行：

```bash
wget -O f2b.sh https://raw.githubusercontent.com/Kequans/fail2ban-panel/main/f2b_panel_zh.sh && chmod +x f2b.sh && sudo ./f2b.sh
```
## 历史更新日志（v1.3）

以下记录描述 v1.3 当时的实现；当前版本已支持多 Jail，配置写入独立覆盖文件。

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

## Navigation and IPv6 default repair (v1.6)

Main categories: **1 Jails and ports**, **2 Ban policy**, **3 IP and whitelist**, **4 Logs and diagnostics**, **5 Service management**. Use `0` to return or exit; the selected jail persists across categories. Menu paths below use `category → item`.

Startup checks the configuration. If the successful check reports the exact missing `allowipv6` warning, the panel creates `/etc/fail2ban/fail2ban.d/zz-f2b-panel.local` with `[Definition] allowipv6 = auto`, preserving Fail2ban's existing default behavior. The new file is validated and removed on failure; existing files/settings are preserved. Diagnostics remain visible. **5 → 2** runs the check manually.

## Can multiple jails run at the same time?

**Yes.** One Fail2ban service can run multiple enabled jails, each with its own filter, log source and ban policy. For example, `sshd` and a wizard-created `panel-web` can protect SSH and Nginx HTTP authentication at the same time.

Selecting a jail only changes the panel's current management target. It does not stop other jails. Exiting the panel leaves Fail2ban running. Port, policy, whitelist and unban operations target the selected jail; **5 → 1** starts/stops the entire service and enables/disables its startup at boot.

Keep the existing `sshd` jail, then use **1 → 3** to create a Nginx HTTP authentication jail with suffix `web`, ports `80,443` and the actual error-log path. Switch between them with **1 → 1**. Verify both are active with:

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status panel-web
```

The same IP may be banned by several jails. Unbanning or whitelisting it in one jail does not remove another jail's restrictions. Allports/custom actions may also affect other services. For one SSH service listening on multiple ports, normally configure one jail's full port list; avoid duplicate jails processing identical events.

## Ports and jail selection

Use menu **1 → 2** to replace the selected jail's port list (e.g. `22,2222` or `80,443,8000:8010`), and menu **1 → 1** to select an already enabled jail. Empty input cancels. Numeric ports must be within 1–65535; the list is limited to 15 iptables-multiport slots (two per range).

Changes are stored in `/etc/fail2ban/jail.d/zz-f2b-panel.local`, validated with `fail2ban-client -t`, and applied by restarting only the selected jail via `reload --restart <jail>`. Failed changes restore the previous file. Parameters, whitelist, unbanning and logs follow the selected jail; service start/stop remains global.

Ports control ban actions. They do not change listening ports or create monitoring filters. Configure and enable the matching service jail first. Allports/custom actions may ignore this setting. Complex includes/interpolation require checking the effective Fail2ban configuration and firewall rules. Both language editions remain standalone downloads.

Regression tests: `bash tests/test_panel.sh` (mocked client; no host service changes). Real firewall behavior still requires Linux integration testing.

## Setup, whitelist removal, diagnostics and statistics

- **1 → 3 — Service setup wizard:** create a new `panel-<name>` jail for SSH, Nginx HTTP authentication or Apache authentication. Installed filters and a readable log file are required; SSH also supports the systemd journal. The entire configuration is validated and applied together, with rollback on failure. Existing names are rejected. Actions and whitelist inherit system defaults.
- **3 → 3 — Remove whitelist entry:** remove an exact IP/CIDR/hostname from the selected jail, including its final entry. This persists a per-jail list; later global whitelist changes are not merged automatically.
- **4 → 3 — Diagnose log matches:** run a read-only `fail2ban-regex` test against an installed filter and one file (or `systemd-journal` for SSH). Inspect matched/missed counts. Custom jail regex settings are not reproduced.
- **4 → 1 — Ban statistics:** show live jail counters plus Ban events, distinct IPs, top 10 IPs and daily counts from the current Fail2ban log. Rotated logs, journal history, Unban and Restore Ban events are excluded.

The wizard does not install application services or change listening ports. Avoid creating a duplicate monitor for an existing jail. File paths must be absolute and contain no spaces, globs or INI interpolation.

## UI

Screenshots show earlier versions; refer to the current navigation above.

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
## Historical update log (v1.3)

These notes describe v1.3. The current version supports multiple jails and writes a separate override file.

### 1. Fixed Display Bug (for openEuler/CentOS)

Issue: On some systems, duplicate parameter definitions in the config file caused the script to read multiple lines, breaking the menu layout.

Fix: Updated the read logic to force fetching only the last effective line, ensuring a clean menu display.

### 2. Scoped Configuration (Preventing Side Effects)

Issue: The previous version used global replacement. Changing maxretry would accidentally alter settings for all jails (e.g., Nginx, Apache).

Fix: The script now locks the scope to the [sshd] block. It only modifies SSH-related configurations, leaving other services untouched.

### 3. Fixed "Restart Failed" False Positives

Issue: Fail2ban takes a few seconds to reload. The script checked the status too quickly, reporting "Failed" even when the service started successfully.

Fix: Implemented a smart polling mechanism (checks 5 times with a 1-second interval) for restart and start actions. The script now waits for the service to be ready, eliminating false alarms.
