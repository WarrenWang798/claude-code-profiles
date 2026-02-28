#!/usr/bin/env bash
# CCP 测试脚本 — 覆盖所有核心操作
set -euo pipefail

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 计数器
PASS=0
FAIL=0
TOTAL=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCP_SCRIPT="${SCRIPT_DIR}/../ccp.sh"
TMP_HOME=""

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
info() { echo -e "${BLUE}→${NC} $1"; }

# 运行 ccp 命令（隔离 HOME）
run() { HOME="$TMP_HOME" bash "$CCP_SCRIPT" "$@" 2>&1; }

# 仅获取 stdout（export 语句）
exports() { HOME="$TMP_HOME" bash "$CCP_SCRIPT" "$@" 2>/dev/null; }

# 写入测试 profile（直接写 JSON 绕过交互式 add）
seed_config() {
    cat > "$TMP_HOME/.ccp_profiles.json" << 'EOF'
{
  "current": "",
  "profiles": {
    "work": {
      "base_url": "https://api.work.com",
      "api_key": "sk-work-key-123",
      "env": {
        "MODEL": "claude-4",
        "TIMEOUT": "60000"
      }
    },
    "personal": {
      "base_url": "https://api.anthropic.com",
      "api_key": "sk-ant-personal"
    }
  }
}
EOF
    chmod 600 "$TMP_HOME/.ccp_profiles.json"
}

setup() {
    info "Setting up test environment..."
    TMP_HOME=$(mktemp -d)
    mkdir -p "$TMP_HOME/.claude"
    seed_config
    info "Test HOME: $TMP_HOME"
    echo ""
}

cleanup() { [[ -n "$TMP_HOME" && -d "$TMP_HOME" ]] && rm -rf "$TMP_HOME"; }

# ============ TEST CASES ============

test_help() {
    info "help command"
    local out; out=$(run help)
    echo "$out" | grep -q "Usage:" && pass "help displays usage" || fail "help missing usage"
}

test_status() {
    info "status command"
    local out; out=$(run status)
    echo "$out" | grep -q "Current configuration" && pass "status works" || fail "status broken"
}

test_list() {
    info "list profiles"
    local out; out=$(run list)
    echo "$out" | grep -q "work" && pass "list shows work profile" || fail "list missing work"
    echo "$out" | grep -q "personal" && pass "list shows personal profile" || fail "list missing personal"
    echo "$out" | grep -q "+2 env vars" && pass "list shows env count" || fail "list missing env count"
}

test_switch_exports() {
    info "switch profile exports"
    local out; out=$(exports work)
    echo "$out" | grep -q "export ANTHROPIC_BASE_URL=" && pass "switch exports BASE_URL" || fail "missing BASE_URL"
    echo "$out" | grep -q "https://api.work.com" && pass "switch has correct URL" || fail "wrong URL"
    echo "$out" | grep -q "export ANTHROPIC_AUTH_TOKEN=" && pass "switch exports AUTH_TOKEN" || fail "missing AUTH_TOKEN"
    echo "$out" | grep -q "unset ANTHROPIC_API_KEY" && pass "switch unsets API_KEY" || fail "missing unset"
    echo "$out" | grep -q "export MODEL=" && pass "switch exports custom env" || fail "missing custom env"
}

test_switch_updates_current() {
    info "switch updates current"
    exports work >/dev/null
    local cur; cur=$(HOME="$TMP_HOME" bash "$CCP_SCRIPT" status 2>&1 | grep "Profile:" | head -1)
    echo "$cur" | grep -q "work" && pass "current updated to work" || fail "current not updated"
}

test_nonexistent_profile() {
    info "non-existent profile error"
    local out; out=$(run nonexistent_xyz 2>&1) || true
    echo "$out" | grep -q "not found" && pass "non-existent profile rejected" || fail "no error for bad profile"
}

test_set_env() {
    info "set-env"
    run set-env work NEW_VAR "new_value" >/dev/null
    local out; out=$(run show-env work)
    echo "$out" | grep -q "NEW_VAR" && pass "set-env adds var" || fail "set-env failed"
}

