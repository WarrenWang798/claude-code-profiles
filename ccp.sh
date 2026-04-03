#!/bin/bash
# Claude Code Profile Switcher (CCP) 3.0
# Pure .env file based configuration management
# Bash 3.2+ compatible, zero external dependencies

set -euo pipefail

#############################################
# 颜色定义
#############################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#############################################
# 路径常量
#############################################
CCP_DIR="${HOME}/.ccp"
CCP_PROFILES_DIR="${CCP_DIR}/profiles"
CCP_CURRENT_FILE="${CCP_DIR}/current"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

#############################################
# 基础工具函数
#############################################

# 错误退出
die() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# 警告
warn() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

# 信息
info() {
    echo -e "${BLUE}→ $1${NC}"
}

# 成功
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 确保目录存在（带权限）
ensure_dirs() {
    if [[ ! -d "${CCP_PROFILES_DIR}" ]]; then
        mkdir -p "${CCP_PROFILES_DIR}"
        chmod 700 "${CCP_DIR}"
        chmod 700 "${CCP_PROFILES_DIR}"
    fi
}

# 原子写入文件
atomic_write() {
    local target="$1"
    local tmp
    tmp=$(mktemp "${target}.tmp.XXXXXX")
    cat > "${tmp}"
    chmod 600 "${tmp}"
    mv "${tmp}" "${target}"
}

