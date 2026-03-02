#!/bin/bash
# Claude Code Profile Switcher (CCP) 2.0
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

# Shell 安全单引号转义
shell_quote() {
    local s="$1"
    s=${s//\'/\'"\'"\'}
    printf '%s' "$s"
}

#############################################
# .env 文件操作
#############################################

# 读取 .env 文件并输出 export 语句
# 成功返回 0，失败返回 1
read_env_file() {
    local profile="$1"
    local env_file="${CCP_PROFILES_DIR}/${profile}.env"
    
    if [[ ! -f "${env_file}" ]]; then
        return 1
    fi
    
    # 验证必需字段
    local has_base_url=0 has_token=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        [[ "$line" == ANTHROPIC_BASE_URL=* ]] && has_base_url=1
        [[ "$line" == ANTHROPIC_AUTH_TOKEN=* ]] && has_token=1
    done < "${env_file}"
    
    if (( !has_base_url || !has_token )); then
        die "Missing required fields in ${env_file}"
    fi
    
    # 输出 export 语句
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" != *=* ]] && continue
        
        local key value
        key="${line%%=*}"
        value="${line#*=}"
        
        # 验证 key
        if ! is_valid_env_key "$key"; then
            warn "Invalid key '${key}' skipped"
            continue
        fi
        
        echo "export ${key}='$(shell_quote "$value")'"
    done < "${env_file}"
    
    # 始终 unset ANTHROPIC_API_KEY
    echo "unset ANTHROPIC_API_KEY"
    
    return 0
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

#############################################
# Init 命令
#############################################

cmd_init() {
    local settings_dir="${HOME}/.claude"
    local backup_dir="${settings_dir}/backups"
    local settings_file="${settings_dir}/settings.json"
    local max_backups=5
    
    info "Initializing Claude Code settings..."
    
    # 确保目录存在
    mkdir -p "${settings_dir}"
    mkdir -p "${backup_dir}"
    
    # 如果存在 settings.json，备份它
    if [[ -f "${settings_file}" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${backup_dir}/settings.json.${timestamp}"
        
        mv "${settings_file}" "${backup_file}"
        chmod 600 "${backup_file}"
        success "Backed up settings to: ${backup_file}"
    fi
    
    # 创建新的空 settings.json
    echo '{}' | atomic_write "${settings_file}"
    success "Created new settings.json"
    
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
    info "Use 'ccp2 add <profile>' to create a profile."
    info "Use 'ccp2 <profile>' to switch profiles."
}

#############################################
# Profile 命令
#############################################

cmd_add() {
    local profile="${1:-}"
    
    if [[ -z "$profile" ]]; then
        die "Profile name required. Usage: ccp2 add <name>"
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
    
    [[ -z "$profile" ]] && die "Profile name required. Usage: ccp2 remove <name>"
    
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
        echo "  Add a profile with: ccp2 add <name>"
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
        echo -e "  Current profile: ${YELLOW}none${NC}"
    else
        echo -e "  Current profile: ${GREEN}${current}${NC}"
        
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

cmd_switch() {
    local profile="${1:-}"
    
    [[ -z "$profile" ]] && die "Profile name required"
    
    if ! profile_exists "$profile"; then
        die "Profile '${profile}' does not exist. Use 'ccp2 list' to see available profiles."
    fi
    
    # 读取并输出 export 语句
    if ! read_env_file "$profile"; then
        die "Failed to read profile '${profile}'"
    fi
    
    # 更新 current
    set_current_profile "$profile"
    
    # 输出状态到 stderr
    echo -e "${GREEN}Switched to profile: ${profile}${NC}" >&2
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
Claude Code Profile Switcher (CCP) 2.0

USAGE:
    ccp2 <profile>              Switch to specified profile
    ccp2 add <name>             Add a new profile (interactive)
    ccp2 remove <name>          Remove a profile
    ccp2 list                   List all profiles
    ccp2 status                 Show current status
    ccp2 set-env <profile> <VAR> <value>   Set custom env var
    ccp2 unset-env <profile> <VAR>         Remove custom env var
    ccp2 show-env <profile>       Show env vars for profile
    ccp2 init                   Initialize Claude Code settings
    ccp2 help                   Show this help

CONFIG LOCATION:
    ~/.ccp/profiles/            Profile .env files
    ~/.ccp/current              Current profile name

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
            # 尝试作为 profile 名切换
            if is_valid_profile_name "$cmd"; then
                cmd_switch "$cmd"
            else
                die "Unknown command: $cmd. Use 'ccp2 help' for usage."
            fi
            ;;
    esac
}

main "$@"
