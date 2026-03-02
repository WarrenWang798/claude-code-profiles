#!/usr/bin/env bash
# CCP 2.0 测试脚本：覆盖核心命令与安装注入行为
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CCP_SCRIPT="$ROOT_DIR/ccp.sh"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
UNINSTALL_SCRIPT="$ROOT_DIR/uninstall.sh"
TMP_HOME=""

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
info() { echo -e "${BLUE}→${NC} $1"; }

run() {
    HOME="$TMP_HOME" bash "$CCP_SCRIPT" "$@" 2>&1
}

run_with_input() {
    local input="$1"
    shift
    printf '%s' "$input" | HOME="$TMP_HOME" bash "$CCP_SCRIPT" "$@" 2>&1
}

exports() {
    HOME="$TMP_HOME" bash "$CCP_SCRIPT" "$@" 2>/dev/null
}

seed_profiles() {
    mkdir -p "$TMP_HOME/.ccp/profiles"

    cat > "$TMP_HOME/.ccp/profiles/work.env" << 'ENVEOF'
# CCP Profile: work
ANTHROPIC_BASE_URL=https://api.work.com/v1
ANTHROPIC_AUTH_TOKEN=sk-work-test-key
# Custom env vars
ANTHROPIC_MODEL=claude-sonnet-4
ENVEOF
    chmod 600 "$TMP_HOME/.ccp/profiles/work.env"

    cat > "$TMP_HOME/.ccp/profiles/personal.env" << 'ENVEOF'
# CCP Profile: personal
ANTHROPIC_BASE_URL=https://api.anthropic.com
ANTHROPIC_AUTH_TOKEN=sk-personal-test-key
ENVEOF
    chmod 600 "$TMP_HOME/.ccp/profiles/personal.env"

    echo "work" > "$TMP_HOME/.ccp/current"
    chmod 600 "$TMP_HOME/.ccp/current"
}

setup() {
    info "Setting up isolated HOME"
    TMP_HOME="$(mktemp -d)"
    mkdir -p "$TMP_HOME/.claude"
    seed_profiles
    info "Test HOME: $TMP_HOME"
    echo ""
}

cleanup() {
    if [[ -n "$TMP_HOME" && -d "$TMP_HOME" ]]; then
        rm -rf "$TMP_HOME"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "$haystack" | grep -q "$needle"; then
        pass "$msg"
    else
        fail "$msg"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "$haystack" | grep -q "$needle"; then
        fail "$msg"
    else
        pass "$msg"
    fi
}

test_help() {
    info "help command"
    local out
    out=$(run help)
    assert_contains "$out" "USAGE:" "help displays usage"
}

test_status() {
    info "status command"
    local out
    out=$(run status)
    assert_contains "$out" "Current profile:" "status shows current profile"
    assert_contains "$out" "work" "status includes work profile"
}

test_list() {
    info "list command"
    local out
    out=$(run list)
    assert_contains "$out" "work" "list shows work profile"
    assert_contains "$out" "personal" "list shows personal profile"
}

test_switch_exports() {
    info "switch exports"
    local out
    out=$(exports work)
    assert_contains "$out" "export ANTHROPIC_BASE_URL='https://api.work.com/v1'" "switch exports base url"
    assert_contains "$out" "export ANTHROPIC_AUTH_TOKEN='sk-work-test-key'" "switch exports auth token"
    assert_contains "$out" "export ANTHROPIC_MODEL='claude-sonnet-4'" "switch exports custom env"
    assert_contains "$out" "unset ANTHROPIC_API_KEY" "switch unsets API key"
}

test_switch_updates_current() {
    info "switch updates current"
    exports personal >/dev/null
    local current
    current=$(cat "$TMP_HOME/.ccp/current")
    if [[ "$current" == "personal" ]]; then
        pass "current profile updated"
    else
        fail "current profile not updated"
    fi
}

test_nonexistent_profile() {
    info "nonexistent profile"
    local out
    out=$(run not_exists 2>&1 || true)
    assert_contains "$out" "does not exist" "nonexistent profile rejected"
}

