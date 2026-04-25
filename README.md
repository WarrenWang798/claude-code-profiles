# Claude Code Commander (CCC)

> Launch Claude Code with isolated, per-profile settings JSON. `ccc` never mutates `~/.claude/settings.json`.

## Why CCC

`ccc` is a small Bash launcher for running Claude Code with a specific settings file:

```bash
ccc work --resume abc123
```

It resolves `work` to:

```text
~/.ccc/profiles/work.json
```

Then starts Claude Code with:

```bash
claude --setting-sources "" --settings ~/.ccc/profiles/work.json --resume abc123
```

Direct `claude` launches continue to use your normal Claude configuration.

## Quick Start

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"

# Import Claude providers from CC Switch, if you use it
ccc import-cc-switch

# List available profiles
ccc list

# Launch Claude Code with one profile
ccc work-one
```

## How to Use

### 1. Import from CC Switch

If you already maintain Claude providers in CC Switch:

```bash
ccc import-cc-switch
```

This reads:

```text
~/.cc-switch/cc-switch.db
```

and writes independent CCC profiles:

```text
~/.ccc/profiles/*.json
```

Import only the current CC Switch Claude provider:

```bash
ccc import-cc-switch --current
```

The import is a one-time copy. It does not modify CC Switch and it does not keep live sync.

### 2. Check Profiles

```bash
ccc list
ccc show work-one
ccc path work-one
```

`show` prints metadata only. It does not print token values.

### 3. Launch Claude Code

```bash
ccc work-one
ccc work-one --resume <session-id>
ccc work-one --dangerously-skip-permissions
```

`ccc work-one` launches:

```bash
claude --setting-sources "" --settings ~/.ccc/profiles/work-one.json
```

Any arguments after the profile name are passed through to Claude Code.

### 4. Create a Profile Manually

Create a complete Claude settings JSON file:

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

Then launch:

```bash
ccc work
```

### 5. Verify Isolation

Run this before and after `ccc <profile>`:

```bash
cat ~/.claude/settings.json
```

The file should not change. CCC passes the profile with `--settings` and disables default Claude setting sources with `--setting-sources ""` for the spawned Claude process.

## Profile Format

Profiles are complete Claude Code settings JSON files:

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

CCC passes the whole file to Claude Code. It does not edit or normalize the settings content.

Do not use CCC as a JSON editor. Edit profile files directly or import them from CC Switch.

## Commands

| Command | Description |
|---------|-------------|
| `ccc <profile> [args...]` | Launch Claude Code with a profile |
| `ccc list` | List profiles under `~/.ccc/profiles` |
| `ccc show <profile>` | Show profile metadata without printing secrets |
| `ccc path <profile>` | Print the profile file path |
| `ccc import-cc-switch` | Import all Claude providers from CC Switch |
| `ccc import-cc-switch --current` | Import only the current CC Switch Claude provider |

There is no `ccp` command anymore.

## Storage

```text
~/.ccc/
├── profiles/
│   ├── work-one.json
│   └── kimi.json
└── current
```

CC Switch import reads:

```text
~/.cc-switch/cc-switch.db
```

It copies `providers.settings_config` where `app_type='claude'` into CCC profile JSON files. It does not modify the CC Switch database.

## Install

```bash
./install.sh
```

Installed files:

```text
~/.local/share/ccc/ccc
~/.local/bin/ccc
```

Uninstall:

```bash
./uninstall.sh
```

Configuration is preserved at `~/.ccc`; remove it manually if needed.

## Guarantees

- `ccc` does not modify `~/.claude/settings.json`.
- `ccc` does not modify `~/.cc-switch/cc-switch.db`.
- `ccc` launches Claude Code with `--setting-sources ""` so default user/project/local settings do not leak into the profile run.
- `ccc` unsets external `ANTHROPIC_API_KEY` for the launched process to avoid shell leakage.
- If a profile JSON contains `env.ANTHROPIC_API_KEY`, Claude Code still receives it via `--settings`.
- `ccc` uses no Python, Node, or jq. CC Switch import requires the system `sqlite3` command.
