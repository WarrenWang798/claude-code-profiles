#!/usr/bin/env bash
# CCP 3.0 测试脚本：覆盖 launcher 校验、init 精准删除和安装迁移
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
CCC_SCRIPT="$ROOT_DIR/ccc"
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

run_ccc() {
    HOME="$TMP_HOME" PATH="$TMP_HOME/bin:$PATH" bash "$CCC_SCRIPT" "$@" 2>&1
}

run_ccc_with_ccp_cmd() {
    local ccp_cmd="$1"
    shift
    HOME="$TMP_HOME" PATH="$TMP_HOME/bin:$PATH" CCP_CMD="$ccp_cmd" bash "$CCC_SCRIPT" "$@" 2>&1
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

seed_mock_claude() {
    mkdir -p "$TMP_HOME/bin"
    cat > "$TMP_HOME/bin/claude" << 'EOF'
#!/usr/bin/env bash
echo "CLAUDE_ARGS:$*"
echo "ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-}"
echo "ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN:-}"
echo "ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-}"
echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY-unset}"
EOF
    chmod +x "$TMP_HOME/bin/claude"
}

setup() {
    info "Setting up isolated HOME"
    TMP_HOME="$(mktemp -d)"
    mkdir -p "$TMP_HOME/.claude"
    seed_profiles
    seed_mock_claude
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

assert_equals() {
    local actual="$1"
    local expected="$2"
    local msg="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$msg"
    else
        fail "$msg"
    fi
}

test_help() {
    info "help command"
    local out
    out=$(run help)
    assert_contains "$out" "USAGE:" "help displays usage"
    assert_contains "$out" "ccc <profile>" "help documents ccc launcher"
    assert_not_contains "$out" "Switch to specified profile" "help no longer documents ccp profile switching"
}

test_status() {
    info "status command"
    local out
    out=$(run status)
    assert_contains "$out" "Last launched profile:" "status uses last launched label"
    assert_contains "$out" "work" "status includes work profile"
}

test_list() {
    info "list command"
    local out
    out=$(run list)
    assert_contains "$out" "work" "list shows work profile"
    assert_contains "$out" "personal" "list shows personal profile"
}

test_ccc_launches_with_profile_env() {
    info "ccc launches with profile env"
    local out
    out=$(run_ccc work --resume abc123)
    assert_contains "$out" "CLAUDE_ARGS:--resume abc123" "ccc passes claude args through"
    assert_contains "$out" "ANTHROPIC_BASE_URL=https://api.work.com/v1" "ccc injects base url"
    assert_contains "$out" "ANTHROPIC_AUTH_TOKEN=sk-work-test-key" "ccc injects auth token"
    assert_contains "$out" "ANTHROPIC_MODEL=claude-sonnet-4" "ccc injects custom env"
    assert_contains "$out" "ANTHROPIC_API_KEY=unset" "ccc unsets ANTHROPIC_API_KEY"
}

test_ccc_runs_without_ccp_script() {
    info "ccc does not depend on ccp.sh"
    local out
    out=$(run_ccc_with_ccp_cmd "$TMP_HOME/does-not-exist" work 2>&1 || true)
    assert_contains "$out" "ANTHROPIC_BASE_URL=https://api.work.com/v1" "ccc works without ccp script"
}

test_ccc_requires_base_url() {
    info "ccc requires base url"
    cat > "$TMP_HOME/.ccp/profiles/broken.env" << 'ENVEOF'
ANTHROPIC_AUTH_TOKEN=sk-broken
ENVEOF
    local out
    out=$(run_ccc broken 2>&1 || true)
    assert_contains "$out" "missing required variable: ANTHROPIC_BASE_URL" "ccc rejects missing base url"
}

test_ccc_requires_auth_token() {
    info "ccc requires auth token"
    cat > "$TMP_HOME/.ccp/profiles/broken.env" << 'ENVEOF'
ANTHROPIC_BASE_URL=https://api.broken.test/v1
ENVEOF
    local out
    out=$(run_ccc broken 2>&1 || true)
    assert_contains "$out" "missing required variable: ANTHROPIC_AUTH_TOKEN" "ccc rejects missing auth token"
}

test_ccc_updates_current_after_validation() {
    info "ccc updates current after validation"
    run_ccc personal >/dev/null
    local current
    current=$(cat "$TMP_HOME/.ccp/current")
    assert_equals "$current" "personal" "ccc updates current profile"
}

test_ccc_no_shell_mutation() {
    info "ccc does not mutate caller shell"
    local out
    out=$(HOME="$TMP_HOME" PATH="$TMP_HOME/bin:$PATH" bash -c '
        export ANTHROPIC_BASE_URL="should-not-change"
        export ANTHROPIC_API_KEY="should-stay"
        bash "$1" work >/dev/null
        printf "%s|%s" "${ANTHROPIC_BASE_URL}" "${ANTHROPIC_API_KEY}"
    ' _ "$CCC_SCRIPT")
    assert_equals "$out" "should-not-change|should-stay" "ccc leaves caller shell env untouched"
}

test_nonexistent_profile() {
    info "unknown command instead of profile switch"
    local out
    out=$(run work 2>&1 || true)
    assert_contains "$out" "Unknown command: work" "ccp no longer treats profile names as commands"
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

test_init_preserves_non_env_keys_single_line() {
    info "init preserves single-line settings"
    printf '%s\n' '{"env":{"FOO":"1"},"permissions":{"allow":["Bash"]},"x":1}' > "$TMP_HOME/.claude/settings.json"

    run init >/dev/null

    local settings
    settings=$(cat "$TMP_HOME/.claude/settings.json")
    assert_not_contains "$settings" '"env"' "init removes env from single-line json"
    assert_contains "$settings" '"permissions"' "init preserves permissions in single-line json"
    assert_contains "$settings" '"x"' "init preserves other keys in single-line json"

    if ls "$TMP_HOME/.claude/backups"/settings.json.* >/dev/null 2>&1; then
        pass "init creates backup for single-line settings"
    else
        fail "init backup missing for single-line settings"
    fi
}

test_init_preserves_non_env_keys_multi_line() {
    info "init preserves multi-line settings"
    cat > "$TMP_HOME/.claude/settings.json" << 'JSONEOF'
{
  "permissions": {
    "allow": ["Bash"]
  },
  "env": {
    "FOO": "1"
  },
  "hooks": {
    "enabled": true
  }
}
JSONEOF

    run init >/dev/null

    local settings
    settings=$(cat "$TMP_HOME/.claude/settings.json")
    assert_not_contains "$settings" '"env"' "init removes env from multi-line json"
    assert_contains "$settings" '"permissions"' "init preserves permissions in multi-line json"
    assert_contains "$settings" '"hooks"' "init preserves hooks in multi-line json"
}

test_init_handles_braces_inside_strings() {
    info "init handles braces inside strings"
    printf '%s\n' '{"env":{"FOO":"1"},"note":"value with { braces } and , commas","x":1}' > "$TMP_HOME/.claude/settings.json"

    run init >/dev/null

    local settings
    settings=$(cat "$TMP_HOME/.claude/settings.json")
    assert_not_contains "$settings" '"env"' "init removes env when strings contain braces"
    assert_contains "$settings" 'value with { braces } and , commas' "init preserves string content with braces"
}

test_init_no_settings_file() {
    info "init creates empty settings when missing"
    rm -f "$TMP_HOME/.claude/settings.json"
    run init >/dev/null
    local settings
    settings=$(cat "$TMP_HOME/.claude/settings.json")
    assert_equals "$settings" "{}" "init creates empty object when settings file is missing"
}

test_install_removes_legacy_rc_blocks_without_reinjection() {
    info "install removes legacy rc blocks without reinjection"
    cat > "$TMP_HOME/.zshrc" << 'RCEOF'
before
# >>> ccp function begin >>>
legacy function block
# <<< ccp function end <<<
# >>> ccp init begin >>>
source "$HOME/.local/share/ccp/ccp-init.sh"
# <<< ccp init end <<<
after
RCEOF

    HOME="$TMP_HOME" SHELL=/bin/zsh bash "$INSTALL_SCRIPT" >/dev/null

    local rc_content
    rc_content=$(cat "$TMP_HOME/.zshrc")
    assert_not_contains "$rc_content" "ccp function begin" "install removes legacy function block"
    assert_not_contains "$rc_content" "ccp init begin" "install removes legacy init block"
    assert_not_contains "$rc_content" "ccp-init.sh" "install does not re-add source block"

    if [[ -L "$TMP_HOME/.local/bin/ccp" ]] && [[ -L "$TMP_HOME/.local/bin/ccc" ]]; then
        pass "install creates launcher symlinks"
    else
        fail "install missing launcher symlinks"
    fi

    if [[ ! -e "$TMP_HOME/.local/share/ccp/ccp-init.sh" ]]; then
        pass "install does not create ccp-init.sh"
    else
        fail "install should not create ccp-init.sh"
    fi
}

test_uninstall_removes_legacy_rc_blocks() {
    info "uninstall removes legacy rc blocks"
    mkdir -p "$TMP_HOME/.local/share/ccp"
    touch "$TMP_HOME/.local/share/ccp/ccp.sh"
    cat > "$TMP_HOME/.zshrc" << 'RCEOF'
before
# >>> ccp function begin >>>
legacy function block
# <<< ccp function end <<<
# >>> ccp init begin >>>
legacy init block
# <<< ccp init end <<<
after
RCEOF

    HOME="$TMP_HOME" SHELL=/bin/zsh bash "$UNINSTALL_SCRIPT" >/dev/null

    local rc_content
    rc_content=$(cat "$TMP_HOME/.zshrc")
    assert_not_contains "$rc_content" "ccp function begin" "uninstall removes legacy function block"
    assert_not_contains "$rc_content" "ccp init begin" "uninstall removes legacy init block"

    if [[ ! -d "$TMP_HOME/.local/share/ccp" ]]; then
        pass "uninstall removes install directory"
    else
        fail "uninstall should remove install directory"
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
    test_ccc_launches_with_profile_env
    test_ccc_runs_without_ccp_script
    test_ccc_requires_base_url
    test_ccc_requires_auth_token
    test_ccc_updates_current_after_validation
    test_ccc_no_shell_mutation
    test_nonexistent_profile
    test_set_unset_env
    test_invalid_key_rejected
    test_remove_profile
    test_init_preserves_non_env_keys_single_line
    test_init_preserves_non_env_keys_multi_line
    test_init_handles_braces_inside_strings
    test_init_no_settings_file
    test_install_removes_legacy_rc_blocks_without_reinjection
    test_uninstall_removes_legacy_rc_blocks

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
