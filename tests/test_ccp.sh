#!/usr/bin/env bash
# CCC 测试脚本：覆盖独立 settings profile 启动、cc-switch 导入和安装迁移
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
CCC_SCRIPT="$ROOT_DIR/ccc"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
UNINSTALL_SCRIPT="$ROOT_DIR/uninstall.sh"
TMP_HOME=""

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
info() { echo -e "${BLUE}→${NC} $1"; }

run_ccc() {
    HOME="$TMP_HOME" PATH="$TMP_HOME/bin:$PATH" bash "$CCC_SCRIPT" "$@" 2>&1
}

seed_profiles() {
    mkdir -p "$TMP_HOME/.ccc/profiles"

    cat > "$TMP_HOME/.ccc/profiles/work.json" << 'JSONEOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.work.com/v1",
    "ANTHROPIC_AUTH_TOKEN": "sk-work-test-key",
    "ANTHROPIC_MODEL": "claude-sonnet-4"
  },
  "includeCoAuthoredBy": false,
  "model": "opus[1m]",
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  }
}
JSONEOF
    chmod 600 "$TMP_HOME/.ccc/profiles/work.json"

    cat > "$TMP_HOME/.ccc/profiles/official.json" << 'JSONEOF'
{
  "env": {},
  "model": "sonnet"
}
JSONEOF
    chmod 600 "$TMP_HOME/.ccc/profiles/official.json"

    echo "work" > "$TMP_HOME/.ccc/current"
    chmod 600 "$TMP_HOME/.ccc/current"
}

seed_mock_claude() {
    mkdir -p "$TMP_HOME/bin"
    cat > "$TMP_HOME/bin/claude" << 'EOF'
#!/usr/bin/env bash
settings_file=""
setting_sources_seen=0
setting_sources_value=""
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --settings)
            settings_file="$2"
            shift 2
            ;;
        --setting-sources)
            setting_sources_seen=1
            setting_sources_value="$2"
            shift 2
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
echo "SETTINGS_PATH:${settings_file}"
echo "SETTING_SOURCES_SEEN:${setting_sources_seen}"
echo "SETTING_SOURCES_VALUE:${setting_sources_value}"
if [[ -n "$settings_file" && -f "$settings_file" ]]; then
    echo "SETTINGS_CONTENT_BEGIN"
    cat "$settings_file"
    echo "SETTINGS_CONTENT_END"
fi
echo "CLAUDE_ARGS:${args[*]}"
echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY-unset}"
EOF
    chmod +x "$TMP_HOME/bin/claude"
}

seed_mock_sqlite3() {
    cat > "$TMP_HOME/bin/sqlite3" << 'EOF'
#!/usr/bin/env bash
    if [[ "$1" == "-separator" ]]; then
        shift 2
    fi
    db="$1"
    query="$2"
printf 'SQLITE_DB:%s\n' "$db" >&2
case "$query" in
    *"where app_type='claude' and is_current=1"*)
        printf '%s\t%s\n' "Current Claude" '{"env":{"ANTHROPIC_BASE_URL":"https://current.example.com","ANTHROPIC_AUTH_TOKEN":"sk-current"},"model":"sonnet"}'
        ;;
    *"where app_type='claude'"*)
        printf '%s\t%s\n' "Work One" '{"env":{"ANTHROPIC_BASE_URL":"https://work.example.com","ANTHROPIC_AUTH_TOKEN":"sk-work"},"includeCoAuthoredBy":false}'
        printf '%s\t%s\n' "七牛 work" '{"env":{"ANTHROPIC_BASE_URL":"https://qiniu.example.com","ANTHROPIC_AUTH_TOKEN":"sk-qiniu"},"model":"opus"}'
        ;;
    *)
        echo "unexpected query: $query" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$TMP_HOME/bin/sqlite3"
}

