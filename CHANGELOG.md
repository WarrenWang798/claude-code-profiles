# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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