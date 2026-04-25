# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| v3.0.x  | :white_check_mark: |
| v2.0.x  | :x:                |
| v1.x    | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in CCC, please open a private GitHub security advisory or a regular GitHub issue with the title prefixed `[SECURITY]`.

## Security Design Principles

CCC follows these principles to minimize attack surface:

- **No default settings mutation** — CCC never writes `~/.claude/settings.json`.
- **No CC Switch mutation** — import reads `~/.cc-switch/cc-switch.db` and writes only CCC profiles.
- **Process-local launch** — `ccc` launches `claude --setting-sources "" --settings <profile.json>` for one process.
- **No default source leakage** — default user/project/local settings are disabled for the spawned Claude process.
- **Config file permissions** — imported profile files and `~/.ccc/current` are written with mode 600.
- **No broad dependencies** — pure Bash + POSIX awk; only `import-cc-switch` requires `sqlite3`.
- **No secrets in status output** — `show` prints metadata only, not profile JSON contents.
