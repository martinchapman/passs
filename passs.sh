#!/usr/bin/env sh
VERSION="0.1.8"

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
		commit_entry_change "Add tag '$2' for $1" "$file"
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
	commit_entry_change "$verb description for $1" "$file"
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

lint_roots() {
	password_store_dir
	[ ! -d "$(vault_dir)" ] || vault_dir
}

top_level_gpg_files() {
	lint_roots | while read -r root; do
		find "$root" -maxdepth 1 -name "*.gpg" -type f
	done
}

top_level_dirs() {
	lint_roots | while read -r root; do
		find "$root" -mindepth 1 -maxdepth 1 -type d
	done
}

path_basename() { basename "$1"; }
path_relative_to_store() { echo "$1" | sed "s|$(password_store_dir)/||"; }
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
		gpg_at_top_level \
		redundant_address \
		leaked_id
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

vault_name() { echo vault; }
vault_blob_name() { echo ".$(vault_name).enc"; }
vault_dir() { echo "$(password_store_dir)/$(vault_name)"; }
vault_blob_path() { echo "$(password_store_dir)/$(vault_blob_name)"; }

names_vault_entry() {
	vault_prefix="$(vault_name)"
	for arg in "$@"; do
		case "$arg" in
		"$vault_prefix" | "$vault_prefix"/*) return 0 ;;
		esac
	done
	return 1
}

relocates_vault() {
	case "$1" in
	mv | cp | rename | copy) shift ;;
	*) return 1 ;;
	esac
	vault_prefix="$(vault_name)"
	for arg in "$@"; do
		case "$arg" in
		-*) ;;
		"$vault_prefix" | "$vault_prefix"/) return 0 ;;
		*) return 1 ;;
		esac
	done
	return 1
}

ensure_vault_ignored() { ensure_line "$(password_store_dir)/.gitignore" "/$(vault_name)/"; }

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
	! store_git cat-file -e "HEAD:$(vault_blob_name)" 2>/dev/null ||
		store_git cat-file blob "HEAD:$(vault_blob_name)" | vault_decrypt
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
				commit_store_change "Update vault" .gitignore "$(vault_blob_name)"; }; }
	status=$?
	remove_path "$current" "$committed"
	return $status
}

vault_git() { git -C "$(vault_dir)" "$@"; }

format_history_entry() {
	printf 'commit refs/heads/main\nauthor %s\ncommitter %s\ndata %s\n%s\n' \
		"$1" "$2" "$(($(printf '%s\n' "$3" | wc -c)))" "$3"
}

append_vault_history() { printf '%s\n\n' "$1" >>"$(vault_dir)/.githistory"; }

vault_history() {
	vault_git rev-list --reverse "$1..HEAD" | while IFS= read -r commit; do
		format_history_entry \
			"$(vault_git show -s --date=raw --format='%an <%ae> %ad' "$commit")" \
			"$(vault_git show -s --date=raw --format='%cn <%ce> %cd' "$commit")" \
			"$(vault_git show -s --format=%B "$commit")"
		echo
	done
}

commit_entry_change() {
	case "$2" in
	"$(vault_dir)"/*)
		append_vault_history "$(format_history_entry \
			"$(store_git var GIT_AUTHOR_IDENT)" "$(store_git var GIT_COMMITTER_IDENT)" "$1")" &&
			vault_seal
		;;
	*) commit_store_change "$1" "$2" ;;
	esac
}

vault_remove() {
	path_exists "$(vault_blob_path)" || return 0
	remove_path "$(vault_blob_path)" && commit_store_change "Remove vault" "$(vault_blob_name)"
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
	[ -d "$(vault_dir)" ] || {
		remove_path "$history_repository"
		vault_remove || return 1
		return $status
	}
	history="$(vault_history "$snapshot")"
	remove_path "$history_repository" "$(vault_dir)/.git"
	[ -z "$history" ] || { append_vault_history "$history" && vault_seal; } || status=$?
	return $status
}

vault_unseal() {
	path_exists "$(vault_blob_path)" || {
		remove_path "$(vault_dir)"
		return
	}
	temp_dir="$(mktemp -d "$(store_temp_path vault-XXXXXX)")" &&
		vault_decrypt <"$(vault_blob_path)" | tar -C "$temp_dir" -xf - &&
		remove_path "$(vault_dir)" &&
		move_file "$temp_dir" "$(vault_dir)"
}

passs_help() {
	vault="$(vault_name)"
	cat <<EOF
Usage: passs <command> [args]

Commands:
  tag pass-name <tag>               Add a tag to an entry and commit it
  tag list <tag>                    List entries with a tag
  description pass-name <text>      Set an entry's description and commit it
  description get pass-name         Print an entry's description
  lint [--fix]                      Report store structure problems, and fix them with --fix
  generate --secret pass-folder [pass generate args]
                                    Prompt for an id, generate a password and save both as pass-folder/hidden_credentials_N
  git push|pull [args]              Run pass git, encrypting and decrypting the vault
  version, --version                Print the version
  help, -h, --help                  Show this help

Vault:
  Entries under $vault/ are committed as one encrypted file ($(vault_blob_name)), so their names never reach the remote.
  Manage them with passs, for example 'passs insert $vault/foo.com/bar', so each change is committed.
  passs git pull decrypts the vault after pulling.
  The commits pass would make for vault entries are kept in $vault/.githistory as a git fast-import stream.

For all other functionality, call pass directly (see 'pass help').
EOF
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
	generate)
		case "$2" in
		--secret)
			shift 2
			generate_secret "$@"
			;;
		*) pass_dispatch "$@" ;;
		esac
		;;
	--version | version) echo "pass wrapper v$VERSION" ;;
	help | -h | --help) passs_help ;;
	*) pass_dispatch "$@" ;;
	esac
}

pass_dispatch() {
	if relocates_vault "$@"; then
		echo "error: moving or copying the whole vault isn't supported, move its entries instead" >&2
		return 1
	elif names_vault_entry "$@"; then
		ensure_vault_ignored && vault_pass "$@"
	else
		pass "$@"
	fi
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
	path="$(get_lint_violation_field "$1" 2)"
	echo "error: file '$path' is a .gpg file at the top level"
}

lint_gpg_at_top_level_remediation() {
	echo "Password files should live inside site folders, for example foo.bar.gpg -> foo.bar/password.gpg."
}

lint_gpg_at_top_level_fix() {
	path="$(get_lint_violation_field "$1" 2)"
	folder="${path%.gpg}"
	store_dir="$(password_store_dir)"
	target="$store_dir/$folder/password.gpg"
	path_exists "$target" && {
		echo "error: cannot fix '$path', '$folder/password.gpg' already exists"
		return
	}
	make_dir "$store_dir/$folder" &&
		move_file "$store_dir/$path" "$target" &&
		echo "fixed: moved '$path' to '$folder/password.gpg'"
}

###############################################################################
# Lint rule: subdomain_folder_name
###############################################################################

lint_subdomain_folder_name_violations() {
	top_level_dirs | while read -r dir; do
		basename="$(path_basename "$dir")"
		relative_path="$(path_relative_to_store "$dir")"
		looks_like_subdomain "$basename" && ! looks_like_ip_address "$basename" && print_lint_violation "$basename" "$relative_path"
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
	path="$(get_lint_violation_field "$1" 2)"
	store_dir="$(password_store_dir)"
	target_relative="${path%"$name"}$(subdomain_to_nested_path "$name")"
	target="$store_dir/$target_relative"
	path_exists "$target" && {
		echo "error: cannot fix '$path', '$target_relative' already exists"
		return
	}
	make_dir "$(parent_dir "$target")" &&
		move_file "$store_dir/$path" "$target" &&
		echo "fixed: moved '$path' to '$target_relative'"
}

###############################################################################
# Lint rule: leaked_id
###############################################################################

user_full_name() { getent passwd "$USER" | cut -d: -f5 | cut -d, -f1; }

generic_account_words() {
	printf '%s\n' access account admin administrator api app backup codes config demo dev developer \
		email key login memorable other password phone pin root secret service ssh temp test token \
		user username vpn
}

web_entries() {
	store_dir="$(password_store_dir)"
	find "$store_dir" -path "$store_dir/.git" -prune -o -path "$(vault_dir)" -prune -o -name '*.gpg' -type f -print |
		sed "s|^$store_dir/||; s|\.gpg$||" | grep -E '^[^/]*\.[^/]*/'
}