setup() {
    info "Setting up isolated HOME"
    TMP_HOME="$(mktemp -d)"
    mkdir -p "$TMP_HOME/.claude"
    seed_profiles
    seed_mock_claude
    seed_mock_sqlite3
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
    if echo "$haystack" | grep -qF "$needle"; then
        pass "$msg"
    else
        fail "$msg"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "$haystack" | grep -qF "$needle"; then
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
    out=$(run_ccc help)
    assert_contains "$out" "ccc <profile>" "help displays launcher usage"
    assert_contains "$out" "import-cc-switch" "help documents cc-switch import"
    assert_not_contains "$out" "ccp" "help does not reference ccp"
}

test_launches_complete_settings_json() {
    info "ccc launches with complete settings json"
    local out
    out=$(run_ccc work --resume abc123)
    assert_contains "$out" "SETTINGS_PATH:$TMP_HOME/.ccc/profiles/work.json" "ccc passes profile json as settings"
    assert_contains "$out" "SETTING_SOURCES_SEEN:1" "ccc explicitly controls setting sources"
    assert_contains "$out" "SETTING_SOURCES_VALUE:" "ccc disables default setting sources"
    assert_contains "$out" "CLAUDE_ARGS:--resume abc123" "ccc passes claude args through"
    assert_contains "$out" '"enabledPlugins": {' "ccc preserves non-env settings"
    assert_contains "$out" '"includeCoAuthoredBy": false' "ccc preserves top-level settings"
    assert_contains "$out" "ANTHROPIC_API_KEY=unset" "ccc clears external api key"
}

test_launch_accepts_empty_env_settings() {
    info "ccc accepts complete settings without auth env"
    local out
    out=$(run_ccc official)
    assert_contains "$out" "SETTINGS_PATH:$TMP_HOME/.ccc/profiles/official.json" "ccc accepts full settings json without required env keys"
    assert_contains "$out" '"model": "sonnet"' "ccc passes official settings through"
}

test_no_shell_or_default_settings_mutation() {
    info "ccc does not mutate shell or default settings"
    cat > "$TMP_HOME/.claude/settings.json" << 'JSONEOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://default.example.com"
  }
}
JSONEOF
    local before after out
    before=$(cat "$TMP_HOME/.claude/settings.json")
    out=$(HOME="$TMP_HOME" PATH="$TMP_HOME/bin:$PATH" ANTHROPIC_API_KEY="external" bash "$CCC_SCRIPT" work)
    after=$(cat "$TMP_HOME/.claude/settings.json")
    assert_equals "$after" "$before" "ccc preserves ~/.claude/settings.json"
    assert_contains "$out" "ANTHROPIC_API_KEY=unset" "ccc does not leak external api key"
    assert_not_contains "$out" "https://default.example.com" "ccc does not use default settings as profile"
}

test_list_show_path() {
    info "list/show/path commands"
    local list show path
    list=$(run_ccc list)
    show=$(run_ccc show work)
    path=$(run_ccc path work)
    assert_contains "$list" "work" "list shows work profile"
    assert_contains "$list" "official" "list shows official profile"
    assert_contains "$show" "Profile: work" "show prints profile name"
    assert_contains "$show" "Path: $TMP_HOME/.ccc/profiles/work.json" "show prints profile path"
    assert_not_contains "$show" "sk-work-test-key" "show masks secrets by omission"
    assert_equals "$path" "$TMP_HOME/.ccc/profiles/work.json" "path prints exact profile path"
}

