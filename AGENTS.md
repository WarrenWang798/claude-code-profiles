# PROJECT KNOWLEDGE BASE

**Generated:** 2026-02-28
**Version:** 2.0.0
**Branch:** (no git repo initialized)

## OVERVIEW

Claude Code Profile Switcher (CCP) — pure Bash + POSIX awk CLI for managing multiple Claude Code API configurations (base_url + api_key + custom env vars). Zero external dependencies. Switch profiles with `ccp`, launch Claude Code with `ccc`.

## STRUCTURE

```
./
├── ccp.sh                        # Core logic: JSON engine + profile CRUD + switching (~1190 lines)
├── ccc                           # Launcher: switches profile then `exec claude` (63 lines)
├── install.sh                    # Installs ccp.sh to ~/.local/share/ccp/, injects shell functions
├── uninstall.sh                  # Reverses install.sh — removes script + rc block
├── README.md                     # English docs
├── README_CN.md                  # Chinese docs
├── CHANGELOG.md                  # Version history
├── SECURITY.md                   # Security policy + design principles
├── CONTRIBUTING.md               # Contribution guidelines
├── LICENSE                       # MIT
├── .gitignore
├── tests/
│   └── test_ccp.sh              # Test suite (26 tests)
└── .github/
    └── workflows/
        └── ci.yml               # Shellcheck + tests on Linux/macOS
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| JSON read/write engine | `ccp.sh` → `_json_core()` | Single awk script handles all JSON ops |
| Atomic file writes | `ccp.sh` → `_atomic_write()` | Temp file + mv pattern |
| Security validators | `ccp.sh` → `_is_valid_env_key()`, `_shell_quote()` | Used at all export boundaries |
| Add/remove/list profiles | `ccp.sh` → `add_profile`, `remove_profile`, `list_profiles` | Interactive prompts in `add_profile` |
| Switch profile (env export) | `ccp.sh` → `switch_profile` | Outputs `export` statements to stdout, status to stderr |
| Custom env vars per profile | `ccp.sh` → `set_env_var`, `unset_env_var`, `show_env_vars` | Pure awk, no external deps |
| Launch Claude Code | `ccc` | Calls `ccp.sh` via `eval`, then `exec claude` |
| Shell integration | `install.sh` → `append_function_block` | Injected between `>>> ccp function begin >>>` markers |
| Clear conflicting settings | `ccp.sh` → `init_claude_env` | Removes `env` key from `~/.claude/settings.json` |
| Tests | `tests/test_ccp.sh` | 26 tests: CRUD, security, round-trip, init |

## CONVENTIONS

- **Bilingual comments**: All inline comments in Chinese (中文). README has EN + CN versions.
- **Pure awk JSON engine**: `_json_core()` is a single awk script that handles both reads and writes for CCP's fixed schema. No Python, no jq.
- **Bash 3.2 compatibility**: No associative arrays (`declare -A`), no namerefs (`declare -n`). Uses indexed arrays only.
- **POSIX awk only**: No gawk extensions. Must work with macOS default `/usr/bin/awk`.
- **Profile switch via stdout**: `switch_profile` prints `export` statements to stdout, human-readable messages to stderr. Caller uses `eval "$(ccp <profile>)"`.
- **Atomic writes**: All JSON mutations use temp file + `mv` for crash safety.
- **Security at boundaries**: Env var keys validated with `_is_valid_env_key()`, values escaped with `_shell_quote()` before export generation.
- **Config location**: `~/.ccp_profiles.json` (600 perms). NOT in repo.
- **Env vars exported**: `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_URL`, `ANTHROPIC_AUTH_TOKEN`. Explicitly `unset ANTHROPIC_API_KEY`.

## ANTI-PATTERNS (THIS PROJECT)

- **NEVER use Python3, jq, or any external dependency** — pure Bash + POSIX awk only.
- **NEVER set `ANTHROPIC_API_KEY`** — use `ANTHROPIC_AUTH_TOKEN` only. API_KEY is explicitly unset.
- **NEVER use `declare -A`** (associative arrays) — breaks Bash 3.2 on macOS.
- **NEVER use `declare -n`** (namerefs) — breaks Bash 3.2 on macOS.
- **NEVER store config in the repo** — `~/.ccp_profiles.json` lives in `$HOME`, contains secrets.
- **NEVER print API keys in full** — always use `mask_token` (shows first 4 + last 4 chars).
- **NEVER generate export statements without `_shell_quote()`** — prevents eval injection.
- **NEVER accept env var keys without `_is_valid_env_key()`** — prevents command injection.

## UNIQUE STYLES

- Single awk script (`_json_core`) handles all JSON operations for a fixed schema — reads and writes.
- `ccc` uses `exec claude` to replace the shell process (not a subprocess).
- Install/uninstall use awk-based marker blocks for clean rc file management.
- `_json_save_profile_with_env` receives array data via a temp file (NUL-safe transport for arbitrary values).

## COMMANDS

```bash
# No build step. Pure bash scripts.

# Install
./install.sh
source ~/.zshrc

# Test
bash tests/test_ccp.sh

# Lint
shellcheck -e SC1091 ccp.sh ccc install.sh uninstall.sh

# Usage
ccp add <name>          # Interactive profile creation
ccp list                # List profiles
ccp status              # Show current config
ccc <profile>           # Switch + launch Claude Code
ccp set-env <p> K V     # Set custom env var
```

## NOTES

- `ccp init` clears `env` from `~/.claude/settings.json` — needed because Claude Code's settings.json can override shell env vars.
- The `ccc` standalone script and the shell function `ccc()` do the same thing. Shell function is preferred.
- Editor detection order in `edit_config`: cursor → code → open (macOS) → vim → nano.
- API key input is hidden (`read -sp`) during `ccp add`.
- All writes are atomic (temp file + mv) to prevent corruption from concurrent access.
