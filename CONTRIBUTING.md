# Contributing to CCP

CCP is a pure Bash CLI for managing multiple Claude Code API configurations. It has zero external dependencies and runs on Bash 3.2+ (macOS default).

## Development Setup

```bash
git clone https://github.com/your-repo/ccp.git
cd ccp
```

That's it. No build step, no npm install, no pip install. Just clone and run.

## Testing

Run the test suite:

```bash
bash tests/test_ccp.sh
```

## Linting

We use shellcheck:

```bash
shellcheck ccp.sh ccc install.sh uninstall.sh
```

## Code Conventions

### Comments

Inline comments should be in Chinese (中文). This is a project convention.

### Bash Compatibility

- Bash 3.2 compatible only
- No associative arrays (`declare -A`)
- No namerefs (`declare -n`)
- POSIX awk only, no gawk extensions

### JSON Operations

All JSON read/write operations go through internal `_json_*` functions. Do not add external JSON tools.

### Security

- Validate env var keys: must match `^[A-Za-z_][A-Za-z0-9_]*$`
- Escape values before export: use `printf '%q'`
- Never print API keys in full: use `mask_token`

## Pull Request Process

1. Fork the repo
2. Create a feature branch (`git checkout -b fix-thing`)
3. Make your changes
4. Run tests and linting
5. Open a pull request

## What We're Looking For

- Bug fixes
- Security improvements
- Compatibility fixes for other shells/OSes
- Documentation improvements

## What We're NOT Looking For

- New external dependencies (jq, python, node, etc.)
- Rewrites in other languages
- Feature creep outside the core scope