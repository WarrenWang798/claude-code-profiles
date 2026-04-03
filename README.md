# Claude Code Profile Switcher (CCP) 3.0

> Pure Bash profile management for Claude Code. **.env file based**, zero dependencies, terminal-native isolation.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/WarrenWang798/claude-code-profiles)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-purple.svg)](https://claude.ai/code)

[English](README.md) | [中文文档](README_CN.md)

---

## What's New in 3.0

- `ccc` now reads profile `.env` files directly and launches `claude` with process-local env
- `ccp <profile>` shell switching is removed
- `ccp init` now removes only the top-level `env` key from `~/.claude/settings.json`
- Install no longer injects new rc blocks; it creates `~/.local/bin/ccp` and `~/.local/bin/ccc`

---

## Why CCP?

Other tools manage API endpoints. **CCP manages Claude Code launch environments without mutating your current shell.**

**Per-profile env bundles** — Each profile carries arbitrary custom env vars (MODEL, TIMEOUT, FEATURE_FLAGS). Set `ANTHROPIC_MODEL=claude-sonnet-4` for work and `ANTHROPIC_MODEL=claude-opus-4` for personal.

**Process-local isolation** — `ccc` reads one profile and starts one `claude` process with `exec env ...`. No `eval`, no shell pollution, no accidental cross-talk between sessions.

**Truly zero dependencies** — Pure Bash 3.2. No Python, no Node, no jq. Works on stock macOS out of the box.

**Auditable simplicity** — For security-conscious developers managing API keys: one file format, no external calls, readable source. Know exactly what runs when you launch Claude Code with a profile.

---

## Quick Start

```bash
# One-line install (recommended)
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash

# Make sure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

# Initialize (one-time, removes only the conflicting top-level `env` key)
ccp init

# Add your first profile
ccp add work

# Launch Claude Code with profile
ccc work
```

---

## New .env Format

CCP 3.0 uses simple `.env` files instead of JSON:

```bash
# ~/.ccp/profiles/work.env
# CCP Profile: work
ANTHROPIC_BASE_URL=https://api.example.com/v1
ANTHROPIC_AUTH_TOKEN=sk-xxxxx
# Custom env vars
ANTHROPIC_MODEL=claude-sonnet-4
API_TIMEOUT_MS=600000
```

**Benefits:**
- ✏️ Human-readable and editable
- 🔍 Easy to debug
- 📋 Easy to copy/share
- 🛡️ No JSON parsing complexity

---

## Commands

| Command | Description |
|---------|-------------|
| `ccc <profile>` | **Launch Claude Code with a profile** |
| `ccc env <profile>` | Compatibility alias for `ccc <profile>` |
| `ccp add <name>` | Add/update profile (interactive) |
| `ccp remove <name>` | Remove a profile |
| `ccp list` | List all profiles |
| `ccp status` | Show current configuration and last launched profile |
| `ccp set-env <profile> <VAR> <value>` | Set custom env var |
| `ccp unset-env <profile> <VAR>` | Remove custom env var |
| `ccp show-env <profile>` | Show all env vars for profile |
| `ccp init` | Initialize Claude Code settings |
| `ccp help` | Show help |

---

## Configuration Location

```
~/.ccp/
├── profiles/
│   ├── work.env          # Profile definitions
│   ├── personal.env
│   └── ...
└── current               # Last launched profile name
```

---

## Migration from CCP 2.x

CCP 3.0 changes how launching works:

- `ccp <profile>` is removed
- `ccc <profile>` is now the only launcher
- new installs do not inject shell functions into rc files

Existing legacy rc blocks are cleaned up automatically by `install.sh` and `uninstall.sh`.

---

## Migration from CCP 1.x

CCP 3.0 is **not backward compatible** with 1.x profiles. You need to recreate your profiles:

```bash
# Old profiles were in ~/.ccp_profiles.json
# New profiles are in ~/.ccp/profiles/*.env

# 1. Backup old config
cp ~/.ccp_profiles.json ~/.ccp_profiles.json.backup

# 2. Re-create profiles
ccp add work
ccp add personal

# 3. Done! Remove old config if desired
rm ~/.ccp_profiles.json
```

---

## Installation

### Requirements

- Bash 3.2+ (macOS default) or Zsh
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed

### Install

```bash
# One-line install (no git clone needed)
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/WarrenWang798/claude-code-profiles.git
cd claude-code-profiles
./install.sh
```

Then make sure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### What Gets Installed

```
~/.local/share/ccp/ccp.sh    # Main script
~/.local/share/ccp/ccc       # Launcher script
~/.local/bin/ccp            # Symlink to main script
~/.local/bin/ccc            # Symlink to launcher
~/.ccp/profiles/              # Profile .env files (created on first use)
```

### Uninstall

```bash
# If installed via git clone
./uninstall.sh

# If installed via curl (download uninstall script)
curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/uninstall.sh | bash

# Optional: remove config
rm -rf ~/.ccp
```

---

## How It Works

```
`ccp` manages profile files under `~/.ccp/profiles`.
`ccc` reads one `.env` file, validates required variables, updates `~/.ccp/current`, and starts `claude` with `exec env`.
Only the launched `claude` process receives the profile environment.
```

This architecture means:
- Launching a profile only affects the spawned `claude` process
- Multiple terminals can run different profiles simultaneously
- No lock files, no race conditions, no state sync issues
- No `eval` or shell-function dependency

---

## CCP vs Alternatives

| Feature | CCP 3.0 | CCM | CCS |
|---------|---------|-----|-----|
| Storage format | **.env files** | JSON | JSON |
| Custom env vars per profile | **Yes** | No | No |
| Terminal isolation guarantee | **Yes** | Writes global config | Shared proxy state |
| Zero dependencies | **Yes** | Yes | No (Node.js) |
| Built-in provider presets | No | 7+ | 17+ |
| Proxy/routing features | No | No | Yes |
| Web UI | No | No | Yes |
**Choose CCP if:** You want predictable per-process Claude Code launches, minimal footprint, auditable code, and .env file simplicity.

**Choose CCM if:** You need built-in provider presets and a simpler feature set.

**Choose CCS if:** You want a proxy layer, Web UI, or don't mind Node.js dependencies.

---

## Troubleshooting

### Claude Code ignores my profile settings

Run `ccp init` to clear conflicting settings from `~/.claude/settings.json`:

```bash
ccp init
# Then restart Claude Code
ccc work
```

### Environment variables not applied

Use `ccc`, not `ccp`, to launch Claude Code with a profile:

```bash
# Correct
ccc work

# Wrong: `ccp` is now management-only
ccp work
```

### Permission denied

```bash
chmod 600 ~/.ccp/profiles/*.env
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Related Projects

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — Official Claude Code command-line tool
- [Claude Code Switch (CCM)](https://github.com/foreveryh/claude-code-switch) — Switch between different AI model providers
- [Claude Code Switch (CCS)](https://github.com/kaitranntt/ccs) — Full-featured proxy with Web UI
- [Claude Code Router](https://github.com/musistudio/claude-code-router) — Request routing and load balancing

---

## License

[MIT License](LICENSE)
