#!/bin/bash
set -euo pipefail

############################################################
# Claude Code Profile Switcher (CCP)
# ---------------------------------------------------------
# 功能: 管理多套 Claude Code API 配置（base_url + api_key + 自定义环境变量）
# 用法: ccp <profile> | ccp add <name> | ccp list | ccp status
# 版本: 2.0.0
############################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置文件路径
PROFILES_FILE="$HOME/.ccp_profiles.json"

# 校验环境变量名是否合法
_is_valid_env_key() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }

# Shell 安全单引号转义
_shell_quote() {
    local s="$1"
    s=${s//\'/\'"\'"\'}
    printf '%s' "$s"
}

# 原子写入文件
_atomic_write() {
    local target="$1"
    local tmp
    tmp=$(mktemp "${target}.tmp.XXXXXX")
    cat > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$target"
}

# 通用 JSON 内核（固定 schema + 纯 awk）
# 支持操作:
#   get_current / list_profiles / profile_exists / get_value / get_env_vars
#   set_current / save_profile / save_profile_with_env / set_env_var / unset_env_var / remove_profile
_json_core() {
    local file="$1"
    local op="$2"
    local a1="${3:-}"
    local a2="${4:-}"
    local a3="${5:-}"
    local env_file="${6:-}"

    awk -v op="$op" -v a1="$a1" -v a2="$a2" -v a3="$a3" -v env_file="$env_file" '
function jerr(msg) { print msg > "/dev/stderr"; exit 3 }
function skip_ws(  c) { while (i <= L) { c = substr(S, i, 1); if (c ~ /[ \t\r\n]/) i++; else break } }
function expect(ch,  c) { skip_ws(); c = substr(S, i, 1); if (c != ch) jerr("JSON parse error: expected " ch " at pos " i); i++ }
function parse_string(  c, n, hex, out) {
    skip_ws()
    if (substr(S, i, 1) != "\"") jerr("JSON parse error: expected string at pos " i)
    i++; out = ""
    while (i <= L) {
        c = substr(S, i, 1)
        if (c == "\"") { i++; return out }
        if (c == "\\") {
            i++; if (i > L) jerr("JSON parse error: bad escape")
            n = substr(S, i, 1)
            if (n == "\"" || n == "\\" || n == "/") out = out n
            else if (n == "b") out = out sprintf("%c", 8)
            else if (n == "f") out = out sprintf("%c", 12)
            else if (n == "n") out = out "\n"
            else if (n == "r") out = out "\r"
            else if (n == "t") out = out "\t"
            else if (n == "u") {
                hex = substr(S, i + 1, 4)
                if (hex ~ /^[0-9A-Fa-f]{4}$/) {
                    # 仅保留 unicode 转义原样语义（对本项目配置够用）
                    out = out "\\u" hex
                    i += 4
                } else {
                    jerr("JSON parse error: bad unicode escape")
                }
            } else {
                jerr("JSON parse error: unknown escape \\" n)
            }
            i++
        } else {
            out = out c
            i++
        }
    }
    jerr("JSON parse error: unterminated string")
}
function parse_token(  st, c) {
    skip_ws()
    st = i
    while (i <= L) {
        c = substr(S, i, 1)
        if (c ~ /[ \t\r\n,}\]]/) break
        i++
    }
    return substr(S, st, i - st)
}
function skip_value(  c) {
    skip_ws()
    c = substr(S, i, 1)
    if (c == "\"") { parse_string(); return }
    if (c == "{") { skip_object(); return }
    if (c == "[") { skip_array(); return }
    parse_token()
}
function skip_object(  c, k) {
    expect("{")
    skip_ws(); c = substr(S, i, 1)
    if (c == "}") { i++; return }
    while (1) {
        k = parse_string()
        expect(":")
        skip_value()
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "}") { i++; break }
        jerr("JSON parse error: bad object separator at pos " i)
    }
}
function skip_array(  c) {
    expect("[")
    skip_ws(); c = substr(S, i, 1)
    if (c == "]") { i++; return }
    while (1) {
        skip_value()
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "]") { i++; break }
        jerr("JSON parse error: bad array separator at pos " i)
    }
}
function parse_scalar_as_string(  c, t) {
    skip_ws()
    c = substr(S, i, 1)
    if (c == "\"") return parse_string()
    t = parse_token()
    if (t == "null") return ""
    return t
}
function ensure_profile(p) {
    if (!(p in profile_seen)) {
        profile_seen[p] = 1
        profile_count++
        profile_order[profile_count] = p
        base_url[p] = ""
        api_key[p] = ""
        env_count[p] = 0
    }
}
function set_env(p, k, v, idx) {
    ensure_profile(p)
    if (!((p SUBSEP k) in env_seen)) {
        env_count[p]++
        idx = env_count[p]
        env_order[p SUBSEP idx] = k
        env_seen[p SUBSEP k] = 1
    }
    env_val[p SUBSEP k] = v
}
function clear_env(p,   kk, a) {
    delete env_count[p]
    env_count[p] = 0
    for (kk in env_order) {
        split(kk, a, SUBSEP)
        if (a[1] == p) delete env_order[kk]
    }
    for (kk in env_seen) {
        split(kk, a, SUBSEP)
        if (a[1] == p) delete env_seen[kk]
    }
    for (kk in env_val) {
        split(kk, a, SUBSEP)
        if (a[1] == p) delete env_val[kk]
    }
}
function compact_env_order(p,   j, key, n) {
    n = 0
    for (j = 1; j <= env_count[p]; j++) {
        key = env_order[p SUBSEP j]
        if (key != "" && ((p SUBSEP key) in env_seen)) {
            n++
            new_env_order[p SUBSEP n] = key
        }
    }
    for (j = 1; j <= env_count[p]; j++) delete env_order[p SUBSEP j]
    env_count[p] = n
    for (j = 1; j <= n; j++) env_order[p SUBSEP j] = new_env_order[p SUBSEP j]
    for (j = 1; j <= n; j++) delete new_env_order[p SUBSEP j]
}
function remove_profile_internal(p,   i, j, x) {
    if (!(p in profile_seen)) return
    delete profile_seen[p]
    delete base_url[p]
    delete api_key[p]
    clear_env(p)
    x = 0
    for (i = 1; i <= profile_count; i++) {
        if (profile_order[i] != p) {
            x++
            new_profile_order[x] = profile_order[i]
        }
    }
    for (i = 1; i <= profile_count; i++) delete profile_order[i]
    profile_count = x
    for (i = 1; i <= profile_count; i++) {
        profile_order[i] = new_profile_order[i]
        delete new_profile_order[i]
    }
    if (current == p) current = ""
}
function parse_env(p,   c, k, v) {
    expect("{")
    skip_ws(); c = substr(S, i, 1)
    if (c == "}") { i++; return }
    while (1) {
        k = parse_string()
        expect(":")
        v = parse_scalar_as_string()
        set_env(p, k, v)
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "}") { i++; break }
        jerr("JSON parse error: bad env object at pos " i)
    }
}
function parse_profile(p,   c, k, v) {
    ensure_profile(p)
    expect("{")
    skip_ws(); c = substr(S, i, 1)
    if (c == "}") { i++; return }
    while (1) {
        k = parse_string()
        expect(":")
        if (k == "base_url") {
            base_url[p] = parse_scalar_as_string()
        } else if (k == "api_key") {
            api_key[p] = parse_scalar_as_string()
        } else if (k == "env") {
            parse_env(p)
        } else {
            skip_value()
        }
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "}") { i++; break }
        jerr("JSON parse error: bad profile object at pos " i)
    }
}
function parse_profiles(  c, p) {
    expect("{")
    skip_ws(); c = substr(S, i, 1)
    if (c == "}") { i++; return }
    while (1) {
        p = parse_string()
        expect(":")
        parse_profile(p)
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "}") { i++; break }
        jerr("JSON parse error: bad profiles object at pos " i)
    }
}
function parse_root(  c, k) {
    expect("{")
    skip_ws(); c = substr(S, i, 1)
    if (c == "}") { i++; return }
    while (1) {
        k = parse_string()
        expect(":")
        if (k == "current") current = parse_scalar_as_string()
        else if (k == "profiles") parse_profiles()
        else skip_value()
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "}") { i++; break }
        jerr("JSON parse error: bad root object at pos " i)
    }
}
function jesc(s,   out, c, idx) {
    out = ""
    for (idx = 1; idx <= length(s); idx++) {
        c = substr(s, idx, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c == "\n") out = out "\\n"
        else if (c == "\r") out = out "\\r"
        else if (c == "\t") out = out "\\t"
        else out = out c
    }
    return out
}
function emit_json(  i, j, p, k, comma_p, comma_e) {
    print "{"
    print "  \"current\": \"" jesc(current) "\"," 
    print "  \"profiles\": {"
    for (i = 1; i <= profile_count; i++) {
        p = profile_order[i]
        print "    \"" jesc(p) "\": {"
        if (env_count[p] > 0) {
            print "      \"base_url\": \"" jesc(base_url[p]) "\"," 
            print "      \"api_key\": \"" jesc(api_key[p]) "\"," 
            print "      \"env\": {"
            for (j = 1; j <= env_count[p]; j++) {
                k = env_order[p SUBSEP j]
                comma_e = (j < env_count[p]) ? "," : ""
                print "        \"" jesc(k) "\": \"" jesc(env_val[p SUBSEP k]) "\"" comma_e
            }
            print "      }"
        } else {
            print "      \"base_url\": \"" jesc(base_url[p]) "\"," 
            print "      \"api_key\": \"" jesc(api_key[p]) "\""
        }
        comma_p = (i < profile_count) ? "," : ""
        print "    }" comma_p
    }
    print "  }"
    print "}"
}
function op_get_value(path,   n, arr, p, k) {
    n = split(path, arr, /\./)
    if (n == 1 && arr[1] == "current") { print current; return 0 }
    if (n == 4 && arr[1] == "profiles" && arr[3] == "env") {
        p = arr[2]; k = arr[4]
        if ((p SUBSEP k) in env_val) print env_val[p SUBSEP k]
        return 0
    }
    if (n == 3 && arr[1] == "profiles") {
        p = arr[2]
        if (arr[3] == "base_url") { print base_url[p]; return 0 }
        if (arr[3] == "api_key") { print api_key[p]; return 0 }
    }
    return 0
}
BEGIN {
    S = ""
    L = 0
    i = 1
    current = ""
    profile_count = 0
}
{
    S = S $0 "\n"
}
END {
    L = length(S)
    if (L > 0) {
        skip_ws()
        if (i <= L) parse_root()
    }

    if (op == "get_current") {
        print current
        exit 0
    }
    if (op == "list_profiles") {
        for (x = 1; x <= profile_count; x++) print profile_order[x]
        exit 0
    }
    if (op == "profile_exists") {
        if (a1 in profile_seen) { print "1"; exit 0 }
        exit 1
    }
    if (op == "get_value") {
        op_get_value(a1)
        exit 0
    }
    if (op == "get_env_vars") {
        p = a1
        if (p in profile_seen) {
            for (x = 1; x <= env_count[p]; x++) {
                k = env_order[p SUBSEP x]
                print k "=" env_val[p SUBSEP k]
            }
        }
        exit 0
    }

    if (op == "set_current") {
        current = a1
        emit_json()
        exit 0
    }
    if (op == "save_profile") {
        ensure_profile(a1)
        base_url[a1] = a2
        api_key[a1] = a3
        emit_json()
        exit 0
    }
    if (op == "save_profile_with_env") {
        ensure_profile(a1)
        base_url[a1] = a2
        api_key[a1] = a3
        clear_env(a1)
        if (env_file != "") {
            while ((getline line < env_file) > 0) {
                t = index(line, "\t")
                if (t <= 0) continue
                k = substr(line, 1, t - 1)
                v = substr(line, t + 1)
                set_env(a1, k, v)
            }
            close(env_file)
        }
        emit_json()
        exit 0
    }
    if (op == "set_env_var") {
        if (!(a1 in profile_seen)) jerr("Profile not found: " a1)
        set_env(a1, a2, a3)
        emit_json()
        exit 0
    }
    if (op == "unset_env_var") {
        if (!(a1 in profile_seen)) jerr("Profile not found: " a1)
        if ((a1 SUBSEP a2) in env_seen) {
            delete env_seen[a1 SUBSEP a2]
            delete env_val[a1 SUBSEP a2]
            for (x = 1; x <= env_count[a1]; x++) {
                if (env_order[a1 SUBSEP x] == a2) {
                    delete env_order[a1 SUBSEP x]
                }
            }
            compact_env_order(a1)
        }
        emit_json()
        exit 0
    }
    if (op == "remove_profile") {
        remove_profile_internal(a1)
        emit_json()
        exit 0
    }

    jerr("Unknown JSON op: " op)
}
    ' "$file"
}

