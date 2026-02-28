# Claude Code Profile Switcher (CCP)

> 纯 Bash 的 Claude Code 配置管理工具。零依赖，终端级隔离。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/WarrenWang798/claude-code-profiles)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-purple.svg)](https://claude.ai/code)

[English](README.md) | [中文文档](README_CN.md)

## 为什么选择 CCP？

其他工具管理 API 端点。CCP 管理你的整个终端环境。

**按 Profile 捆绑环境变量** — 每个 profile 可携带任意自定义环境变量（MODEL、TIMEOUT、FEATURE_FLAGS）。工作 profile 设 `ANTHROPIC_MODEL=claude-sonnet-4`，个人 profile 设 `ANTHROPIC_MODEL=claude-opus-4`。同类工具中唯一支持此功能。

**终端原生隔离** — 纯 env var 导出（`stdout`），状态信息走 `stderr`。每个终端拥有独立环境。不污染全局配置，不会意外影响其他终端。不像 CCM 的 `ccm user` 会写入 `~/.claude/settings.json`。

**真正零依赖** — 纯 Bash 3.2。不需要 Python、Node、jq。macOS 开箱即用。单个 ~900 行脚本，15 分钟可审计完毕。

**可审计的简洁** — 对于管理 API key 的安全敏感开发者：一个文件，无外部调用，源码可读。切换 profile 时你能清楚知道执行了什么。

CCP 面向需要可预测环境控制的开发者，而非 provider 抽象。

## 快速开始

```bash
# 一键安装（推荐）
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
source ~/.zshrc  # 或 ~/.bashrc

# 初始化（一次性，清除冲突配置）
ccp init

# 添加第一个 profile
ccp add work

# 使用 profile 启动 Claude Code
ccc work
```

## 功能特性

| 功能 | 说明 |
|------|------|
| **多 Profile 管理** | 存储无限数量的 API 配置 |
| **快速切换** | 一条命令切换 profile |
| **一键启动** | `ccc <profile>` 切换并启动 Claude Code |
| **自定义环境变量** | 为每个 profile 设置任意环境变量 |
| **终端隔离** | 不同终端可同时使用不同 profile |
| **零依赖** | 纯 Bash 3.2，无需 Python/Node/jq |
| **安全存储** | API key 在所有输出中脱敏显示 |

## 安装

### 系统要求

- Bash 3.2+（macOS 默认）或 Zsh
- 已安装 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)

### 安装步骤

```bash
# 一键安装（无需 git clone）
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
```

或克隆后本地安装：

```bash
git clone https://github.com/WarrenWang798/claude-code-profiles.git
cd claude-code-profiles
./install.sh
```

然后重载 shell：

```bash
source ~/.zshrc  # 或 ~/.bashrc
```

### 安装内容

```
~/.local/share/ccp/ccp.sh    # 主脚本
~/.ccp_profiles.json          # 配置文件（首次使用时创建）
~/.zshrc 或 ~/.bashrc         # 注入 shell 函数
```

### 卸载

```bash
# 克隆安装的用户
./uninstall.sh

# 远程安装的用户
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/uninstall.sh | bash

# 重载 shell
source ~/.zshrc

# 可选：删除配置文件
rm ~/.ccp_profiles.json
```

## 使用方法

### 命令列表

| 命令 | 说明 |
|------|------|
| `ccc <profile>` | **切换 profile 并启动 Claude Code** |
| `ccp <profile>` | 切换到指定 profile（设置环境变量） |
| `ccp add <名称>` | 添加/更新 profile（交互式） |
| `ccp remove <名称>` | 删除 profile |
| `ccp list` | 列出所有 profile |
| `ccp status` | 显示当前配置 |
| `ccp init` | 清除 ~/.claude/settings.json 中的 env |
| `ccp edit` | 在编辑器中打开配置文件 |
| `ccp set-env <profile> <变量> <值>` | 设置自定义环境变量 |
| `ccp unset-env <profile> <变量>` | 删除自定义环境变量 |
| `ccp show-env [profile]` | 显示 profile 的环境变量 |
| `ccp help` | 显示帮助 |

### 使用示例

**添加 profile：**
```bash
$ ccp add work
Adding profile: work

Base URL: https://api.example.com/v1
API Key: sk-xxxxxxxxxxxx

Profile 'work' saved
  BASE_URL: https://api.example.com/v1
  API_KEY: [set] sk-x...xxxx
```

**切换并启动：**
```bash
$ ccc work

🚀 Launching Claude Code...
   Profile: work
   Base URL: https://api.example.com/v1
```

