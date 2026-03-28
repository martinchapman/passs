#!/usr/bin/env sh
VERSION="0.1.0"
meta_file() { echo "$HOME/.password-store/$1/.site.meta.json"; }
add_tag() {
	file="$(meta_file "$1")"
	mkdir -p "$(dirname "$file")"
	[ ! -f "$file" ] && printf '{"tags":[]}\n' >"$file"
	jq -e --arg t "$2" '.tags | index($t)' "$file" >/dev/null 2>&1 || {
		jq --arg t "$2" '.tags += [$t]' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
		git -C "$HOME/.password-store" add "$file" && git -C "$HOME/.password-store" commit -m "Add tag '$2' for $1"
		return
	}
	echo "Tag '$2' already exists in $file"
}
list_by_tag() {
	find "$HOME/.password-store" -name ".site.meta.json" | while read -r file; do
		jq -r --arg t "$1" 'select(.tags[]? == $t) | "match"' "$file" | grep -q . && echo "${file%/.site.meta.json}" | sed "s|$HOME/.password-store/||"
	done
}
lint() {
	find "$HOME/.password-store" -type d | while read -r dir; do
		basename="$(basename "$dir")"
		[ "$basename" = ".password-store" ] && continue
		relative_path="$(echo "$dir" | sed "s|$HOME/.password-store/||")"
		echo "$relative_path" | grep -qv '/' && echo "$basename" | grep -qE '^[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.' && echo "$basename" | grep -qvE '^[0-9.]+$' && echo "error: folder name '$basename' appears to contain subdomain at $relative_path"
	done
}
case "$1" in
tag)
	[ $# -lt 3 ] && {
		echo "Usage: passs tag pass-name <tag>"
		exit 1
	}
	add_tag "$2" "$3"
	;;
get)
	[ $# -lt 2 ] && {
		echo "Usage: passs get <tag>"
		exit 1
	}
	list_by_tag "$2"
	;;
lint) lint ;;
--version | version) echo "pass wrapper v$VERSION" ;;
*) pass "$@" ;;
esac
