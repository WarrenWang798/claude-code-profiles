# Claude Code Profile Switcher (CCP) 3.0

> 纯 Bash 的 Claude Code 配置管理工具。**基于 .env 文件**，零依赖，终端原生隔离。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/WarrenWang798/claude-code-profiles)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-purple.svg)](https://claude.ai/code)

[English](README.md) | [中文文档](README_CN.md)

---

## 3.0 新特性

- `ccc` 直接读取 profile `.env` 文件，并以进程级环境启动 `claude`
- 移除 `ccp <profile>` 的 shell 切换机制
- `ccp init` 改为只删除 `~/.claude/settings.json` 顶层 `env` 键
- 安装器不再新增 rc 注入，只创建 `~/.local/bin/ccp` 和 `~/.local/bin/ccc`

---

## 为什么选择 CCP？

其他工具管理 API 端点。**CCP 管理 Claude Code 的启动环境，而不是修改您当前 shell。**

**Per-profile env bundles** — 每个 profile 携带任意的自定义环境变量（MODEL、TIMEOUT、FEATURE_FLAGS）。为工作设置 `ANTHROPIC_MODEL=claude-sonnet-4`，为个人使用设置 `ANTHROPIC_MODEL=claude-opus-4`。

**进程级隔离** — `ccc` 读取一个 profile，然后用 `exec env ...` 启动一个 `claude` 进程。无 `eval`，无 shell 污染，无会话间意外串扰。

**真正零依赖** — 纯 Bash 3.2。无 Python，无 Node，无 jq。开箱即用，适用于原生 macOS。

**可审计的简单性** — 对于管理 API 密钥的安全意识开发者：单一文件格式，无外部调用，可读源代码。准确知道按 profile 启动 Claude Code 时运行了什么。

---

## 快速开始

```bash
# 一行命令安装（推荐）
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash

# 确保 ~/.local/bin 在 PATH 中
export PATH="$HOME/.local/bin:$PATH"

# 初始化（一次性，只删除冲突的顶层 `env` 键）
ccp init

# 添加您的第一个 profile
ccp add work

# 使用 profile 启动 Claude Code
ccc work
```

---

## 新的 .env 格式

CCP 3.0 使用简单的 `.env` 文件代替 JSON：

```bash
# ~/.ccp/profiles/work.env
# CCP Profile: work
ANTHROPIC_BASE_URL=https://api.example.com/v1
ANTHROPIC_AUTH_TOKEN=sk-xxxxx
# 自定义环境变量
ANTHROPIC_MODEL=claude-sonnet-4
API_TIMEOUT_MS=600000
```

**优势：**
- ✏️ 人类可读且可编辑
- 🔍 易于调试
- 📋 易于复制/分享
- 🛡️ 无 JSON 解析复杂性

---

## 命令

| 命令 | 描述 |
|---------|-------------|
| `ccc <profile>` | **用指定 profile 启动 Claude Code** |
| `ccc env <profile>` | `ccc <profile>` 的兼容别名 |
| `ccp add <name>` | 添加/更新 profile（交互式） |
| `ccp remove <name>` | 删除 profile |
| `ccp list` | 列出所有 profiles |
| `ccp status` | 显示当前配置和最后一次启动的 profile |
| `ccp set-env <profile> <VAR> <value>` | 设置自定义环境变量 |
| `ccp unset-env <profile> <VAR>` | 删除自定义环境变量 |
| `ccp show-env <profile>` | 显示 profile 的所有环境变量 |
| `ccp init` | 初始化 Claude Code 设置 |
| `ccp help` | 显示帮助 |

---

## 配置位置

```
~/.ccp/
├── profiles/
│   ├── work.env          # Profile 定义
│   ├── personal.env
│   └── ...
└── current               # 最后一次启动的 profile 名称
```

---

## 从 CCP 2.x 迁移

CCP 3.0 调整了启动方式：

- 移除 `ccp <profile>`
- 统一使用 `ccc <profile>` 启动
- 新安装不再向 rc 文件注入 shell 函数

历史版本留下的 rc block 会在 `install.sh` 和 `uninstall.sh` 中自动清理。

---

## 从 CCP 1.x 迁移

CCP 3.0 **与 1.x profiles 不向后兼容**。您需要重新创建 profiles：

```bash
# 旧 profiles 在 ~/.ccp_profiles.json
# 新 profiles 在 ~/.ccp/profiles/*.env

# 1. 备份旧配置
cp ~/.ccp_profiles.json ~/.ccp_profiles.json.backup

# 2. 重新创建 profiles
ccp add work
ccp add personal

# 3. 完成！如果需要，删除旧配置
rm ~/.ccp_profiles.json
```

---

## 安装

### 要求

- Bash 3.2+（macOS 默认）或 Zsh
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 已安装

### 安装

```bash
# 一行命令安装（无需 git clone）
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
```

或本地克隆并安装：

```bash
git clone https://github.com/WarrenWang798/claude-code-profiles.git
cd claude-code-profiles
./install.sh
```

然后确保 `~/.local/bin` 在 `PATH` 中：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 安装内容

```
~/.local/share/ccp/ccp.sh    # 主脚本
~/.local/share/ccp/ccc       # 启动器脚本
~/.local/bin/ccp            # 主脚本链接
~/.local/bin/ccc            # 启动器链接
~/.ccp/profiles/              # Profile .env 文件（首次使用时创建）
```

### 卸载

```bash
# 如果通过 git clone 安装
./uninstall.sh

# 如果通过 curl 安装（下载卸载脚本）
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/uninstall.sh | bash

# 可选：删除配置
rm -rf ~/.ccp
```

---

## 工作原理

```
`ccp` 负责管理 `~/.ccp/profiles` 下的 profile 文件。
`ccc` 读取一个 `.env` 文件，校验必填变量，更新 `~/.ccp/current`，再通过 `exec env` 启动 `claude`。
只有被启动的 `claude` 进程会拿到该 profile 的环境变量。
```

这种架构意味着：
- 启动 profile 只影响被拉起的 `claude` 进程
- 多个终端可以同时运行不同的 profiles
- 无锁文件，无竞态条件，无状态同步问题
- 不依赖 `eval` 或 shell 函数

---

## CCP vs 替代品

| 特性 | CCP 3.0 | CCM | CCS |
|---------|---------|-----|-----|
| 存储格式 | **.env 文件** | JSON | JSON |
| 每个 profile 的自定义环境变量 | **是** | 否 | 否 |
| 终端隔离保证 | **是** | 写入全局配置 | 共享代理状态 |
| 零依赖 | **是** | 是 | 否 (Node.js) |
| 内置提供商预设 | 否 | 7+ | 17+ |
| 代理/路由功能 | 否 | 否 | 是 |
| Web UI | 否 | 否 | 是 |
**选择 CCP 如果：** 您想要可预测的按进程启动控制、最小占用空间、可审计代码，以及 .env 文件的简单性。

**选择 CCM 如果：** 您需要内置提供商预设和更简单的功能集。

**选择 CCS 如果：** 您想要代理层、Web UI，或不介意 Node.js 依赖。

---

## 故障排除

### Claude Code 忽略我的 profile 设置

运行 `ccp init` 清除来自 `~/.claude/settings.json` 的冲突设置：

```bash
ccp init
# 然后重启 Claude Code
ccc work
```

### 环境变量未应用

使用 `ccc` 启动 Claude Code，不要再用 `ccp` 充当切换器：

```bash
# 正确
ccc work

# 错误：`ccp` 现在只负责管理
ccp work
```

### 权限被拒绝

```bash
chmod 600 ~/.ccp/profiles/*.env
```

---

## 相关项目

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — 官方 Claude Code 命令行工具
- [Claude Code Switch (CCM)](https://github.com/foreveryh/claude-code-switch) — 在不同 AI 模型提供商之间切换
- [Claude Code Switch (CCS)](https://github.com/kaitranntt/ccs) — 带 Web UI 的全功能代理
- [Claude Code Router](https://github.com/musistudio/claude-code-router) — 请求路由和负载均衡

---

## 许可证

[MIT 许可证](LICENSE)
