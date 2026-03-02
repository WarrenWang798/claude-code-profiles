#!/usr/bin/env bash
set -euo pipefail

# Uninstaller for Claude Code Profile Switcher (CCP)

INSTALL_DIR="${CCP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ccp}"
BEGIN_MARK="# >>> ccp init begin >>>"
END_MARK="# <<< ccp init end <<<"
OLD_BEGIN_MARK="# >>> ccp function begin >>>"
OLD_END_MARK="# <<< ccp function end <<<"

detect_rc_file() {
    local shell_name="${SHELL##*/}"
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash)
            if [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)    echo "$HOME/.zshrc" ;;
    esac
}

remove_function_block() {
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
        echo "Removed injected block from $rc"
    fi
}

main() {
    echo "Uninstalling CCP..."

    local rc
    rc="$(detect_rc_file)"
    remove_function_block "$rc" "$OLD_BEGIN_MARK" "$OLD_END_MARK"
    remove_function_block "$rc" "$BEGIN_MARK" "$END_MARK"

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        echo "Removed $INSTALL_DIR"
    fi

    echo ""
    echo "✅ CCP uninstalled"
    echo ""
    echo "Note: Config directory preserved at ~/.ccp"
    echo "      Delete manually if not needed: rm -rf ~/.ccp"
    echo ""
    echo "Reload your shell: source $rc"
}

main "$@"
