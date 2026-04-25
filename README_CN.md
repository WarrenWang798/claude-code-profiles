# Claude Code Commander (CCC)

> 使用独立 settings JSON profile 启动 Claude Code。`ccc` 不会修改 `~/.claude/settings.json`。

## 为什么需要 CCC

`ccc` 是一个很小的 Bash 启动器，用指定 settings 文件运行 Claude Code：

```bash
ccc work --resume abc123
```

它会把 `work` 解析为：

```text
~/.ccc/profiles/work.json
```

然后启动：

```bash
claude --setting-sources "" --settings ~/.ccc/profiles/work.json --resume abc123
```

直接运行 `claude` 仍然使用你原来的 Claude 配置。

## 快速开始

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"

# 如果你使用 CC Switch，可以导入 Claude providers
ccc import-cc-switch

# 查看 profiles
ccc list

# 使用某个 profile 启动 Claude Code
ccc work-one
```

## 使用方式

### 1. 从 CC Switch 导入

如果你已经在 CC Switch 里维护 Claude providers：

```bash
ccc import-cc-switch
```

它会读取：

```text
~/.cc-switch/cc-switch.db
```

并生成独立的 CCC profiles：

```text
~/.ccc/profiles/*.json
```

只导入 CC Switch 当前 Claude provider：

```bash
ccc import-cc-switch --current
```

导入是一次性复制，不会修改 CC Switch，也不会和 CC Switch 保持实时同步。
重复执行导入会覆盖同名 CCC profile，不会继续生成 `-2` / `-3` 副本。导入写入的 JSON 会格式化，便于直接阅读。

### 2. 查看 Profiles

```bash
ccc list
ccc show work-one
ccc path work-one
```

`show` 只显示元信息，不打印 token。

### 3. 启动 Claude Code

```bash
ccc work-one
ccc work-one --resume <session-id>
ccc work-one --dangerously-skip-permissions
```

`ccc work-one` 实际启动：

```bash
claude --setting-sources "" --settings ~/.ccc/profiles/work-one.json
```

profile 名后面的参数会原样透传给 Claude Code。

### 4. 手动创建 Profile

创建一个完整 Claude settings JSON 文件：

```bash
mkdir -p ~/.ccc/profiles
cat > ~/.ccc/profiles/work.json <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.example.com/v1",
    "ANTHROPIC_AUTH_TOKEN": "sk-xxxxx",
    "ANTHROPIC_MODEL": "claude-sonnet-4"
  },
  "includeCoAuthoredBy": false
}
JSON
chmod 600 ~/.ccc/profiles/work.json
```

然后启动：

```bash
ccc work
```

### 5. 验证隔离

在执行 `ccc <profile>` 前后查看：

```bash
cat ~/.claude/settings.json
```

该文件不应该变化。CCC 只在拉起的 Claude 子进程里通过 `--settings` 使用 profile，并通过 `--setting-sources ""` 禁用默认 Claude settings 来源。

## Profile 格式

Profile 是完整的 Claude Code settings JSON：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.example.com/v1",
    "ANTHROPIC_AUTH_TOKEN": "sk-xxxxx",
    "ANTHROPIC_MODEL": "claude-sonnet-4"
  },
  "includeCoAuthoredBy": false,
  "model": "sonnet"
}
```

CCC 会把整个文件传给 Claude Code，不编辑、不裁剪、不转换 settings 内容。

不要把 CCC 当成 JSON 编辑器使用。请直接编辑 profile 文件，或者从 CC Switch 导入。

## 命令

| 命令 | 说明 |
|------|------|
| `ccc <profile> [args...]` | 使用 profile 启动 Claude Code |
| `ccc list` | 列出 `~/.ccc/profiles` 下的 profiles |
| `ccc show <profile>` | 显示 profile 元信息，不打印密钥 |
| `ccc path <profile>` | 输出 profile 文件路径 |
| `ccc import-cc-switch` | 从 CC Switch 导入全部 Claude providers |
| `ccc import-cc-switch --current` | 只导入 CC Switch 当前 Claude provider |

已经没有 `ccp` 命令。

## 存储位置

```text
~/.ccc/
├── profiles/
│   ├── work-one.json
│   └── kimi.json
└── current
```

CC Switch 导入读取：

```text
~/.cc-switch/cc-switch.db
```

它会把 `app_type='claude'` 的 `providers.settings_config` 复制成 CCC profile JSON 文件。不会修改 CC Switch 数据库。
重复导入对同名 profile 是幂等刷新，会更新已有 JSON 文件。

## 安装

```bash
./install.sh
```

安装内容：

```text
~/.local/share/ccc/ccc
~/.local/bin/ccc
```

卸载：

```bash
./uninstall.sh
```

配置会保留在 `~/.ccc`，如不需要可手动删除。

## 边界保证

- `ccc` 不修改 `~/.claude/settings.json`。
- `ccc` 不修改 `~/.cc-switch/cc-switch.db`。
- `ccc` 启动 Claude Code 时带 `--setting-sources ""`，避免默认 user/project/local settings 泄漏到 profile 运行。
- `ccc` 会在启动子进程时清理外部 `ANTHROPIC_API_KEY`，避免 shell 环境污染。
- 如果 profile JSON 内有 `env.ANTHROPIC_API_KEY`，Claude Code 仍会通过 `--settings` 读取到。
- `ccc` 不依赖 Python、Node、jq。CC Switch 导入需要系统有 `sqlite3` 命令。