test_import_cc_switch_all() {
    info "import all cc-switch claude providers"
    mkdir -p "$TMP_HOME/.cc-switch"
    touch "$TMP_HOME/.cc-switch/cc-switch.db"
    local out
    out=$(run_ccc import-cc-switch)
    assert_contains "$out" "Imported: Work One -> work-one" "imports ascii provider"
    assert_contains "$out" "Imported: 七牛 work -> work-2" "imports non-ascii provider with sanitized fallback"
    assert_contains "$(cat "$TMP_HOME/.ccc/profiles/work-one.json")" "https://work.example.com" "writes imported provider settings"
    assert_contains "$(cat "$TMP_HOME/.ccc/profiles/work-2.json")" "https://qiniu.example.com" "writes sanitized non-ascii provider settings"
    assert_contains "$(cat "$TMP_HOME/.ccc/profiles/work-one.json")" $'\n  "env": {\n' "formats imported json for readability"

    printf '%s\n' '{"stale":true}' > "$TMP_HOME/.ccc/profiles/work-one.json"
    out=$(run_ccc import-cc-switch)
    assert_contains "$out" "Imported: Work One -> work-one" "repeat import overwrites same profile"
    assert_contains "$(cat "$TMP_HOME/.ccc/profiles/work-one.json")" "https://work.example.com" "repeat import refreshes profile content"
    if [[ ! -f "$TMP_HOME/.ccc/profiles/work-one-2.json" ]]; then
        pass "repeat import does not create duplicate profile"
    else
        fail "repeat import should not create duplicate profile"
    fi
}

test_import_cc_switch_current() {
    info "import current cc-switch claude provider"
    mkdir -p "$TMP_HOME/.cc-switch"
    touch "$TMP_HOME/.cc-switch/cc-switch.db"
    local out
    out=$(run_ccc import-cc-switch --current)
    assert_contains "$out" "Imported: Current Claude -> current-claude" "imports current provider"
    assert_contains "$(cat "$TMP_HOME/.ccc/profiles/current-claude.json")" "https://current.example.com" "writes current provider settings"
    rm -f "$TMP_HOME/.ccc/profiles/work-one.json" "$TMP_HOME/.ccc/profiles/work-2.json"
    if [[ ! -f "$TMP_HOME/.ccc/profiles/work-one.json" ]]; then
        pass "current import does not import all providers"
    else
        fail "current import should not import all providers"
    fi
}

test_install_only_installs_ccc() {
    info "install only installs ccc"
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
    HOME="$TMP_HOME" SHELL=/bin/zsh bash "$INSTALL_SCRIPT" >/dev/null
    local rc_content
    rc_content=$(cat "$TMP_HOME/.zshrc")
    assert_not_contains "$rc_content" "ccp function begin" "install removes legacy function block"
    assert_not_contains "$rc_content" "ccp init begin" "install removes legacy init block"
    if [[ -L "$TMP_HOME/.local/bin/ccc" && ! -e "$TMP_HOME/.local/bin/ccp" ]]; then
        pass "install creates ccc symlink only"
    else
        fail "install should create only ccc symlink"
    fi
}

test_uninstall_removes_ccc_and_legacy() {
    info "uninstall removes ccc and legacy"
    mkdir -p "$TMP_HOME/.local/share/ccc" "$TMP_HOME/.local/bin"
    touch "$TMP_HOME/.local/share/ccc/ccc"
    rm -f "$TMP_HOME/.local/bin/ccc"
    ln -s "$TMP_HOME/.local/share/ccc/ccc" "$TMP_HOME/.local/bin/ccc"
    touch "$TMP_HOME/.local/bin/ccp"
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
    if [[ ! -e "$TMP_HOME/.local/bin/ccc" && ! -e "$TMP_HOME/.local/bin/ccp" && ! -d "$TMP_HOME/.local/share/ccc" ]]; then
        pass "uninstall removes ccc install surface"
    else
        fail "uninstall should remove ccc install surface"
    fi
}

main() {
    echo "========================================"
    echo "CCC Test Suite"
    echo "========================================"
    echo ""

    setup

    test_help
    test_launches_complete_settings_json
    test_launch_accepts_empty_env_settings
    test_no_shell_or_default_settings_mutation
    test_list_show_path
    test_import_cc_switch_all
    test_import_cc_switch_current
    test_install_only_installs_ccc
    test_uninstall_removes_ccc_and_legacy

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
