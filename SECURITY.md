# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| v2.0.x  | :white_check_mark: |
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
- **Shell-escaped exports** — Values are properly quoted before eval
- **Config file permissions** — `~/.ccp_profiles.json` set to mode 600
- **No secrets in history** — API key input uses `read -sp` (hidden)
- **Strict mode** — `set -euo pipefail` catches errors early