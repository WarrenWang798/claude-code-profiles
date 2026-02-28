#!/usr/bin/env bash
set -euo pipefail

# Claude Code Profile Switcher (CCP) — 安装脚本
# 支持两种安装方式:
#   本地: git clone 后运行 ./install.sh
#   远程: curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
#
# 环境变量:
#   CCP_DIR     — 自定义安装目录（默认 ~/.local/share/ccp）
#   CCP_REPO    — 自定义 GitHub 仓库（默认 WarrenWang798/claude-code-profiles）
#   CCP_BRANCH  — 自定义分支（默认 main）

CCP_VERSION="2.0.0"

# GitHub 仓库信息（用户可通过环境变量覆盖）
REPO="${CCP_REPO:-WarrenWang798/claude-code-profiles}"
BRANCH="${CCP_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

INSTALL_DIR="${CCP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ccp}"
DEST_SCRIPT_PATH="$INSTALL_DIR/ccp.sh"
BEGIN_MARK="# >>> ccp function begin >>>"
END_MARK="# <<< ccp function end <<<"

# 检测本地是否有 ccp.sh（判断是本地安装还是远程安装）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
LOCAL_CCP="${SCRIPT_DIR:+$SCRIPT_DIR/ccp.sh}"
IS_LOCAL=false
if [[ -n "$LOCAL_CCP" && -f "$LOCAL_CCP" ]]; then
    IS_LOCAL=true
fi

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}==>${NC} $1"; }
ok()    { echo -e "${GREEN}✅${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠️${NC}  $1"; }
fail()  { echo -e "${RED}❌${NC} $1" >&2; exit 1; }

# 检测下载工具
detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        echo "curl"
    elif command -v wget >/dev/null 2>&1; then
        echo "wget"
    else
        fail "curl 或 wget 未找到，请先安装其中之一"
    fi
}

# 下载文件
download() {
    local url="$1"
    local dest="$2"
    local downloader
    downloader=$(detect_downloader)

    case "$downloader" in
        curl) curl -fsSL "$url" -o "$dest" ;;
        wget) wget -qO "$dest" "$url" ;;
    esac
}

# 检测 shell rc 文件
detect_rc_file() {
    local shell_name="${SHELL##*/}"
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash)
            # macOS 默认 login shell 读 .bash_profile，非 login 读 .bashrc
            if [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)    echo "$HOME/.zshrc" ;;
    esac
}

# 移除已有的 ccp 函数块
remove_existing_block() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if grep -qF "$BEGIN_MARK" "$rc"; then
        local tmp
        tmp="$(mktemp)"
        awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
            $0==b {inblock=1; next}
            $0==e {inblock=0; next}
            !inblock {print}
        ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    fi
}

# 追加 shell 函数块
append_function_block() {
    local rc="$1"
    mkdir -p "$(dirname "$rc")"
    [[ -f "$rc" ]] || touch "$rc"
    cat >> "$rc" << 'BLOCK_EOF'
# >>> ccp function begin >>>
# CCP: Claude Code Profile Switcher
unalias ccp 2>/dev/null || true
unset -f ccp 2>/dev/null || true
ccp() {
    local script="${CCP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ccp}/ccp.sh"
    if [[ ! -f "$script" ]]; then
        echo "ccp error: script not found at $script" >&2
        return 1
    fi

    case "$1" in
        ""|"help"|"-h"|"--help"|"status"|"st"|"list"|"ls"|"add"|"remove"|"rm"|"delete"|"edit"|"set-env"|"unset-env"|"show-env"|"init")
            "$script" "$@"
            ;;
        *)
            eval "$("$script" "$@")"
            ;;
    esac
}

# CCC: Switch profile and launch Claude Code
unalias ccc 2>/dev/null || true
unset -f ccc 2>/dev/null || true
ccc() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: ccc <profile> [claude-options]"
        echo ""
        echo "Examples:"
        echo "  ccc work              # Launch with 'work' profile"
        echo "  ccc personal          # Launch with 'personal' profile"
        echo ""
        echo "Use 'ccp list' to see available profiles"
        return 1
    fi

    local profile="$1"
    shift

    # Switch profile
    ccp "$profile" || return 1

    echo ""
    echo "🚀 Launching Claude Code..."
    echo "   Profile: $profile"
    echo "   Base URL: ${ANTHROPIC_BASE_URL:-'(not set)'}"
    echo ""

    if ! command -v claude >/dev/null 2>&1; then
        echo "❌ 'claude' CLI not found. Install: npm install -g @anthropic-ai/claude-code" >&2
        return 127
    fi

    if [[ $# -eq 0 ]]; then
        exec claude
    else
        exec claude "$@"
    fi
}
# <<< ccp function end <<<
BLOCK_EOF
}

main() {
    echo ""
    echo -e "${BLUE}Claude Code Profile Switcher (CCP) v${CCP_VERSION}${NC}"
    echo ""

    # 1. 创建安装目录
    mkdir -p "$INSTALL_DIR"

    # 2. 获取 ccp.sh
    if [[ "$IS_LOCAL" == "true" ]]; then
        info "本地安装 (从 $SCRIPT_DIR)"
        cp -f "$LOCAL_CCP" "$DEST_SCRIPT_PATH"
    else
        info "远程安装 (从 github.com/${REPO})"
        download "${RAW_BASE}/ccp.sh" "$DEST_SCRIPT_PATH"
    fi
    chmod +x "$DEST_SCRIPT_PATH"

    # 3. 注入 shell 函数
    local rc
    rc="$(detect_rc_file)"
    remove_existing_block "$rc"
    append_function_block "$rc"

    # 4. 完成
    echo ""
    ok "已安装 ccp 和 ccc 函数到: $rc"
    echo "   脚本位置: $DEST_SCRIPT_PATH"
    echo ""
    info "重载 shell:"
    echo "   source $rc"
    echo ""
    info "开始使用:"
    echo "   ccp add work       # 添加 profile"
    echo "   ccp list           # 列出 profile"
    echo "   ccc work           # 切换并启动 Claude Code"
    echo ""
}

main "$@"
