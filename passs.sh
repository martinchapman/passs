#!/usr/bin/env sh
VERSION="0.1.7"

password_store_dir() { echo "$HOME/.password-store"; }
store_temp_path() { echo "$(password_store_dir)/.git/passs-$1"; }
store_git() { git -C "$(password_store_dir)" "$@"; }
meta_file() { echo "$(password_store_dir)/$1/.site.meta.json"; }
parent_dir() { dirname "$1"; }
make_dir() { mkdir -p "$1"; }
move_file() { mv "$1" "$2"; }
remove_path() { rm -rf "$@"; }
path_exists() { [ -e "$1" ]; }
meta_file_exists() { [ -f "$1" ]; }
write_default_meta_file() { printf '{"tags":[],"description":""}\n' >"$1"; }

ensure_meta_file() {
	file="$(meta_file "$1")"
	make_dir "$(parent_dir "$file")"
	meta_file_exists "$file" || write_default_meta_file "$file"
	echo "$file"
}

ensure_line() {
	[ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ] && echo >>"$1"
	grep -qxF "$2" "$1" 2>/dev/null || echo "$2" >>"$1"
}

commit_store_change() {
	message="$1"
	shift
	store_git add -- "$@" && store_git commit -m "$message" -- "$@"
}

meta_has_tag() { jq -e --arg t "$2" '.tags | index($t)' "$1" >/dev/null 2>&1; }
append_meta_tag() { jq --arg t "$2" '.tags += [$t]' "$1" >"${1}.tmp" && mv "${1}.tmp" "$1"; }