looks_like_id() {
	case "$1" in
	*@* | hidden_credentials_[0-9]*) return 1 ;;
	esac
	generic_account_words | grep -qixF "$1" && return 1
	for part in $2; do
		printf '%s\n' "$1" | grep -qiF "$part" && return 1
	done
	return 0
}

lint_leaked_id_violations() {
	user_name="$(user_full_name)"
	web_entries | while read -r relative_path; do
		looks_like_id "${relative_path##*/}" "$user_name" &&
			print_lint_violation "${relative_path##*/}" "$relative_path"
	done
}

lint_leaked_id_message() {
	name="$(get_lint_violation_field "$1" 1)"
	path="$(get_lint_violation_field "$1" 2)"
	echo "error: entry name '$name' appears to be an id at $path"
}

lint_leaked_id_remediation() {
	echo "Entry names aren't encrypted, so they shouldn't contain ids. Move the id into the entry, for example with 'passs generate --secret foo.com', or into the vault."
}

###############################################################################
# Lint rule: redundant_address
###############################################################################

repeated_site_address() {
	host=
	match=
	IFS=/
	for folder in ${1%/*}; do
		host="$folder${host:+.$host}"
		case "${1##*/}" in *"$host"*) match="$host" ;; esac
	done
	unset IFS
	echo "$match"
}