# 验证环境变量名是否合法
is_valid_env_key() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# 验证 profile 名是否合法
is_valid_profile_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# 写入 .env 文件
write_env_file() {
    local profile="$1"
    local base_url="$2"
    local auth_token="$3"
    shift 3
    local custom_vars=("$@")
    
    local env_file="${CCP_PROFILES_DIR}/${profile}.env"
    local tmp
    tmp=$(mktemp "${env_file}.tmp.XXXXXX")
    
    {
        echo "# CCP Profile: ${profile}"
        echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "ANTHROPIC_BASE_URL=${base_url}"
        echo "ANTHROPIC_AUTH_TOKEN=${auth_token}"
        
        if (( ${#custom_vars[@]} > 0 )); then
            echo "# Custom env vars"
            printf '%s\n' "${custom_vars[@]}"
        fi
    } > "${tmp}"
    
    chmod 600 "${tmp}"
    mv "${tmp}" "${env_file}"
}

# 获取 env 文件路径
env_file_path() {
    local profile="$1"
    echo "${CCP_PROFILES_DIR}/${profile}.env"
}

#############################################
# Profile 管理
#############################################

# 检查 profile 是否存在
profile_exists() {
    local profile="$1"
    [[ -f "$(env_file_path "$profile")" ]]
}

# 获取当前 profile
get_current_profile() {
    if [[ -f "${CCP_CURRENT_FILE}" ]]; then
        cat "${CCP_CURRENT_FILE}"
    else
        echo ""
    fi
}

# 设置当前 profile
set_current_profile() {
    local profile="$1"
    echo "$profile" | atomic_write "${CCP_CURRENT_FILE}"
}

# 重写 settings.json，删除顶层 env 键
rewrite_settings_without_env() {
    local input_file="$1"
    local output_file="$2"

    awk '
        function skip_ws(pos,    ch) {
            while (pos <= len) {
                ch = substr(json, pos, 1)
                if (ch !~ /[[:space:]]/) {
                    break
                }
                pos++
            }
            return pos
        }

        function parse_string(pos,    ch, out, escape) {
            if (substr(json, pos, 1) != "\"") {
                return 0
            }

            out = ""
            escape = 0
            pos++

            while (pos <= len) {
                ch = substr(json, pos, 1)
                if (escape) {
                    out = out ch
                    escape = 0
                } else if (ch == "\\") {
                    escape = 1
                } else if (ch == "\"") {
                    parsed_string = out
                    return pos
                } else {
                    out = out ch
                }
                pos++
            }

            return 0
        }

        function parse_value(pos,    ch, brace_depth, bracket_depth, in_string, escape) {
            ch = substr(json, pos, 1)
            if (ch == "\"") {
                return parse_string(pos)
            }

            if (ch != "{" && ch != "[") {
                while (pos <= len) {
                    ch = substr(json, pos, 1)
                    if (ch == "," || ch == "}") {
                        return pos - 1
                    }
                    pos++
                }
                return len
            }

            brace_depth = 0
            bracket_depth = 0
            in_string = 0
            escape = 0

            while (pos <= len) {
                ch = substr(json, pos, 1)

                if (in_string) {
                    if (escape) {
                        escape = 0
                    } else if (ch == "\\") {
                        escape = 1
                    } else if (ch == "\"") {
                        in_string = 0
                    }
                    pos++
                    continue
                }

                if (ch == "\"") {
                    in_string = 1
                    pos++
                    continue
                }

                if (ch == "{") {
                    brace_depth++
                } else if (ch == "}") {
                    brace_depth--
                } else if (ch == "[") {
                    bracket_depth++
                } else if (ch == "]") {
                    bracket_depth--
                }

                if (brace_depth < 0 || bracket_depth < 0) {
                    return 0
                }

                if (brace_depth == 0 && bracket_depth == 0) {
                    return pos
                }

                pos++
            }

            return 0
        }

        BEGIN {
            json = ""
            parsed_string = ""
        }

        {
            json = json $0 ORS
        }

        END {
            len = length(json)
            start = skip_ws(1)
            if (start > len || substr(json, start, 1) != "{") {
                exit 1
            }

            finish = len
            while (finish > start && substr(json, finish, 1) ~ /[[:space:]]/) {
                finish--
            }

            if (substr(json, finish, 1) != "}") {
                exit 1
            }

            pos = start + 1
            kept_count = 0

            while (1) {
                pos = skip_ws(pos)
                if (pos > finish) {
                    exit 1
                }

                ch = substr(json, pos, 1)
                if (ch == "}") {
                    pos++
                    break
                }

                member_start = pos
                key_end = parse_string(pos)
                if (!key_end) {
                    exit 1
                }

                key = parsed_string
                pos = skip_ws(key_end + 1)
                if (substr(json, pos, 1) != ":") {
                    exit 1
                }

                pos = skip_ws(pos + 1)
                value_end = parse_value(pos)
                if (!value_end) {
                    exit 1
                }

                if (key != "env") {
                    kept_count++
                    kept_members[kept_count] = substr(json, member_start, value_end - member_start + 1)
                }

                pos = skip_ws(value_end + 1)
                ch = substr(json, pos, 1)
                if (ch == ",") {
                    pos++
                    continue
                }
                if (ch == "}") {
                    pos++
                    break
                }
                exit 1
            }

            output = substr(json, 1, start - 1) "{"
            for (i = 1; i <= kept_count; i++) {
                if (i > 1) {
                    output = output ","
                }
                output = output kept_members[i]
            }
            output = output "}" substr(json, finish + 1)
            printf "%s", output
        }
    ' "${input_file}" > "${output_file}"
}

#############################################
# Init 命令
#############################################

cmd_init() {
    local settings_dir="${HOME}/.claude"
    local backup_dir="${settings_dir}/backups"
    local settings_file="${settings_dir}/settings.json"
    local max_backups=5
    local tmp_file
    
    info "Initializing Claude Code settings..."
    
    # 确保目录存在
    mkdir -p "${settings_dir}"
    mkdir -p "${backup_dir}"
    
    # 如果存在 settings.json，备份并精准删除顶层 env
    if [[ -f "${settings_file}" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${backup_dir}/settings.json.${timestamp}"
        
        cp "${settings_file}" "${backup_file}"
        chmod 600 "${backup_file}"
        success "Backed up settings to: ${backup_file}"

        tmp_file=$(mktemp "${settings_file}.tmp.XXXXXX")
        if ! rewrite_settings_without_env "${settings_file}" "${tmp_file}"; then
            rm -f "${tmp_file}"
            die "Failed to rewrite ${settings_file}. Only valid JSON objects are supported."
        fi

        chmod 600 "${tmp_file}"
        mv "${tmp_file}" "${settings_file}"
        success "Removed top-level env from settings.json"
    else
        echo '{}' | atomic_write "${settings_file}"
        success "Created new settings.json"
    fi
    
    # 清理旧备份（保留最近 5 个）
    local backups
    backups=($(ls -t "${backup_dir}"/settings.json.* 2>/dev/null))
    if (( ${#backups[@]} > max_backups )); then
        for ((i = max_backups; i < ${#backups[@]}; i++)); do
            rm -f "${backup_dir}/${backups[i]}"
        done
        info "Cleaned up old backups (kept ${max_backups})"
    fi
    
    success "Initialization complete!"
    echo ""
    info "Claude Code will now use shell environment variables."
    info "Use 'ccp add <profile>' to create a profile."
    info "Use 'ccc <profile>' to launch Claude Code with a profile."
}

#############################################
# Profile 命令
#############################################

cmd_add() {
    local profile="${1:-}"
    
    if [[ -z "$profile" ]]; then
        die "Profile name required. Usage: ccp add <name>"
    fi
    
    if ! is_valid_profile_name "$profile"; then
        die "Invalid profile name. Use only: A-Z, a-z, 0-9, ., _, -"
    fi
    
    ensure_dirs
    
    if profile_exists "$profile"; then
        warn "Profile '${profile}' already exists. Will update."
        read -p "Continue? (y/N) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || return 1
    fi
    
    local base_url api_key
    
    # 读取 base_url
    echo ""
    read -p "Base URL: " base_url
    [[ -z "$base_url" ]] && die "Base URL is required"
    
    # 读取 api_key (隐藏输入)
    echo ""
    read -sp "API Key: " api_key
    echo
    [[ -z "$api_key" ]] && die "API Key is required"
    
    # 创建 .env 文件
    write_env_file "$profile" "$base_url" "$api_key"
    
    # 设置为当前 profile
    set_current_profile "$profile"
    
    echo ""
    success "Profile '${profile}' created and activated"
}

cmd_remove() {
    local profile="${1:-}"
    
    [[ -z "$profile" ]] && die "Profile name required. Usage: ccp remove <name>"
    
    if ! profile_exists "$profile"; then
        die "Profile '${profile}' does not exist"
    fi
    
    local current
    current=$(get_current_profile)
    
    echo ""
    read -p "Remove profile '${profile}'? (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || return 1
    
    rm -f "$(env_file_path "$profile")"
    
    # 如果删除的是当前 profile，清除 current
    if [[ "$current" == "$profile" ]]; then
        rm -f "${CCP_CURRENT_FILE}"
    fi
    
    success "Profile '${profile}' removed"
}

cmd_list() {
    ensure_dirs
    
    local current
    current=$(get_current_profile)
    
    echo ""
    echo -e "${BLUE}Available profiles:${NC}"
    echo ""
    
    local found=0
    local env_file profile
    
    for env_file in "${CCP_PROFILES_DIR}"/*.env; do
        [[ -f "$env_file" ]] || continue
        found=1
        profile=$(basename "$env_file" .env)
        
        # 读取 base_url
        local base_url
        base_url=$(grep "^ANTHROPIC_BASE_URL=" "$env_file" | cut -d= -f2- || echo "")
        
        # 检查是否为当前 profile
        if [[ "$profile" == "$current" ]]; then
            echo -e "  ${GREEN}* ${profile}${NC} (${base_url:-no url})"
        else
            echo -e "    ${profile} (${base_url:-no url})"
        fi
    done
    
    if (( !found )); then
        echo -e "  ${YELLOW}No profiles configured${NC}"
        echo ""
        echo "  Add a profile with: ccp add <name>"
    fi
    
    echo ""
}

cmd_status() {
    ensure_dirs
    
    local current
    current=$(get_current_profile)
    
    echo ""
    echo -e "${BLUE}CCP Status${NC}"
    echo ""
    
    if [[ -z "$current" ]]; then
        echo -e "  Last launched profile: ${YELLOW}none${NC}"
    else
        echo -e "  Last launched profile: ${GREEN}${current}${NC}"
        
        local env_file
        env_file=$(env_file_path "$current")
        
        if [[ -f "$env_file" ]]; then
            local base_url
            base_url=$(grep "^ANTHROPIC_BASE_URL=" "$env_file" | cut -d= -f2- || echo "")
            echo "  Base URL: ${base_url:-not set}"
        fi
    fi
    
    # 统计 profile 数量
    local count=0
    for f in "${CCP_PROFILES_DIR}"/*.env; do
        [[ -f "$f" ]] && ((count++))
    done
    
    echo "  Total profiles: ${count}"
    echo "  Config directory: ${CCP_DIR}"
    echo ""
}

cmd_set_env() {
    local profile="${1:-}"
    local var="${2:-}"
    local value="${3:-}"
    
    [[ -z "$profile" ]] && die "Profile name required"
    [[ -z "$var" ]] && die "Variable name required"
    [[ -z "$value" ]] && die "Variable value required"
    
    if ! profile_exists "$profile"; then
        die "Profile '${profile}' does not exist"
    fi
    
    # 验证变量名
    if ! is_valid_env_key "$var"; then
        die "Invalid variable name '${var}'. Must match: [A-Za-z_][A-Za-z0-9_]*"
    fi
    
    local env_file
    env_file=$(env_file_path "$profile")
    
    # 读取现有内容，替换或添加变量
    local tmp_file
    tmp_file=$(mktemp "${env_file}.tmp.XXXXXX")
    
    local found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            # 保留注释
            echo "$line"
        elif [[ "$line" =~ ^"${var}"= ]]; then
            # 替换现有变量
            echo "${var}=${value}"
            found=1
        else
            echo "$line"
        fi
    done < "${env_file}" > "${tmp_file}"
    
    # 如果没有找到，在末尾添加
    if (( !found )); then
        echo "${var}=${value}" >> "${tmp_file}"
    fi
    
    chmod 600 "${tmp_file}"
    mv "${tmp_file}" "${env_file}"
    
    success "Set ${var}=${value} in profile '${profile}'"
}

cmd_unset_env() {
    local profile="${1:-}"
    local var="${2:-}"
    
    [[ -z "$profile" ]] && die "Profile name required"
    [[ -z "$var" ]] && die "Variable name required"
    
    if ! profile_exists "$profile"; then
        die "Profile '${profile}' does not exist"
    fi
    
    local env_file
    env_file=$(env_file_path "$profile")
    
    # 读取并过滤掉指定变量
    local tmp_file
    tmp_file=$(mktemp "${env_file}.tmp.XXXXXX")
    
    local found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ ! "$line" =~ ^"${var}"= ]]; then
            echo "$line"
        else
            found=1
        fi
    done < "${env_file}" > "${tmp_file}"
    
    chmod 600 "${tmp_file}"
    mv "${tmp_file}" "${env_file}"
    
    if (( found )); then
        success "Removed ${var} from profile '${profile}'"
    else
        warn "Variable '${var}' not found in profile '${profile}'"
    fi
}

cmd_show_env() {
    local profile="${1:-}"
    
    [[ -z "$profile" ]] && die "Profile name required"
    
    if ! profile_exists "$profile"; then
        die "Profile '${profile}' does not exist"
    fi
    
    local env_file
    env_file=$(env_file_path "$profile")
    
    echo ""
    echo -e "${BLUE}Environment variables for profile: ${profile}${NC}"
    echo ""
    
    local has_vars=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" != *=* ]] && continue
        
        local key value
        key="${line%%=*}"
        value="${line#*=}"
        
        has_vars=1
        
        # 掩码显示 API key
        if [[ "$key" == "ANTHROPIC_AUTH_TOKEN" ]]; then
            local masked
            masked=$(echo "${value:0:4}****${value: -4}")
            echo "  ${key}=${masked}"
        else
            echo "  ${key}=${value}"
        fi
    done < "${env_file}"
    
    if (( !has_vars )); then
        echo "  (none)"
    fi
    
    echo ""
}

#############################################
# 主命令分发
#############################################

show_help() {
    cat << 'EOF'
Claude Code Profile Switcher (CCP) 3.0.0

USAGE:
    ccp add <name>             Add a new profile (interactive)
    ccp remove <name>          Remove a profile
    ccp list                   List all profiles
    ccp status                 Show current status
    ccp set-env <profile> <VAR> <value>   Set custom env var
    ccp unset-env <profile> <VAR>         Remove custom env var
    ccp show-env <profile>     Show env vars for profile
    ccp init                   Initialize Claude Code settings
    ccc <profile>              Launch Claude Code with profile
    ccp help                   Show this help

CONFIG LOCATION:
    ~/.ccp/profiles/            Profile .env files
    ~/.ccp/current              Last launched profile name

ENV FILE FORMAT:
    # CCP Profile: <name>
    ANTHROPIC_BASE_URL=<url>
    ANTHROPIC_AUTH_TOKEN=<key>
    # Custom env vars
    CUSTOM_VAR=value
EOF
}

main() {
    local cmd="${1:-help}"
    
    case "$cmd" in
        help|-h|--help)
            show_help
            ;;
        add)
            shift
            cmd_add "$@"
            ;;
        remove|rm)
            shift
            cmd_remove "$@"
            ;;
        list|ls)
            cmd_list
            ;;
        status|st)
            cmd_status
            ;;
        set-env)
            shift
            cmd_set_env "$@"
            ;;
        unset-env)
            shift
            cmd_unset_env "$@"
            ;;
        show-env)
            shift
            cmd_show_env "$@"
            ;;
        init)
            cmd_init
            ;;
        *)
            die "Unknown command: ${cmd}. Use 'ccp help' for usage."
            ;;
    esac
}

main "$@"