**设置自定义环境变量：**
```bash
$ ccp set-env work ANTHROPIC_MODEL claude-sonnet-4
Set ANTHROPIC_MODEL in profile 'work'
```

**在不同终端使用不同 profile：**
```bash
# 终端 1
$ ccc work
# 使用 work profile

# 终端 2
$ ccc personal
# 使用 personal profile（完全独立）
```

## 工作原理

```
ccp.sh 通过 stdout 输出 `export` 语句，通过 stderr 输出状态信息。
shell 函数 `ccp()` 使用 `eval` 将 export 语句应用到当前 shell。
每个终端拥有独立环境 — 无全局状态，无文件冲突。
```

这种架构意味着：
- 切换 profile 只影响当前终端
- 多个终端可同时运行不同 profile
- 无锁文件、无竞态条件、无状态同步问题
- 关闭终端即自动清理（环境变量随 shell 消亡）

## 配置说明

### 配置文件

位置：`~/.ccp_profiles.json`

```json
{
  "current": "work",
  "profiles": {
    "work": {
      "base_url": "https://api.example.com/v1",
      "api_key": "sk-work-xxxxxxxxxxxx",
      "env": {
        "ANTHROPIC_MODEL": "claude-sonnet-4",
        "API_TIMEOUT_MS": "600000"
      }
    },
    "personal": {
      "base_url": "https://api.anthropic.com",
      "api_key": "sk-ant-xxxxxxxxxxxx"
    }
  }
}
```

### 配置字段

| 字段 | 说明 | 必填 |
|------|------|------|
| `base_url` | API 端点 URL | 是 |
| `api_key` | API 认证密钥 | 是 |
| `env` | 自定义环境变量 | 否 |

### 导出的环境变量

切换 profile 时，CCP 会导出：

```bash
ANTHROPIC_BASE_URL    # API 端点
ANTHROPIC_API_URL     # 同 BASE_URL
ANTHROPIC_AUTH_TOKEN  # API key
# 以及 profile 中定义的所有自定义环境变量
```

注意：CCP 会显式 `unset ANTHROPIC_API_KEY` 以避免与 `ANTHROPIC_AUTH_TOKEN` 冲突。

## 安全性

- **API key 脱敏** 显示（`sk-x...xxxx` 格式）
- **配置文件权限** 设为 `600`（仅所有者可读写）
- **环境变量名校验** — 仅允许字母数字和下划线，防止注入
- **导出值 shell 转义** — 防止单引号注入
- **交互式输入不记录历史** — `ccp add` 时 key 不存入 shell history
- **无外部网络调用** — 纯本地操作

漏洞报告请参阅 [SECURITY.md](SECURITY.md)。

## CCP 与其他工具对比

| 功能 | CCP | CCM | CCS |
|------|-----|-----|-----|
| 每 profile 自定义环境变量 | 支持 | 不支持 | 不支持 |
| 终端隔离保证 | 支持 | 写全局配置 | 共享代理状态 |
| 零依赖 | 是 | 是 | 否 (Node.js) |
| 内置 provider 预设 | 否 | 7+ | 17+ |
| 代理/路由功能 | 否 | 否 | 是 |
| Web UI | 否 | 否 | 是 |
| 代码行数 | ~900 | ~400 | ~3000+ |

**选 CCP：** 需要可预测的终端级环境控制、最小化依赖、可审计代码。

**选 CCM：** 需要内置 provider 预设和更简单的功能集。

**选 CCS：** 需要代理层、Web UI，或不介意 Node.js 依赖。

## 常见问题

### Claude Code 不使用我的 profile 配置

运行 `ccp init` 清除 `~/.claude/settings.json` 中的冲突配置：

```bash
ccp init
# 然后重启 Claude Code
ccc work
```

### 环境变量未生效

确保使用 shell 函数（而非直接执行脚本）：

```bash
# 正确（使用 shell 函数）
ccp work

# 错误（在子 shell 中运行，export 丢失）
~/.local/share/ccp/ccp.sh work
```

### 权限被拒绝

```bash
chmod 600 ~/.ccp_profiles.json
```

## 参与贡献

参阅 [CONTRIBUTING.md](CONTRIBUTING.md) 了解贡献指南。

## 相关项目

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — 官方 Claude Code 命令行工具
- [Claude Code Switch (CCM)](https://github.com/foreveryh/claude-code-switch) — 在不同 AI 模型 provider 之间切换
- [Claude Code Switch (CCS)](https://github.com/kaitranntt/ccs) — 功能完整的代理，带 Web UI
- [Claude Code Router](https://github.com/musistudio/claude-code-router) — 请求路由与负载均衡

## 许可证

[MIT License](LICENSE)
