# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| v3.0.x  | :white_check_mark: |
| v2.0.x  | :x:                |
| v1.x    | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in CCP, please open a private GitHub security advisory or a regular GitHub issue with the title prefixed `[SECURITY]`.

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

We aim to acknowledge reports within 72 hours and provide a fix or mitigation within 7 days for confirmed vulnerabilities.

## Security Design Principles

CCP follows these principles to minimize attack surface:

- **No external dependencies** — Pure Bash + POSIX awk only
- **Env var key validation** — Keys must match `^[A-Za-z_][A-Za-z0-9_]*$`
- **Process-local launches only** — `ccc` injects env into the spawned `claude` process with `exec env`; it does not mutate the caller shell
- **Config file permissions** — Profile `.env` files and `~/.ccp/current` are written with mode 600
- **Narrow settings rewrite** — `ccp init` removes only the top-level `env` key from `~/.claude/settings.json`
- **No secrets in history** — API key input uses `read -sp` (hidden)
- **Strict mode** — `set -euo pipefail` catches errors early
