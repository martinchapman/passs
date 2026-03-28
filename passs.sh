#!/usr/bin/env sh
VERSION="0.1.0"
meta_file() { echo "$HOME/.password-store/$1/.site.meta.json"; }
ensure_meta_file() {
	file="$(meta_file "$1")"
	mkdir -p "$(dirname "$file")"
	[ ! -f "$file" ] && printf '{"tags":[],"description":""}\n' >"$file"
	echo "$file"
}
commit_meta_change() {
	git -C "$HOME/.password-store" add "$1" && git -C "$HOME/.password-store" commit -m "$2"
}
add_tag() {
	file="$(ensure_meta_file "$1")"
	jq -e --arg t "$2" '.tags | index($t)' "$file" >/dev/null 2>&1 || {
		jq --arg t "$2" '.tags += [$t]' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
		commit_meta_change "$file" "Add tag '$2' for $1"
		return
	}
	echo "Tag '$2' already exists in $file"
}
add_description() {
	file="$(ensure_meta_file "$1")"
	current_description="$(jq -r '.description // ""' "$file")"
	[ "$current_description" = "$2" ] && {
		echo "Description already set to '$2' for $1"
		return
	}
	jq --arg d "$2" '.description = $d' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
	[ -n "$current_description" ] && verb="Update" || verb="Add"
	commit_meta_change "$file" "$verb description for $1"
}
get_description() {
	file="$(meta_file "$1")"
	[ -f "$file" ] && {
		description="$(jq -r '.description // ""' "$file")"
		[ -n "$description" ] && echo "$description"
	}
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
	case "$2" in
	list)
		[ $# -lt 3 ] && {
			echo "Usage: passs tag list <tag>"
			exit 1
		}
		list_by_tag "$3"
		;;
	*)
		[ $# -lt 3 ] && {
			echo "Usage: passs tag pass-name <tag>"
			exit 1
		}
		add_tag "$2" "$3"
		;;
	esac
	;;
description)
	case "$2" in
	get)
		[ $# -lt 3 ] && {
			echo "Usage: passs description get pass-name"
			exit 1
		}
		get_description "$3"
		;;
	*)
		[ $# -lt 3 ] && {
			echo "Usage: passs description pass-name <description>"
			exit 1
		}
		add_description "$2" "$3"
		;;
	esac
	;;
lint) lint ;;
--version | version) echo "pass wrapper v$VERSION" ;;
*) pass "$@" ;;
esac