# 将写操作安全落盘
_json_apply_write() {
    local file="$1"
    local op="$2"
    local a1="${3:-}"
    local a2="${4:-}"
    local a3="${5:-}"
    local env_file="${6:-}"
    local tmp
    tmp=$(mktemp "${file}.tmp.XXXXXX")
    if ! _json_core "$file" "$op" "$a1" "$a2" "$a3" "$env_file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 600 "$tmp"
    mv "$tmp" "$file"
}

# 初始化配置文件
init_profiles() {
    if [[ ! -f "$PROFILES_FILE" ]]; then
        cat > "$PROFILES_FILE" << 'EOF'
{
  "current": "",
  "profiles": {}
}
EOF
        chmod 600 "$PROFILES_FILE"
    fi
}

# JSON 读取操作
_json_get_value() { _json_core "$1" "get_value" "$2"; }
_json_get_current() { _json_core "$1" "get_current"; }
_json_list_profiles() { _json_core "$1" "list_profiles"; }
_json_get_env_vars() { _json_core "$1" "get_env_vars" "$2"; }
_json_profile_exists() { _json_core "$1" "profile_exists" "$2" >/dev/null; }

# JSON 写入操作
_json_set_current() { _json_apply_write "$1" "set_current" "$2"; }
_json_save_profile() { _json_apply_write "$1" "save_profile" "$2" "$3" "$4"; }

