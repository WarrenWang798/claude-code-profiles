# Changelog

All notable changes to this project will be documented in this file.

## [3.0.0] - 2026-04-03

### Breaking Changes
- Removed `ccp` command surface.
- Replaced env-bundle management with complete Claude settings JSON profiles.
- Profile storage moved to `~/.ccc/profiles/*.json`.

### Added
- `ccc <profile>` launches Claude Code with `--setting-sources "" --settings ~/.ccc/profiles/<profile>.json`.
- `ccc list`, `ccc show`, and `ccc path` profile inspection commands.
- `ccc import-cc-switch` and `ccc import-cc-switch --current` for one-shot CC Switch import.
- Regression tests for complete settings pass-through, default settings preservation, and CC Switch import.

### Removed
- `ccp.sh`, `ccp add`, `ccp set-env`, `ccp unset-env`, `ccp show-env`, and `ccp init`.
- `.env` profile storage.
- Installer creation of `~/.local/bin/ccp`.

### Migration Notes
- Store profiles as full settings JSON under `~/.ccc/profiles`.
- Use `ccc import-cc-switch` to copy Claude providers from CC Switch.
- Direct `claude` launches continue to use the default Claude configuration.
- `ccc <profile>` disables default Claude setting sources for the spawned process, so user/project/local settings do not leak into the profile run.
