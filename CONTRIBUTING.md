# Contributing to CCC

CCC is a pure Bash CLI for launching Claude Code with isolated settings JSON profiles. It has no build step and runs on Bash 3.2+.

## Development Setup

```bash
git clone https://github.com/WarrenWang798/claude-code-profiles.git
cd claude-code-profiles
```

## Testing

```bash
bash tests/test_ccp.sh
```

## Linting

Use `shellcheck` when available:

```bash
shellcheck -e SC1091 ccc install.sh uninstall.sh
```

## Code Conventions

- Inline comments should be in Chinese.
- Bash 3.2 compatible only.
- No associative arrays (`declare -A`).
- No namerefs (`declare -n`).
- POSIX awk only, no gawk extensions.
- Do not add Python, Node, jq, or runtime services.

## Profile Handling

- Profiles live in `~/.ccc/profiles/*.json`.
- Profiles are complete Claude Code settings JSON files.
- `ccc` must not rewrite profile JSON except during explicit import.
- `ccc` must not write `~/.claude/settings.json`.
- `ccc import-cc-switch` may read `~/.cc-switch/cc-switch.db`, but must not write it.
