#!/usr/bin/env sh
[ "${PASSS_TESTING:-0}" = "1" ] || set -e

REPO_URL="${PASSS_REPO_URL:-https://raw.githubusercontent.com/martinchapman/passs/main}"
BIN_DIR="${PASSS_BIN_DIR:-$HOME/.local/bin}"
ZSH_COMPLETION_DIR="${PASSS_ZSH_COMPLETION_DIR:-$HOME/.local/share/zsh/site-functions}"

info() {
	printf '%s\n' "$*"
}

warn() {
	printf 'warning: %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

download() {
	url="$1"
	destination="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$destination"
	elif command -v wget >/dev/null 2>&1; then
		wget -q "$url" -O "$destination"
	else
		die "install requires curl or wget"
	fi
}

path_contains() {
	case ":$PATH:" in
	*":$1:"*) return 0 ;;
	*) return 1 ;;
	esac
}

display_dir() {
	home_prefix="${HOME%/}/"

	case "$1" in
	"$home_prefix"*) printf '$HOME/%s' "${1#"$home_prefix"}" ;;
	*) printf '%s' "$1" ;;
	esac
}

uses_zsh() {
	[ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]
}

zsh_fpath_contains() {
	command -v zsh >/dev/null 2>&1 || return 1
	zsh -ic 'dir="$1"; for entry in $fpath; do [[ "$entry" == "$dir" ]] && exit 0; done; exit 1' passs-check "$1" >/dev/null 2>&1
}

install_main() {
	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

	mkdir -p "$BIN_DIR" "$ZSH_COMPLETION_DIR"

	download "$REPO_URL/passs.sh" "$tmp_dir/passs"
	download "$REPO_URL/_passs" "$tmp_dir/_passs"

	chmod 755 "$tmp_dir/passs"
	chmod 644 "$tmp_dir/_passs"

	mv "$tmp_dir/passs" "$BIN_DIR/passs"
	mv "$tmp_dir/_passs" "$ZSH_COMPLETION_DIR/_passs"

	info "Installed passs to $BIN_DIR/passs"
	info "Installed zsh completion to $ZSH_COMPLETION_DIR/_passs"

	if ! path_contains "$BIN_DIR"; then
		warn "$BIN_DIR is not on PATH, so 'passs' may not be available in new shells."
		warn "Add this to your shell profile:"
		warn "  export PATH=\"$(display_dir "$BIN_DIR"):\$PATH\""
	fi

	if uses_zsh && ! zsh_fpath_contains "$ZSH_COMPLETION_DIR"; then
		warn "$ZSH_COMPLETION_DIR is not in your zsh fpath, so passs completion may not load."
		warn "Add this before compinit in your zsh config:"
		warn "  fpath=(\"$(display_dir "$ZSH_COMPLETION_DIR")\" \$fpath)"
	fi

	if [ "$(basename "${SHELL:-}")" = "bash" ]; then
		info "Bash users: passs is installed, but this repo does not currently ship bash completion."
	fi
}

[ "${PASSS_TESTING:-0}" = "1" ] || install_main "$@"