has_redundant_address() {
	case "${1##*/}" in *@*) return 1 ;; esac
	[ -n "$(repeated_site_address "$1")" ] ||
		[ "$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')" = "${1%%.*}" ]
}

redundant_address_fixed_name() {
	address="$(repeated_site_address "$1")"
	[ -n "$address" ] || {
		echo user
		return
	}
	name="${1##*/}"
	before="${name%%"$address"*}"
	after="${name#*"$address"}"
	name="${before%[._-]}${after#[._-]}"
	echo "${name:-user}"
}

lint_redundant_address_violations() {
	web_entries | while read -r relative_path; do
		has_redundant_address "$relative_path" &&
			print_lint_violation "${relative_path##*/}" "$relative_path"
	done
}

lint_redundant_address_message() {
	name="$(get_lint_violation_field "$1" 1)"
	path="$(get_lint_violation_field "$1" 2)"
	echo "error: entry name '$name' repeats its site address at $path"
}

lint_redundant_address_remediation() {
	echo "Entry names shouldn't repeat the site they're filed under, for example foo.com/bar.foo.com -> foo.com/bar, or foo.com/foo.com -> foo.com/user."
}

lint_redundant_address_fix() {
	path="$(get_lint_violation_field "$1" 2)"
	store_dir="$(password_store_dir)"
	target_relative="$(parent_dir "$path")/$(redundant_address_fixed_name "$path")"
	path_exists "$store_dir/$target_relative.gpg" && {
		echo "error: cannot fix '$path', '$target_relative' already exists"
		return
	}
	move_file "$store_dir/$path.gpg" "$store_dir/$target_relative.gpg" &&
		echo "fixed: moved '$path' to '$target_relative'"
}

###############################################################################
# Secret generation
###############################################################################

prompt_secret_id() {
	printf 'Enter id for %s: ' "$1" >&2
	read -r id
	echo "$id"
}

next_secret_entry() {
	index=1
	while path_exists "$(password_store_dir)/$1/hidden_credentials_$index.gpg"; do
		index=$((index + 1))
	done
	echo "$1/hidden_credentials_$index"
}

append_secret_id() {
	password="$(pass show "$1")" &&
		printf '%s\nid: %s\n' "$password" "$2" | pass_dispatch insert -m -f "$1" >/dev/null
}

generate_secret() {
	case "$1" in
	"" | -*)
		echo "Usage: passs generate --secret pass-folder [pass generate args]"
		return 1
		;;
	esac
	name="$(next_secret_entry "${1%/}")"
	secret_id="$(prompt_secret_id "$name")"
	[ -n "$secret_id" ] || {
		echo "error: id can't be empty" >&2
		return 1
	}
	shift
	pass_dispatch generate "$name" "$@" && append_secret_id "$name" "$secret_id"
}

[ "${PASSS_TESTING:-0}" = "1" ] || passs_main "$@"
