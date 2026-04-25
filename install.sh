#!/usr/bin/env bash
set -euo pipefail

# Claude Code Commander (CCC) — 安装脚本
# 支持两种安装方式:
#   本地: git clone 后运行 ./install.sh
#   远程: curl -fsSL https://raw.githubusercontent.com/WarrenWang798/claude-code-profiles/main/install.sh | bash
#
# 环境变量:
#   CCC_DIR     — 自定义安装目录（默认 ~/.local/share/ccc）
#   CCC_REPO    — 自定义 GitHub 仓库（默认 WarrenWang798/claude-code-profiles）
#   CCC_BRANCH  — 自定义分支（默认 main）

CCC_VERSION="3.0.0"

# GitHub 仓库信息（用户可通过环境变量覆盖）
REPO="${CCC_REPO:-${CCP_REPO:-WarrenWang798/claude-code-profiles}}"
BRANCH="${CCC_BRANCH:-${CCP_BRANCH:-main}}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

INSTALL_DIR="${CCC_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ccc}"
BIN_DIR="${HOME}/.local/bin"
DEST_CCC_PATH="$INSTALL_DIR/ccc"
DEST_INIT_PATH="$INSTALL_DIR/ccp-init.sh"
BEGIN_MARK="# >>> ccp init begin >>>"
END_MARK="# <<< ccp init end <<<"
OLD_BEGIN_MARK="# >>> ccp function begin >>>"
OLD_END_MARK="# <<< ccp function end <<<"

# 检测本地是否有 ccc（判断是本地安装还是远程安装）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
LOCAL_CCC="${SCRIPT_DIR:+$SCRIPT_DIR/ccc}"
IS_LOCAL=false
if [[ -n "$LOCAL_CCC" && -f "$LOCAL_CCC" ]]; then
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

# 移除已有的 ccp 注入块
remove_existing_block() {
    local rc="$1"
    local begin_mark="$2"
    local end_mark="$3"
    [[ -f "$rc" ]] || return 0
    if grep -qF "$begin_mark" "$rc"; then
        local tmp
        tmp="$(mktemp)"
        awk -v b="$begin_mark" -v e="$end_mark" '
            $0==b {inblock=1; next}
            $0==e {inblock=0; next}
            !inblock {print}
        ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    fi
}

main() {
    echo ""
    echo -e "${BLUE}Claude Code Commander (CCC) v${CCC_VERSION}${NC}"
    echo ""

    # 1. 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"

    # 2. 获取 ccc
    if [[ "$IS_LOCAL" == "true" ]]; then
        info "本地安装 (从 $SCRIPT_DIR)"
        cp -f "$SCRIPT_DIR/ccc" "$DEST_CCC_PATH"
    else
        info "远程安装 (从 github.com/${REPO})"
        download "${RAW_BASE}/ccc" "$DEST_CCC_PATH"
    fi
    chmod +x "$DEST_CCC_PATH"

    # 3. 清理历史 rc 注入块
    local rc
    rc="$(detect_rc_file)"
    remove_existing_block "$rc" "$OLD_BEGIN_MARK" "$OLD_END_MARK"
    remove_existing_block "$rc" "$BEGIN_MARK" "$END_MARK"
    rm -f "$DEST_INIT_PATH"

    # 4. 创建命令链接
    rm -f "$BIN_DIR/ccp"
    ln -sfn "$DEST_CCC_PATH" "$BIN_DIR/ccc"

    # 5. 完成
    echo ""
    ok "已安装 ccc 到: $INSTALL_DIR"
    echo "   启动器: $DEST_CCC_PATH"
    echo "   命令链接: $BIN_DIR/ccc"
    echo ""
    info "开始使用:"
    echo "   ccc import-cc-switch  # 从 CC Switch 导入 Claude profiles"
    echo "   ccc list              # 列出 profiles"
    echo "   ccc work              # 以 profile 启动 Claude Code"
    echo ""

    case ":${PATH:-}:" in
        *":${BIN_DIR}:"*)
            ;;
        *)
            warn "${BIN_DIR} 不在 PATH 中，请手动加入 shell PATH"
            ;;
    esac
    echo ""
}

main "$@"
