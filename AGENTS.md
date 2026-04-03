# PROJECT KNOWLEDGE BASE

**Generated:** 2026-04-03
**Version:** 3.0.0
**Branch:** codex/review-glisteningsleepingbachmanmd

## OVERVIEW

Claude Code Profile Switcher (CCP) — pure Bash + POSIX awk CLI for managing Claude Code API profiles (`base_url`, `auth_token`, custom env vars). Zero external dependencies. `ccp` is management-only; `ccc` launches Claude Code with one profile in a child process.

## STRUCTURE

```
./
├── ccp.sh                        # Profile CRUD, status, init, top-level env removal from settings.json
├── ccc                           # Launcher: reads .env, validates required vars, exec env ... claude
├── install.sh                    # Installs scripts, cleans legacy rc blocks, creates ~/.local/bin symlinks
├── uninstall.sh                  # Removes install dir/symlinks, cleans legacy rc blocks
├── README.md                     # English docs
├── README_CN.md                  # Chinese docs
├── CHANGELOG.md                  # Version history
├── SECURITY.md                   # Security policy + design principles
├── CONTRIBUTING.md               # Contribution guidelines
├── LICENSE                       # MIT
├── .gitignore
└── tests/
    └── test_ccp.sh               # Shell regression suite for launcher/init/install flows
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| Launch Claude Code with one profile | `ccc` | Reads `~/.ccp/profiles/<profile>.env`, validates required vars, updates `~/.ccp/current`, then `exec env ... claude` |
| Add/remove/list profiles | `ccp.sh` | CRUD commands operate directly on `.env` files |
| Custom env vars per profile | `ccp.sh` | `set-env`, `unset-env`, `show-env` |
| Current profile metadata | `ccp.sh` + `ccc` | `~/.ccp/current` stores the last launched profile |
| Clear conflicting Claude settings | `ccp.sh` → `cmd_init` | Removes only the top-level `env` key from `~/.claude/settings.json` |
| Legacy shell cleanup on install | `install.sh` | Removes old rc blocks but does not inject new ones |
| Uninstall cleanup | `uninstall.sh` | Removes symlinks/install dir and legacy rc blocks |
| Tests | `tests/test_ccp.sh` | Covers launcher validation, init rewriting, install migration |

## CONVENTIONS

- **Bilingual comments**: Inline comments stay in Chinese (中文). README has EN + CN versions.
- **Pure Bash + POSIX awk only**: No Python, no jq, no gawk-only features.
- **Bash 3.2 compatibility**: No associative arrays (`declare -A`), no namerefs (`declare -n`).
- **Profile storage**: Profiles live in `~/.ccp/profiles/*.env`.
- **Launcher behavior**: `ccc` never uses `eval`; it injects env only into the spawned `claude` process.
- **Current pointer semantics**: `~/.ccp/current` means "last launched profile", not "current shell profile".
- **Atomic writes**: `current` and rewritten settings files use temp-file + `mv`.
- **Security at boundaries**: Env var keys must match `^[A-Za-z_][A-Za-z0-9_]*$`.
- **Auth variable policy**: Use `ANTHROPIC_AUTH_TOKEN`; explicitly unset `ANTHROPIC_API_KEY` when launching.

## ANTI-PATTERNS (THIS PROJECT)

- **NEVER use Python3, jq, or any external dependency**.
- **NEVER reintroduce `eval "$(ccp <profile>)"` or any equivalent shell-switch flow**.
- **NEVER set `ANTHROPIC_API_KEY`** — use `ANTHROPIC_AUTH_TOKEN` only.
- **NEVER use `declare -A`** — breaks Bash 3.2 on macOS.
- **NEVER use `declare -n`** — breaks Bash 3.2 on macOS.
- **NEVER store config in the repo** — profile data stays under `$HOME/.ccp`.
- **NEVER print API keys in full** — mask them in user-facing output.
- **NEVER inject new rc blocks in install scripts** — only clean up legacy blocks.
- **NEVER accept env var keys without validation** — prevents command injection.

## UNIQUE STYLES

- `ccc` uses `exec env ... claude` so the launcher process is replaced by Claude Code.
- `cmd_init` is intentionally narrow: it deletes only the top-level `env` key from `settings.json`.
- Install/uninstall still understand legacy marker blocks for migration, but 3.0 no longer writes new rc content.

## COMMANDS

```bash
# Install
./install.sh
export PATH="$HOME/.local/bin:$PATH"

# Test
bash tests/test_ccp.sh

# Lint
shellcheck -e SC1091 ccp.sh ccc install.sh uninstall.sh

# Usage
ccp add <name>          # Interactive profile creation
ccp list                # List profiles
ccp status              # Show current config and last launched profile
ccc <profile>           # Launch Claude Code with profile
ccp set-env <p> K V     # Set custom env var
```

## NOTES

- `ccp init` backs up `~/.claude/settings.json` and removes only the top-level `env` key.
- `ccc env <profile>` is kept as a compatibility alias for `ccc <profile>`.
- API key input is hidden (`read -sp`) during `ccp add`.
- All managed writes are atomic to reduce corruption risk.