test_unset_env() {
    info "unset-env"
    run set-env work TEMP_VAR "temp" >/dev/null
    run unset-env work TEMP_VAR >/dev/null
    local out; out=$(run show-env work)
    echo "$out" | grep -q "TEMP_VAR" && fail "unset-env didn't remove" || pass "unset-env removes var"
}

test_env_spaces_roundtrip() {
    info "env value with spaces"
    run set-env work SPACED "hello beautiful world" >/dev/null
    local out; out=$(exports work)
    echo "$out" | grep -q "hello beautiful world" && pass "spaces preserved" || fail "spaces lost"
    # cleanup
    run unset-env work SPACED >/dev/null
}

test_env_singlequote_roundtrip() {
    info "env value with single quotes"
    run set-env work QUOTED "it's a test" >/dev/null
    local out; out=$(exports work)
    # value should contain escaped single quote
    echo "$out" | grep "QUOTED=" | grep -q "it" && pass "single-quote value handled" || fail "single-quote broken"
    # verify the export is valid shell
    eval "$(echo "$out" | grep "QUOTED=")" 2>/dev/null && pass "single-quote export is valid shell" || fail "single-quote eval fails"
    run unset-env work QUOTED >/dev/null
}

test_malicious_key_rejected() {
    info "malicious env key rejected"
    local out; out=$(run set-env work "FOO;rm -rf /" "evil" 2>&1) || true
    echo "$out" | grep -q "Invalid" && pass "injection key rejected" || fail "injection key accepted!"
}

test_key_with_spaces_rejected() {
    info "key with spaces rejected"
    local out; out=$(run set-env work "BAD KEY" "val" 2>&1) || true
    echo "$out" | grep -q "Invalid" && pass "spaced key rejected" || fail "spaced key accepted!"
}

test_remove_preserves_others() {
    info "remove profile preserves others"
    run remove personal >/dev/null
    local out; out=$(run list)
    echo "$out" | grep -q "personal" && fail "personal still present" || pass "personal removed"
    echo "$out" | grep -q "work" && pass "work preserved after remove" || fail "work lost after remove"
}

test_set_env_preserves_profile() {
    info "set-env preserves base_url/api_key"
    run set-env work EXTRA "extra_val" >/dev/null
    local out; out=$(exports work)
    echo "$out" | grep -q "https://api.work.com" && pass "base_url preserved" || fail "base_url lost"
    echo "$out" | grep -q "sk-work-key-123" && pass "api_key preserved" || fail "api_key lost"
    run unset-env work EXTRA >/dev/null
}

test_init_removes_env() {
    info "init removes env from settings.json"
    cat > "$TMP_HOME/.claude/settings.json" << 'EOF'
{
  "something": "value",
  "env": {
    "CONFLICT": "conflict_value"
  }
}
EOF
    run init >/dev/null
    grep -q "CONFLICT" "$TMP_HOME/.claude/settings.json" 2>/dev/null && fail "init didn't remove env" || pass "init removed env"
}

test_init_no_env() {
    info "init handles no env gracefully"
    cat > "$TMP_HOME/.claude/settings.json" << 'EOF'
{
  "something": "value"
}
EOF
    local out; out=$(run init)
    echo "$out" | grep -qi "no env\|already" && pass "init handles no-env" || fail "init bad no-env handling"
}

test_config_json_valid() {
    info "config JSON remains valid after mutations"
    # After all the mutations, verify the JSON is parseable by awk
    local profiles; profiles=$(HOME="$TMP_HOME" bash "$CCP_SCRIPT" list 2>&1)
    echo "$profiles" | grep -q "work" && pass "JSON still valid after mutations" || fail "JSON corrupted"
}

# ============ MAIN ============

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
    test_set_env
    test_unset_env
    test_env_spaces_roundtrip
    test_env_singlequote_roundtrip
    test_malicious_key_rejected
    test_key_with_spaces_rejected
    test_remove_preserves_others
    test_set_env_preserves_profile
    test_init_removes_env
    test_init_no_env
    test_config_json_valid

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
