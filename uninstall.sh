#!/usr/bin/env bash
set -euo pipefail

# Uninstaller for Claude Code Commander (CCC)

INSTALL_DIR="${CCC_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ccc}"
BIN_DIR="${HOME}/.local/bin"
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
    echo "Uninstalling CCC..."

    local rc
    rc="$(detect_rc_file)"
    remove_function_block "$rc" "$OLD_BEGIN_MARK" "$OLD_END_MARK"
    remove_function_block "$rc" "$BEGIN_MARK" "$END_MARK"

    rm -f "$BIN_DIR/ccp" "$BIN_DIR/ccc"

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        echo "Removed $INSTALL_DIR"
    fi

    echo ""
    echo "✅ CCC uninstalled"
    echo ""
    echo "Note: Config directory preserved at ~/.ccc"
    echo "      Delete manually if not needed: rm -rf ~/.ccc"
    echo ""
    echo "No rc block is installed by CCC."
}

main "$@"