test_set_unset_env() {
    info "set-env and unset-env"
    run set-env work NEW_VAR "new value" >/dev/null
    local show
    show=$(run show-env work)
    assert_contains "$show" "NEW_VAR=new value" "set-env adds variable"

    run unset-env work NEW_VAR >/dev/null
    show=$(run show-env work)
    assert_not_contains "$show" "NEW_VAR=" "unset-env removes variable"
}

test_singlequote_roundtrip() {
    info "single quote roundtrip"
    run set-env work QUOTED "it's test" >/dev/null
    local out
    out=$(exports work)
    local line
    line=$(echo "$out" | grep "export QUOTED=")
    if eval "$line" 2>/dev/null && [[ "${QUOTED:-}" == "it's test" ]]; then
        pass "single quote export remains eval-safe"
    else
        fail "single quote export broken"
    fi
    run unset-env work QUOTED >/dev/null
}

test_invalid_key_rejected() {
    info "invalid key rejected"
    local out
    out=$(run set-env work "BAD KEY" value 2>&1 || true)
    assert_contains "$out" "Invalid variable name" "invalid env key rejected"
}

test_remove_profile() {
    info "remove profile"
    run_with_input "y\n" remove personal >/dev/null
    local out
    out=$(run list)
    assert_not_contains "$out" "personal" "remove deletes target profile"
    assert_contains "$out" "work" "remove preserves other profiles"
}

test_init_resets_settings_and_backup() {
    info "init command"
    cat > "$TMP_HOME/.claude/settings.json" << 'JSONEOF'
{
  "env": {
    "CONFLICT": "1"
  },
  "x": 1
}
JSONEOF

    run init >/dev/null

    local settings
    settings=$(cat "$TMP_HOME/.claude/settings.json")
    if [[ "$settings" == "{}" ]]; then
        pass "init resets settings.json to empty object"
    else
        fail "init did not reset settings.json"
    fi

    if ls "$TMP_HOME/.claude/backups"/settings.json.* >/dev/null 2>&1; then
        pass "init creates backup"
    else
        fail "init backup missing"
    fi
}

test_install_injects_minimal_source_block() {
    info "install/uninstall source block regression"

    HOME="$TMP_HOME" SHELL=/bin/zsh bash "$INSTALL_SCRIPT" >/dev/null

    local rc
    rc="$TMP_HOME/.zshrc"
    local init
    init="$TMP_HOME/.local/share/ccp/ccp-init.sh"

    if [[ -f "$init" ]]; then
        pass "install creates ccp-init.sh"
    else
        fail "install missing ccp-init.sh"
    fi

    local rc_content
    rc_content=$(cat "$rc")
    assert_contains "$rc_content" "# >>> ccp init begin >>>" "rc contains new begin marker"
    assert_contains "$rc_content" "source" "rc contains source statement"
    assert_not_contains "$rc_content" "ccp()" "rc does not inject large function body"

    HOME="$TMP_HOME" SHELL=/bin/zsh bash "$UNINSTALL_SCRIPT" >/dev/null
    if [[ -f "$rc" ]] && [[ -z "$(cat "$rc")" ]]; then
        pass "uninstall removes injected rc block"
    else
        fail "uninstall did not clean rc block"
    fi
}

main() {
    echo "========================================"
    echo "CCP Test Suite"
    echo "========================================"
    echo ""

    setup

    test_help
    test_status
    test_list
    test_switch_exports
    test_switch_updates_current
    test_nonexistent_profile
    test_set_unset_env
    test_singlequote_roundtrip
    test_invalid_key_rejected
    test_remove_profile
    test_init_resets_settings_and_backup
    test_install_injects_minimal_source_block

    cleanup

    echo ""
    echo "========================================"
    echo "Results: ${PASS}/${TOTAL} passed"
    echo "========================================"

    if [[ $FAIL -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}${FAIL} test(s) failed${NC}"
        exit 1
    fi
}

main "$@"
