# Claude Code Profile Switcher (CCP)

> Pure Bash profile management for Claude Code. Zero dependencies, terminal-native isolation.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/user/claude-code-profiles)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-purple.svg)](https://claude.ai/code)

[English](README.md) | [中文文档](README_CN.md)

## Why CCP?

Other tools manage API endpoints. CCP manages your entire terminal environment.

**Per-profile env bundles** — Each profile carries arbitrary custom env vars (MODEL, TIMEOUT, FEATURE_FLAGS). Set `ANTHROPIC_MODEL=claude-sonnet-4` for work, `ANTHROPIC_MODEL=claude-opus-4` for personal. The only CLI tool that does this.

**Terminal-native isolation** — Pure env var exports via `stdout`, status messages via `stderr`. Each terminal gets its own environment. No global config pollution, no accidental cross-talk between sessions. Unlike CCM's `ccm user` which writes to `~/.claude/settings.json`.

**Truly zero dependencies** — Pure Bash 3.2. No Python, no Node, no jq. Works on stock macOS out of the box. Single ~900 line script you can audit in 15 minutes.

**Auditable simplicity** — For security-conscious developers managing API keys: one file, no external calls, readable source. Know exactly what runs when you switch profiles.

CCP is for developers who want predictable env control, not provider abstraction.

## Quick Start

```bash
# One-line install (recommended)
curl -fsSL https://raw.githubusercontent.com/user/claude-code-profiles/main/install.sh | bash
source ~/.zshrc  # or ~/.bashrc

# Initialize (one-time, clears conflicting settings)
ccp init

# Add your first profile
ccp add work

# Launch Claude Code with profile
ccc work
```

## Features

| Feature | Description |
|---------|-------------|
| **Multi-Profile** | Store unlimited API configurations |
| **Quick Switch** | One command to switch profiles |
| **One-Command Launch** | `ccc <profile>` switches and launches Claude Code |
| **Custom Env Vars** | Set any environment variable per profile |
| **Terminal Isolation** | Different terminals can use different profiles simultaneously |
| **Zero Dependencies** | Pure Bash 3.2, no Python/Node/jq required |
| **Secure Storage** | API keys masked in all output |

## Installation

### Requirements

- Bash 3.2+ (macOS default) or Zsh
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed

### Install

```bash
# One-line install (no git clone needed)
curl -fsSL https://raw.githubusercontent.com/user/claude-code-profiles/main/install.sh | bash
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/user/claude-code-profiles/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/user/claude-code-profiles.git
cd claude-code-profiles
./install.sh
```

Then reload your shell:

```bash
source ~/.zshrc  # or ~/.bashrc
```

### What Gets Installed

```
~/.local/share/ccp/ccp.sh    # Main script
~/.ccp_profiles.json          # Config file (created on first use)
~/.zshrc or ~/.bashrc        # Shell functions injected
```

### Uninstall

```bash
# If installed via git clone
./uninstall.sh

# If installed via curl (download uninstall script)
curl -fsSL https://raw.githubusercontent.com/user/claude-code-profiles/main/uninstall.sh | bash

# Then reload shell
source ~/.zshrc

# Optional: remove config
rm ~/.ccp_profiles.json
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `ccc <profile>` | **Switch profile and launch Claude Code** |
| `ccp <profile>` | Switch to profile (sets env vars) |
| `ccp add <name>` | Add/update profile (interactive) |
| `ccp remove <name>` | Remove a profile |
| `ccp list` | List all profiles |
| `ccp status` | Show current configuration |
| `ccp init` | Clear env from ~/.claude/settings.json |
| `ccp edit` | Open config in editor |
| `ccp set-env <profile> <VAR> <value>` | Set custom env var |
| `ccp unset-env <profile> <VAR>` | Remove custom env var |
| `ccp show-env [profile]` | Show profile's env vars |
| `ccp help` | Show help |

### Examples

**Add a profile:**
```bash
$ ccp add work
Adding profile: work

Base URL: https://api.example.com/v1
API Key: sk-xxxxxxxxxxxx

Profile 'work' saved
  BASE_URL: https://api.example.com/v1
  API_KEY: [set] sk-x...xxxx
```

**Switch and launch:**
```bash
$ ccc work

🚀 Launching Claude Code...
   Profile: work
   Base URL: https://api.example.com/v1
```

**Set custom environment variable:**
```bash
$ ccp set-env work ANTHROPIC_MODEL claude-sonnet-4
Set ANTHROPIC_MODEL in profile 'work'
```

**Use different profiles in different terminals:**
```bash
# Terminal 1
$ ccc work
# Uses work profile

# Terminal 2
$ ccc personal
# Uses personal profile (completely independent)
```

## How It Works

```
ccp.sh outputs `export` statements to stdout and status messages to stderr.
The shell function `ccp()` uses `eval` to apply exports to the current shell.
Each terminal gets its own environment — no global state, no file conflicts.
```

This architecture means:
- Switching a profile only affects the current terminal
- Multiple terminals can run different profiles simultaneously
- No lock files, no race conditions, no state sync issues
- Closing a terminal cleans up automatically (env vars die with the shell)

## Configuration

### Config File

Location: `~/.ccp_profiles.json`

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

### Profile Fields

| Field | Description | Required |
|-------|-------------|----------|
| `base_url` | API endpoint URL | Yes |
| `api_key` | API authentication key | Yes |
| `env` | Custom environment variables | No |

### Environment Variables Set

When switching profiles, CCP exports:

```bash
ANTHROPIC_BASE_URL    # API endpoint
ANTHROPIC_API_URL     # Same as BASE_URL
ANTHROPIC_AUTH_TOKEN  # API key
# Plus any custom env vars defined in profile
```

Note: CCP explicitly unsets `ANTHROPIC_API_KEY` to avoid conflicts with `ANTHROPIC_AUTH_TOKEN`.

## Security

- **API keys masked** in all output (`sk-x...xxxx` format)
- **Config file permissions** set to `600` (owner read/write only)
- **Env var keys validated** — alphanumeric + underscore only, no injection
- **Export values shell-escaped** — single-quote injection safe
- **No keys in shell history** when using interactive `ccp add`
- **No external network calls** — pure local operations

For vulnerability reports, see [SECURITY.md](SECURITY.md).

## CCP vs Alternatives

| Feature | CCP | CCM | CCS |
|---------|-----|-----|-----|
| Custom env vars per profile | Yes | No | No |
| Terminal isolation guarantee | Yes | Writes global config | Shared proxy state |
| Zero dependencies | Yes | Yes | No (Node.js) |
| Built-in provider presets | No | 7+ | 17+ |
| Proxy/routing features | No | No | Yes |
| Web UI | No | No | Yes |
| Lines of code | ~900 | ~400 | ~3000+ |

**Choose CCP if:** You want predictable per-terminal env control, minimal footprint, and auditable code.

**Choose CCM if:** You need built-in provider presets and a simpler feature set.

**Choose CCS if:** You want a proxy layer, Web UI, or don't mind Node.js dependencies.

## Troubleshooting

### Claude Code ignores my profile settings

Run `ccp init` to clear conflicting settings from `~/.claude/settings.json`:

```bash
ccp init
# Then restart Claude Code
ccc work
```

### Environment variables not applied

Make sure to use the shell function (not direct script execution):

```bash
# Correct (uses shell function)
ccp work

# Wrong (runs in subshell, exports lost)
~/.local/share/ccp/ccp.sh work
```

### Permission denied

```bash
chmod 600 ~/.ccp_profiles.json
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Related Projects

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — Official Claude Code command-line tool
- [Claude Code Switch (CCM)](https://github.com/foreveryh/claude-code-switch) — Switch between different AI model providers
- [Claude Code Switch (CCS)](https://github.com/kaitranntt/ccs) — Full-featured proxy with Web UI
- [Claude Code Router](https://github.com/musistudio/claude-code-router) — Request routing and load balancing

## License

[MIT License](LICENSE)