add_tag() {
	file="$(ensure_meta_file "$1")"
	meta_has_tag "$file" "$2" || {
		append_meta_tag "$file" "$2"
		commit_store_change "Add tag '$2' for $1" "$file"
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
	commit_store_change "$verb description for $1" "$file"
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
top_level_gpg_files() { find "$(password_store_dir)" -maxdepth 1 -name "*.gpg" -type f; }
path_basename() { basename "$1"; }
path_relative_to_store() { echo "$1" | sed "s|$(password_store_dir)/||"; }
is_top_level_path() { echo "$1" | grep -qv '/'; }
looks_like_subdomain() {
	echo "$1" | grep -qE '^[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+' || return 1
	! echo "$1" | grep -qE '^[a-zA-Z0-9-]+\.[a-zA-Z0-9-]{1,3}\.[a-zA-Z]{2}$'
}
looks_like_ip_address() { echo "$1" | grep -qE '^[0-9.]+$'; }

print_lint_violation() { printf '%s\t%s\n' "$1" "$2"; }
get_lint_violation_field() { printf '%s\n' "$1" | cut -f "$2"; }

lint_rules() {
	printf '%s\n' \
		subdomain_folder_name \
		gpg_at_top_level
}

lint_rule_supports() {
	command -v "lint_${1}_${2}" >/dev/null 2>&1
}

lint_rule_violations() {
	rule="$1"
	"lint_${rule}_violations"
}

lint_rule_message() {
	rule="$1"
	violation="$2"
	"lint_${rule}_message" "$violation"
}

lint_rule_remediation() {
	rule="$1"
	"lint_${rule}_remediation"
}

lint_rule_fix() {
	rule="$1"
	violation="$2"
	fn="lint_${rule}_fix"

	command -v "$fn" >/dev/null 2>&1 || return 0
	"$fn" "$violation"
}

lint_rule_report() {
	rule="$1"
	violations="$(lint_rule_violations "$rule")"
	[ -n "$violations" ] || return 0
	printf '%s\n' "$violations" | while IFS= read -r violation; do
		lint_rule_message "$rule" "$violation"
	done
	lint_rule_supports "$rule" remediation && lint_rule_remediation "$rule"
}

lint_fix() {
	lint_rules | while IFS= read -r rule; do
		lint_rule_violations "$rule" | while IFS= read -r violation; do
			lint_rule_fix "$rule" "$violation"
		done
	done
}

lint() {
	lint_rules | while IFS= read -r rule; do
		lint_rule_report "$rule"
	done
}

###############################################################################
# Vault
###############################################################################

vault_dir() { echo "$(password_store_dir)/vault"; }
vault_blob_path() { echo "$(password_store_dir)/.vault.enc"; }

names_vault_entry() {
	for arg in "$@"; do
		case "$arg" in
		vault | vault/*) return 0 ;;
		esac
	done
	return 1
}

ensure_vault_ignored() { ensure_line "$(password_store_dir)/.gitignore" "/vault/"; }

vault_tar() { tar -C "$1" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - .; }

vault_encrypt() {
	set --
	while IFS= read -r id; do
		[ -n "$id" ] && set -- "$@" --hidden-recipient "$id"
	done <"$(password_store_dir)/.gpg-id"
	gpg --quiet --yes --encrypt "$@"
}

vault_decrypt() { gpg --quiet --yes --decrypt; }

vault_committed_tar() {
	! store_git cat-file -e HEAD:.vault.enc 2>/dev/null || store_git cat-file blob HEAD:.vault.enc | vault_decrypt
}

vault_seal() {
	[ -d "$(vault_dir)" ] || return 0
	current="$(store_temp_path vault-current.tar)"
	committed="$(store_temp_path vault-committed.tar)"
	ensure_vault_ignored &&
		vault_tar "$(vault_dir)" >"$current" &&
		vault_committed_tar >"$committed" &&
		{ cmp -s "$current" "$committed" ||
			{ vault_encrypt <"$current" >"$(vault_blob_path)" &&
				commit_store_change "Update vault" .gitignore .vault.enc; }; }
	status=$?
	remove_path "$current" "$committed"
	return $status
}

vault_git() { git -C "$(vault_dir)" "$@"; }

vault_history() {
	vault_git rev-list --reverse "$1..HEAD" | while IFS= read -r commit; do
		message="$(vault_git show -s --format=%B "$commit")"
		printf 'commit refs/heads/main\n%s\ndata %s\n%s\n\n' \
			"$(vault_git show -s --date=raw --format='author %an <%ae> %ad%ncommitter %cn <%ce> %cd' "$commit")" \
			"$(($(printf '%s\n' "$message" | wc -c)))" "$message"
	done
}

vault_pass() {
	history_repository="$(mktemp -d "$(store_temp_path vault-history-XXXXXX)")" &&
		make_dir "$(vault_dir)" &&
		vault_git init -q --separate-git-dir="$history_repository" &&
		vault_git add -A &&
		vault_git commit -q --allow-empty -m snapshot &&
		snapshot="$(vault_git rev-parse HEAD)" || {
		remove_path "$history_repository" "$(vault_dir)/.git"
		return 1
	}
	trap : INT TERM HUP
	pass "$@"
	status=$?
	trap - INT TERM HUP
	history="$(vault_history "$snapshot")"
	remove_path "$history_repository" "$(vault_dir)/.git"
	[ -z "$history" ] || { printf '%s\n\n' "$history" >>"$(vault_dir)/.githistory" && vault_seal; } || status=$?
	return $status
}

vault_unseal() {
	path_exists "$(vault_blob_path)" || return 0
	temp_dir="$(mktemp -d "$(store_temp_path vault-XXXXXX)")" &&
		vault_decrypt <"$(vault_blob_path)" | tar -C "$temp_dir" -xf - &&
		remove_path "$(vault_dir)" &&
		move_file "$temp_dir" "$(vault_dir)"
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
	lint)
		case "$2" in
		--fix)
			lint
			lint_fix
			;;
		*) lint ;;
		esac
		;;
	git)
		case "$2" in
		push) vault_seal && pass "$@" ;;
		pull) vault_seal && pass "$@" && vault_unseal ;;
		*) pass "$@" ;;
		esac
		;;
	--version | version) echo "pass wrapper v$VERSION" ;;
	*)
		if names_vault_entry "$@"; then
			ensure_vault_ignored && vault_pass "$@"
		else
			pass "$@"
		fi
		;;
	esac
}

###############################################################################
# Lint rule: gpg_at_top_level
###############################################################################

lint_gpg_at_top_level_violations() {
	top_level_gpg_files | while read -r file; do
		basename="$(path_basename "$file")"
		relative_path="$(path_relative_to_store "$file")"
		print_lint_violation "$basename" "$relative_path"
	done
}

lint_gpg_at_top_level_message() {
	basename="$(get_lint_violation_field "$1" 1)"
	echo "error: file '$basename' is a .gpg file at the top level"
}

lint_gpg_at_top_level_remediation() {
	echo "Password files should live inside site folders, for example foo.bar.gpg -> foo.bar/password.gpg."
}

lint_gpg_at_top_level_fix() {
	name="$(get_lint_violation_field "$1" 1)"
	folder="${name%.gpg}"
	store_dir="$(password_store_dir)"
	target="$store_dir/$folder/password.gpg"
	path_exists "$target" && {
		echo "error: cannot fix '$name', '$folder/password.gpg' already exists"
		return
	}
	make_dir "$store_dir/$folder" &&
		move_file "$store_dir/$name" "$target" &&
		echo "fixed: moved '$name' to '$folder/password.gpg'"
}

###############################################################################
# Lint rule: subdomain_folder_name
###############################################################################

lint_subdomain_folder_name_violations() {
	password_store_dirs | while read -r dir; do
		basename="$(path_basename "$dir")"
		[ "$basename" = ".password-store" ] && continue
		relative_path="$(path_relative_to_store "$dir")"
		is_top_level_path "$relative_path" && looks_like_subdomain "$basename" && ! looks_like_ip_address "$basename" && print_lint_violation "$basename" "$relative_path"
	done
}

lint_subdomain_folder_name_message() {
	name="$(get_lint_violation_field "$1" 1)"
	path="$(get_lint_violation_field "$1" 2)"
	echo "error: folder name '$name' appears to contain subdomain at $path"
}

lint_subdomain_folder_name_remediation() {
	echo "Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/foo."
}

subdomain_to_nested_path() {
	tld="${1##*.}"
	without_tld="${1%.*}"
	registrable="${without_tld##*.}.$tld"
	subdomain_labels="${without_tld%.*}"
	nested="$registrable"
	while [ -n "$subdomain_labels" ]; do
		label="${subdomain_labels##*.}"
		nested="$nested/$label"
		[ "$subdomain_labels" = "$label" ] && break
		subdomain_labels="${subdomain_labels%.*}"
	done
	echo "$nested"
}

lint_subdomain_folder_name_fix() {
	name="$(get_lint_violation_field "$1" 1)"
	store_dir="$(password_store_dir)"
	target_relative="$(subdomain_to_nested_path "$name")"
	target="$store_dir/$target_relative"
	path_exists "$target" && {
		echo "error: cannot fix '$name', '$target_relative' already exists"
		return
	}
	make_dir "$(parent_dir "$target")" &&
		move_file "$store_dir/$name" "$target" &&
		echo "fixed: moved '$name' to '$target_relative'"
}

[ "${PASSS_TESTING:-0}" = "1" ] || passs_main "$@"