# 使用数组名传入键值（兼容 bash 3.2）
_json_save_profile_with_env() {
    local file="$1"
    local profile="$2"
    local base_url="$3"
    local api_key="$4"
    local keys_name="$5"
    local values_name="$6"

    local env_tmp
    env_tmp=$(mktemp "${file}.env.XXXXXX")

    local keys_ref="${keys_name}[@]"
    local values_ref="${values_name}[@]"
    local keys=("${!keys_ref}")
    local values=("${!values_ref}")

    local i key value
    for ((i = 0; i < ${#keys[@]}; i++)); do
        key="${keys[i]}"
        value="${values[i]:-}"
        printf '%s\t%s\n' "$key" "$value" >> "$env_tmp"
    done

    if ! _json_apply_write "$file" "save_profile_with_env" "$profile" "$base_url" "$api_key" "$env_tmp"; then
        rm -f "$env_tmp"
        return 1
    fi
    rm -f "$env_tmp"
}

_json_set_env_var() { _json_apply_write "$1" "set_env_var" "$2" "$3" "$4"; }
_json_unset_env_var() { _json_apply_write "$1" "unset_env_var" "$2" "$3"; }
_json_remove_profile() { _json_apply_write "$1" "remove_profile" "$2"; }

# 从 JSON 读取指定 profile 的字段值
# 用法: get_profile_field <profile_name> <field_name>
get_profile_field() {
    local profile="$1"
    local field="$2"
    _json_get_value "$PROFILES_FILE" "profiles.${profile}.${field}"
}

# 获取 profile 的自定义环境变量（返回 key=value 格式，每行一个）
get_profile_env_vars() {
    local profile="$1"
    _json_get_env_vars "$PROFILES_FILE" "$profile"
}

# 读取当前 profile 名称
get_current_profile() {
    _json_get_current "$PROFILES_FILE"
}

# 检查 profile 是否存在
profile_exists() {
    local profile="$1"
    _json_profile_exists "$PROFILES_FILE" "$profile"
}

# API key 脱敏
mask_token() {
    local t="$1"
    local n=${#t}
    if [[ -z "$t" ]]; then
        echo "(not set)"
        return
    fi
    if (( n <= 8 )); then
        echo "[set] ****"
    else
        echo "[set] ${t:0:4}...${t:n-4:4}"
    fi
}

# 列出所有 profiles
list_profiles() {
    init_profiles

    local current
    current=$(get_current_profile)

    echo -e "${BLUE}Available profiles:${NC}"
    echo ""

    local profiles
    profiles=$(_json_list_profiles "$PROFILES_FILE")
    if [[ -z "$profiles" ]]; then
        echo -e "  ${YELLOW}No profiles configured${NC}"
        echo ""
        echo "  Add a profile with: ccp add <name>"
        echo ""
        return 0
    fi

    local profile
    while IFS= read -r profile; do
        [[ -z "$profile" ]] && continue
        local base_url env_vars env_count
        base_url=$(get_profile_field "$profile" "base_url")
        env_vars=$(get_profile_env_vars "$profile")
        env_count=0
        if [[ -n "$env_vars" ]]; then
            while IFS= read -r _; do
                [[ -n "$_" ]] && ((env_count++))
            done <<< "$env_vars"
        fi
        local env_info=""
        if (( env_count > 0 )); then
            env_info=" +${env_count} env vars"
        fi

        if [[ "$profile" == "$current" ]]; then
            echo -e "  ${GREEN}* $profile${NC} ($base_url)$env_info"
        else
            echo "    $profile ($base_url)$env_info"
        fi
    done <<< "$profiles"

    echo ""
}

# 显示当前状态
show_status() {
    init_profiles
    echo -e "${BLUE}Current configuration:${NC}"
    echo "  BASE_URL: ${ANTHROPIC_BASE_URL:-'(not set)'}"
    echo -n "  API_KEY: "
    mask_token "${ANTHROPIC_API_KEY:-${ANTHROPIC_AUTH_TOKEN:-}}"
    echo ""

    local current
    current=$(get_current_profile)
    if [[ -n "$current" ]]; then
        echo -e "  Profile: ${GREEN}$current${NC}"

        # 显示自定义环境变量
        local env_vars
        env_vars=$(get_profile_env_vars "$current")
        if [[ -n "$env_vars" ]]; then
            echo ""
            echo -e "${BLUE}Custom environment variables:${NC}"
            while IFS='=' read -r key value; do
                [[ -z "$key" ]] && continue
                if [[ "$key" == *"KEY"* || "$key" == *"TOKEN"* || "$key" == *"SECRET"* ]]; then
                    echo -n "  $key: "
                    mask_token "$value"
                else
                    echo "  $key: $value"
                fi
            done <<< "$env_vars"
        fi
    else
        echo -e "  Profile: ${YELLOW}(none)${NC}"
    fi
}

# 更新 current profile
update_current_profile() {
    local profile="$1"
    _json_set_current "$PROFILES_FILE" "$profile"
}

# 切换到指定 profile（输出 export 语句）
switch_profile() {
    local profile="$1"

    init_profiles

    if ! profile_exists "$profile"; then
        echo -e "${RED}Profile '$profile' not found${NC}" >&2
        echo "Use 'ccp list' to see available profiles" >&2
        echo "Use 'ccp add $profile' to create it" >&2
        return 1
    fi

    local base_url api_key
    base_url=$(get_profile_field "$profile" "base_url")
    api_key=$(get_profile_field "$profile" "api_key")

    if [[ -z "$base_url" || -z "$api_key" ]]; then
        echo -e "${RED}Profile '$profile' is incomplete${NC}" >&2
        return 1
    fi

    update_current_profile "$profile"

    # 输出核心 export 语句（全部做 shell 安全转义）
    echo "export ANTHROPIC_BASE_URL='$(_shell_quote "$base_url")'"
    echo "export ANTHROPIC_API_URL='$(_shell_quote "$base_url")'"
    echo "export ANTHROPIC_AUTH_TOKEN='$(_shell_quote "$api_key")'"
    echo "unset ANTHROPIC_API_KEY"

    # 输出自定义环境变量（输出边界再次校验 key）
    local env_vars env_count
    env_vars=$(get_profile_env_vars "$profile")
    env_count=0
    if [[ -n "$env_vars" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            if ! _is_valid_env_key "$key"; then
                echo -e "${YELLOW}Warning: skipped invalid env key '$key'${NC}" >&2
                continue
            fi
            echo "export $key='$(_shell_quote "$value")'"
            ((env_count++))
        done <<< "$env_vars"
    fi

    echo -e "${GREEN}Switched to profile: $profile${NC}" >&2
    echo "  BASE_URL: $base_url" >&2
    if [[ $env_count -gt 0 ]]; then
        echo "  Custom env vars: $env_count" >&2
    fi
}

# 添加新 profile（交互式）
add_profile() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        echo -e "${RED}Profile name required${NC}" >&2
        echo "Usage: ccp add <name>" >&2
        return 1
    fi

    init_profiles

    if profile_exists "$profile"; then
        echo -e "${YELLOW}Profile '$profile' already exists. Updating...${NC}" >&2
    fi

    echo -e "${BLUE}Adding profile: $profile${NC}"
    echo ""

    local base_url api_key
    read -r -p "Base URL: " base_url
    if [[ -z "$base_url" ]]; then
        echo -e "${RED}Base URL is required${NC}" >&2
        return 1
    fi

    read -r -s -p "API Key: " api_key
    echo ""
    if [[ -z "$api_key" ]]; then
        echo -e "${RED}API Key is required${NC}" >&2
        return 1
    fi

    # 收集自定义环境变量（使用普通数组，兼容 bash 3.2）
    echo ""
    echo -e "${CYAN}Custom environment variables (optional):${NC}"
    echo -e "  Enter in format: ${YELLOW}VAR_NAME=value${NC}"
    echo -e "  Press Enter with empty input to finish"
    echo ""

    local env_keys=()
    local env_values=()
    local env_count=0
    local env_input key value

    while true; do
        read -r -p "  Env var: " env_input
        if [[ -z "$env_input" ]]; then
            break
        fi
        if [[ "$env_input" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            if ! _is_valid_env_key "$key"; then
                echo -e "    ${RED}Invalid variable name: $key${NC}"
                continue
            fi

            # 去除值两端成对引号（保留中间空格）
            if [[ "$value" =~ ^\".*\"$ ]]; then
                value="${value:1:${#value}-2}"
            elif [[ "$value" =~ ^\'.*\'$ ]]; then
                value="${value:1:${#value}-2}"
            fi

            env_keys+=("$key")
            env_values+=("$value")
            ((env_count++))
            echo -e "    ${GREEN}Added: $key${NC}"
        else
            echo -e "    ${RED}Invalid format. Use: VAR_NAME=value${NC}"
        fi
    done

    # 直接按数组保存，避免空格值丢失
    _json_save_profile_with_env "$PROFILES_FILE" "$profile" "$base_url" "$api_key" env_keys env_values

    echo ""
    echo -e "${GREEN}Profile '$profile' saved${NC}"
    echo "  BASE_URL: $base_url"
    echo -n "  API_KEY: "
    mask_token "$api_key"
    if [[ $env_count -gt 0 ]]; then
        echo "  Custom env vars: $env_count"
    fi
}

# 设置单个环境变量
set_env_var() {
    local profile="$1"
    local key="$2"
    local value="${3:-}"

    if [[ -z "$profile" || -z "$key" ]]; then
        echo -e "${RED}Usage: ccp set-env <profile> <VAR_NAME> <value>${NC}" >&2
        return 1
    fi

    if ! _is_valid_env_key "$key"; then
        echo -e "${RED}Invalid variable name: $key${NC}" >&2
        return 1
    fi

    init_profiles
    if ! profile_exists "$profile"; then
        echo -e "${RED}Profile '$profile' not found${NC}" >&2
        return 1
    fi

    _json_set_env_var "$PROFILES_FILE" "$profile" "$key" "$value"
    echo "Set $key in profile '$profile'"
}

# 删除环境变量
unset_env_var() {
    local profile="$1"
    local key="$2"

    if [[ -z "$profile" || -z "$key" ]]; then
        echo -e "${RED}Usage: ccp unset-env <profile> <VAR_NAME>${NC}" >&2
        return 1
    fi

    if ! _is_valid_env_key "$key"; then
        echo -e "${RED}Invalid variable name: $key${NC}" >&2
        return 1
    fi

    init_profiles
    if ! profile_exists "$profile"; then
        echo -e "${RED}Profile '$profile' not found${NC}" >&2
        return 1
    fi

    _json_unset_env_var "$PROFILES_FILE" "$profile" "$key"
    echo "Removed $key from profile '$profile'"
}

# 显示 profile 的环境变量
show_env_vars() {
    local profile="${1:-}"

    if [[ -z "$profile" ]]; then
        profile=$(get_current_profile)
        if [[ -z "$profile" ]]; then
            echo -e "${RED}No profile specified and no current profile set${NC}" >&2
            return 1
        fi
    fi

    init_profiles
    if ! profile_exists "$profile"; then
        echo -e "${RED}Profile '$profile' not found${NC}" >&2
        return 1
    fi

    echo -e "${BLUE}Environment variables for profile '$profile':${NC}"
    echo ""

    local base_url api_key env_vars
    base_url=$(get_profile_field "$profile" "base_url")
    api_key=$(get_profile_field "$profile" "api_key")

    echo -e "${CYAN}Core variables:${NC}"
    echo "  ANTHROPIC_BASE_URL: $base_url"
    echo -n "  ANTHROPIC_API_KEY: "
    mask_token "$api_key"
    echo ""

    env_vars=$(get_profile_env_vars "$profile")
    if [[ -n "$env_vars" ]]; then
        echo -e "${CYAN}Custom variables:${NC}"
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            if [[ "$key" == *"KEY"* || "$key" == *"TOKEN"* || "$key" == *"SECRET"* ]]; then
                echo -n "  $key: "
                mask_token "$value"
            else
                echo "  $key: $value"
            fi
        done <<< "$env_vars"
    else
        echo -e "${YELLOW}No custom environment variables${NC}"
    fi
}

# 删除 profile
remove_profile() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        echo -e "${RED}Profile name required${NC}" >&2
        echo "Usage: ccp remove <name>" >&2
        return 1
    fi

    init_profiles
    if ! profile_exists "$profile"; then
        echo -e "${RED}Profile '$profile' not found${NC}" >&2
        return 1
    fi

    _json_remove_profile "$PROFILES_FILE" "$profile"
    echo -e "${GREEN}Profile '$profile' removed${NC}"
}

# 编辑配置文件
edit_config() {
    init_profiles

    echo -e "${BLUE}Opening config file...${NC}"
    echo "  Path: $PROFILES_FILE"

    if command -v cursor >/dev/null 2>&1; then
        cursor "$PROFILES_FILE" &
    elif command -v code >/dev/null 2>&1; then
        code "$PROFILES_FILE" &
    elif [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1; then
        open "$PROFILES_FILE"
    elif command -v vim >/dev/null 2>&1; then
        vim "$PROFILES_FILE"
    elif command -v nano >/dev/null 2>&1; then
        nano "$PROFILES_FILE"
    else
        echo -e "${RED}No editor found${NC}" >&2
        echo "Edit manually: $PROFILES_FILE" >&2
        return 1
    fi
}

# 移除 settings.json 顶层 env 字段（纯 awk）
_strip_top_level_env() {
    local file="$1"
    awk '
function jerr(msg) { print msg > "/dev/stderr"; exit 3 }
function skip_ws(  c) { while (i <= L) { c = substr(S, i, 1); if (c ~ /[ \t\r\n]/) i++; else break } }
function expect(ch,  c) { skip_ws(); c = substr(S, i, 1); if (c != ch) jerr("JSON parse error: expected " ch " at pos " i); i++ }
function parse_string(  c, n, hex, out) {
    skip_ws(); if (substr(S, i, 1) != "\"") jerr("JSON parse error: expected string at pos " i)
    i++; out = ""
    while (i <= L) {
        c = substr(S, i, 1)
        if (c == "\"") { i++; return out }
        if (c == "\\") {
            i++; if (i > L) jerr("JSON parse error: bad escape")
            n = substr(S, i, 1)
            if (n == "\"" || n == "\\" || n == "/") out = out n
            else if (n == "b") out = out sprintf("%c", 8)
            else if (n == "f") out = out sprintf("%c", 12)
            else if (n == "n") out = out "\n"
            else if (n == "r") out = out "\r"
            else if (n == "t") out = out "\t"
            else if (n == "u") {
                hex = substr(S, i + 1, 4)
                if (hex ~ /^[0-9A-Fa-f]{4}$/) { out = out "\\u" hex; i += 4 }
                else jerr("JSON parse error: bad unicode escape")
            } else jerr("JSON parse error: unknown escape")
            i++
        } else {
            out = out c; i++
        }
    }
    jerr("JSON parse error: unterminated string")
}
function parse_token(  st, c) {
    skip_ws(); st = i
    while (i <= L) { c = substr(S, i, 1); if (c ~ /[ \t\r\n,}\]]/) break; i++ }
    return substr(S, st, i - st)
}
function skip_value(  c) {
    skip_ws(); c = substr(S, i, 1)
    if (c == "\"") { parse_string(); return }
    if (c == "{") { skip_object(); return }
    if (c == "[") { skip_array(); return }
    parse_token()
}
function skip_object(  c, k) {
    expect("{"); skip_ws(); c = substr(S, i, 1)
    if (c == "}") { i++; return }
    while (1) {
        k = parse_string(); expect(":"); skip_value()
        skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "}") { i++; break }
        jerr("JSON parse error: bad object separator at pos " i)
    }
}
function skip_array(  c) {
    expect("["); skip_ws(); c = substr(S, i, 1)
    if (c == "]") { i++; return }
    while (1) {
        skip_value(); skip_ws(); c = substr(S, i, 1)
        if (c == ",") { i++; continue }
        if (c == "]") { i++; break }
        jerr("JSON parse error: bad array separator at pos " i)
    }
}
function capture_raw_value(  st) { skip_ws(); st = i; skip_value(); return substr(S, st, i - st) }
function jesc(s,   out, c, x) {
    out = ""
    for (x = 1; x <= length(s); x++) {
        c = substr(s, x, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c == "\n") out = out "\\n"
        else if (c == "\r") out = out "\\r"
        else if (c == "\t") out = out "\\t"
        else out = out c
    }
    return out
}
BEGIN { S = ""; i = 1; removed = 0; kept = 0 }
{ S = S $0 "\n" }
END {
    L = length(S)
    skip_ws()
    expect("{")
    skip_ws()
    c = substr(S, i, 1)
    if (c != "}") {
        while (1) {
            k = parse_string()
            expect(":")
            v = capture_raw_value()
            if (k == "env") {
                removed = 1
            } else {
                kept++
                keys[kept] = k
                vals[kept] = v
            }
            skip_ws()
            c = substr(S, i, 1)
            if (c == ",") { i++; continue }
            if (c == "}") break
            jerr("JSON parse error: bad top-level separator at pos " i)
        }
    }

    if (!removed) {
        print "NO_ENV"
        exit 0
    }

    print "CHANGED"
    print "{"
    for (x = 1; x <= kept; x++) {
        comma = (x < kept) ? "," : ""
        print "  \"" jesc(keys[x]) "\": " vals[x] comma
    }
    print "}"
}
    ' "$file"
}

# 初始化：清除 ~/.claude/settings.json 中的 env 字段
# 这是为了解决 Claude Code 的 bug：settings.json 的 env 可能覆盖 shell 环境变量
init_claude_env() {
    local settings_file="$HOME/.claude/settings.json"

    if [[ ! -f "$settings_file" ]]; then
        echo -e "${YELLOW}No ~/.claude/settings.json found${NC}"
        echo "Nothing to do."
        return 0
    fi

    local tmp
    tmp=$(mktemp "${settings_file}.tmp.XXXXXX")

    if ! _strip_top_level_env "$settings_file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    local status
    status=$(sed -n '1p' "$tmp")
    if [[ "$status" == "NO_ENV" ]]; then
        rm -f "$tmp"
        echo -e "${YELLOW}No env field in ~/.claude/settings.json${NC}"
        echo "Already ready to use shell environment variables."
        return 0
    fi

    if [[ "$status" != "CHANGED" ]]; then
        rm -f "$tmp"
        echo -e "${RED}Unexpected init result${NC}" >&2
        return 1
    fi

    # 去掉第一行状态标记，保留 JSON 主体
    sed '1d' "$tmp" | _atomic_write "$settings_file"
    rm -f "$tmp"

    echo -e "${GREEN}✓ Cleared env from ~/.claude/settings.json${NC}"
    echo ""
    echo "Now Claude Code will use shell environment variables."
    echo "Use 'ccp <profile>' or 'ccc <profile>' to switch configurations."
}

# 显示帮助
show_help() {
    echo -e "${BLUE}Claude Code Profile Switcher (CCP) v2.0.0${NC}"
    echo ""
    echo "Usage: ccp <command> [args]"
    echo ""
    echo -e "${CYAN}Profile Management:${NC}"
    echo "  <profile>           Switch to specified profile (output export statements)"
    echo "  add <name>          Add or update a profile (interactive)"
    echo "  remove <name>       Remove a profile"
    echo "  list, ls            List all profiles"
    echo "  status, st          Show current configuration"
    echo "  edit                Open config file in editor"
    echo ""
    echo -e "${CYAN}Environment Variables:${NC}"
    echo "  set-env <profile> <VAR> <value>   Set custom env var for profile"
    echo "  unset-env <profile> <VAR>         Remove custom env var from profile"
    echo "  show-env [profile]                Show all env vars for profile"
    echo ""
    echo -e "${CYAN}Other:${NC}"
    echo "  init                Initialize: clear env from ~/.claude/settings.json"
    echo "  help, -h            Show this help"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  eval \"\$(ccp work)\"              # Switch to 'work' profile"
    echo "  ccp add staging                  # Add new profile (interactive)"
    echo "  ccp set-env work MODEL claude-4  # Set custom env var"
    echo "  ccp show-env work                # Show profile's env vars"
    echo "  ccp list                         # List all profiles"
    echo ""
    echo -e "${YELLOW}Config file format:${NC}"
    echo "  {\"profiles\": {\"name\": {\"base_url\": \"...\", \"api_key\": \"...\", \"env\": {...}}}}"
    echo ""
    echo "Config file: $PROFILES_FILE"
}

# 主函数
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        "add")
            shift
            add_profile "$@"
            ;;
        "remove"|"rm"|"delete")
            shift
            remove_profile "$@"
            ;;
        "list"|"ls")
            list_profiles
            ;;
        "status"|"st")
            show_status
            ;;
        "edit")
            edit_config
            ;;
        "set-env")
            shift
            set_env_var "$@"
            ;;
        "unset-env")
            shift
            unset_env_var "$@"
            ;;
        "show-env")
            shift
            show_env_vars "$@"
            ;;
        "init")
            init_claude_env
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            # 尝试作为 profile 名称切换
            switch_profile "$cmd"
            ;;
    esac
}

main "$@"
