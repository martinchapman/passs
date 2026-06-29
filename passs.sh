#!/usr/bin/env sh
VERSION="0.1.1"

password_store_dir() { echo "$HOME/.password-store"; }
meta_file() { echo "$HOME/.password-store/$1/.site.meta.json"; }
parent_dir() { dirname "$1"; }
make_dir() { mkdir -p "$1"; }
meta_file_exists() { [ -f "$1" ]; }
write_default_meta_file() { printf '{"tags":[],"description":""}\n' >"$1"; }

ensure_meta_file() {
	file="$(meta_file "$1")"
	make_dir "$(parent_dir "$file")"
	meta_file_exists "$file" || write_default_meta_file "$file"
	echo "$file"
}

commit_meta_change() {
	git -C "$HOME/.password-store" add "$1" && git -C "$HOME/.password-store" commit -m "$2"
}

meta_has_tag() { jq -e --arg t "$2" '.tags | index($t)' "$1" >/dev/null 2>&1; }
append_meta_tag() { jq --arg t "$2" '.tags += [$t]' "$1" >"${1}.tmp" && mv "${1}.tmp" "$1"; }

add_tag() {
	file="$(ensure_meta_file "$1")"
	meta_has_tag "$file" "$2" || {
		append_meta_tag "$file" "$2"
		commit_meta_change "$file" "Add tag '$2' for $1"
		return
	}
	echo "Tag '$2' already exists in $file"
}

meta_description() { jq -r '.description // ""' "$1"; }
set_meta_description() { jq --arg d "$2" '.description = $d' "$1" >"${1}.tmp" && mv "${1}.tmp" "$1"; }

add_description() {
	file="$(ensure_meta_file "$1")"
	current_description="$(meta_description "$file")"
	[ "$current_description" = "$2" ] && {
		echo "Description already set to '$2' for $1"
		return
	}
	set_meta_description "$file" "$2"
	[ -n "$current_description" ] && verb="Update" || verb="Add"
	commit_meta_change "$file" "$verb description for $1"
}

get_description() {
	file="$(meta_file "$1")"
	meta_file_exists "$file" && {
		description="$(meta_description "$file")"
		[ -n "$description" ] && echo "$description"
	}
}

metadata_files() { find "$(password_store_dir)" -name ".site.meta.json"; }
meta_matches_tag() { jq -r --arg t "$2" 'select(.tags[]? == $t) | "match"' "$1" | grep -q .; }
meta_path_to_pass_name() { echo "${1%/.site.meta.json}" | sed "s|$(password_store_dir)/||"; }

list_by_tag() {
	metadata_files | while read -r file; do
		meta_matches_tag "$file" "$1" && meta_path_to_pass_name "$file"
	done
}

password_store_dirs() { find "$(password_store_dir)" -type d; }
path_basename() { basename "$1"; }
path_relative_to_store() { echo "$1" | sed "s|$(password_store_dir)/||"; }
is_top_level_path() { echo "$1" | grep -qv '/'; }
looks_like_subdomain() { echo "$1" | grep -qE '^[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.'; }
looks_like_ip_address() { echo "$1" | grep -qE '^[0-9.]+$'; }

lint() {
	password_store_dirs | while read -r dir; do
		basename="$(path_basename "$dir")"
		[ "$basename" = ".password-store" ] && continue
		relative_path="$(path_relative_to_store "$dir")"
		is_top_level_path "$relative_path" && looks_like_subdomain "$basename" && ! looks_like_ip_address "$basename" && echo "error: folder name '$basename' appears to contain subdomain at $relative_path"
	done
}

passs_main() {
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
}

[ "${PASSS_TESTING:-0}" = "1" ] || passs_main "$@"
