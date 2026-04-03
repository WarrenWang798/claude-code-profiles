# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [3.0.0] - 2026-04-03

### Breaking Changes
- Removed `ccp <profile>` shell switching
- New installs no longer inject shell functions or source blocks into rc files

### Added
- `ccc` now validates required `.env` fields before launching Claude Code
- Installer now creates `~/.local/bin/ccp` and `~/.local/bin/ccc` symlinks
- Regression tests for process-local launching, precise `init`, and legacy rc cleanup

### Changed
- `ccp init` now removes only the top-level `env` key from `~/.claude/settings.json`
- `~/.ccp/current` now tracks the last launched profile

### Removed
- `eval`-based profile switching path from `ccp.sh`
- New `ccp-init.sh` generation and rc reinjection from installer

### Migration Notes
- Use `ccc <profile>` to launch Claude Code
- If `~/.local/bin` is not in `PATH`, add it manually
- Legacy rc blocks from older installs are cleaned up by `install.sh` and `uninstall.sh`

## [2.0.0] - 2026-02-28

### Removed
- Python3 dependency — now pure Bash + POSIX awk
- Dead code (`save_profile_with_env` legacy function)

### Security
- Fixed eval injection via env var key validation (`^[A-Za-z_][A-Za-z0-9_]*$`)
- Fixed single-quote escaping in export statements
- API key input now hidden (`read -sp`)

### Fixed
- Env values with spaces no longer silently dropped
- Profile save no longer destroys other profiles

### Added
- Strict mode (`set -euo pipefail`)
- SECURITY.md, CONTRIBUTING.md
- Test suite (`tests/test_ccp.sh`)
- GitHub Actions CI

## [1.1.0] - 2025-01-15

### Added
- Initial release with Python3-based JSON handling
- Profile CRUD operations
- Custom env var support per profile
- Shell integration via install script
