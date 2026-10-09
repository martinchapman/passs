#!/usr/bin/env sh

. "$(dirname "$0")/test_helper.sh"

setUp() {
	reset_test_state
	PASSS_TESTING=1 . ./passs.sh
}

stub_recording() {
	for function_name in "$@"; do
		eval "$function_name() { append_call \"$function_name \$*\"; }"
		register_stub "$function_name"
	done
}

stub_failing() {
	for function_name in "$@"; do
		eval "$function_name() { append_call \"$function_name \$*\"; return 1; }"
		register_stub "$function_name"
	done
}

stub_store_in_tmpdir() {
	STUB_STORE_DIR="$SHUNIT_TMPDIR/$1"
	password_store_dir() { printf '%s\n' "$STUB_STORE_DIR"; }
	register_stub password_store_dir
	mkdir -p "$STUB_STORE_DIR/.git" "$STUB_STORE_DIR/vault"
}

stub_tars() {
	STUB_CURRENT_TAR="$1"
	STUB_COMMITTED_TAR="$2"
	vault_tar() { printf '%s\n' "$STUB_CURRENT_TAR"; }
	vault_committed_tar() { printf '%s\n' "$STUB_COMMITTED_TAR"; }
	register_stub vault_tar
	register_stub vault_committed_tar
}

test_vault_dir_returns_path_inside_store() {
	run_with_output vault_dir
	assert_output "$HOME/.password-store/vault"
}

test_vault_blob_path_returns_path_inside_store() {
	run_with_output vault_blob_path
	assert_output "$HOME/.password-store/.vault.enc"
}

test_names_vault_entry_vault_path_returns_success() {
	run names_vault_entry generate -f vault/foo.com/bar 10
	assert_success
}

test_names_vault_entry_vault_folder_returns_success() {
	run names_vault_entry rm -r vault
	assert_success
}

test_names_vault_entry_other_path_returns_failure() {
	run names_vault_entry show foo.com/vault
	assert_failure
}

test_vault_committed_tar_no_committed_vault_prints_nothing() {
	stub_failing store_git vault_decrypt
	run_with_output vault_committed_tar
	assert_success
	assert_output ""
}

test_vault_committed_tar_committed_vault_decrypts_blob() {
	store_git() {
		[ "$2" = "blob" ] && printf 'foo\n'
		return 0
	}
	vault_decrypt() { sed 's/^/decrypted:/'; }
	register_stub store_git
	register_stub vault_decrypt
	run_with_output vault_committed_tar
	assert_success
	assert_output "decrypted:foo"
}

test_vault_seal_vault_absent_does_nothing() {
	stub_store_in_tmpdir absent
	rmdir "$STUB_STORE_DIR/vault"
	stub_recording ensure_vault_ignored commit_store_change
	run vault_seal
	assert_success
	assert_calls ""
}

test_vault_seal_vault_unchanged_skips_commit() {
	stub_store_in_tmpdir unchanged
	stub_tars "foo" "foo"
	stub_recording ensure_vault_ignored vault_encrypt commit_store_change
	run vault_seal
	assert_success
	assert_calls "ensure_vault_ignored "
}

test_vault_seal_vault_changed_encrypts_and_commits() {
	stub_store_in_tmpdir changed
	stub_tars "foo" "bar"
	vault_encrypt() { sed 's/^/sealed:/'; }
	register_stub vault_encrypt
	stub_recording ensure_vault_ignored commit_store_change
	run vault_seal
	assert_success
	assertEquals "sealed:foo" "$(cat "$STUB_STORE_DIR/.vault.enc")"
	assert_calls "$(printf '%s\n%s' \
		"ensure_vault_ignored " \
		"commit_store_change Update vault .gitignore .vault.enc")"
}

test_vault_seal_decrypt_fails_skips_commit_and_removes_temp_files() {
	stub_store_in_tmpdir failing
	vault_tar() { printf 'foo\n'; }
	register_stub vault_tar
	stub_failing vault_committed_tar
	stub_recording ensure_vault_ignored commit_store_change
	run vault_seal
	assert_failure
	assert_calls "$(printf '%s\n%s' "ensure_vault_ignored " "vault_committed_tar ")"
	assertEquals "" "$(ls "$STUB_STORE_DIR/.git")"
}

test_vault_unseal_blob_absent_does_nothing() {
	path_exists() { return 1; }
	register_stub path_exists
	stub_recording vault_decrypt move_file
	run vault_unseal
	assert_success
	assert_calls ""
}

test_vault_unseal_blob_present_replaces_vault() {
	stub_store_in_tmpdir unsealing
	mkdir -p "$SHUNIT_TMPDIR/archive/foo.com" && printf 'new' >"$SHUNIT_TMPDIR/archive/foo.com/bar.gpg"
	tar -C "$SHUNIT_TMPDIR/archive" -cf "$STUB_STORE_DIR/.vault.enc" .
	printf 'old' >"$STUB_STORE_DIR/vault/stale.gpg"
	vault_decrypt() { cat; }
	register_stub vault_decrypt
	run vault_unseal
	assert_success
	assertEquals "foo.com/bar.gpg" "$(cd "$STUB_STORE_DIR/vault" && find . -type f | sed 's|^\./||')"
}

test_vault_unseal_decrypt_fails_keeps_vault() {
	stub_store_in_tmpdir keeping
	printf 'foo' >"$STUB_STORE_DIR/.vault.enc"
	printf 'old' >"$STUB_STORE_DIR/vault/kept.gpg"
	stub_failing vault_decrypt
	run vault_unseal
	assert_failure
	assertEquals "old" "$(cat "$STUB_STORE_DIR/vault/kept.gpg")"
}

test_passs_main_git_push_seals_before_pass() {
	stub_recording vault_seal pass vault_unseal
	run passs_main git push
	assert_success
	assert_calls "$(printf '%s\n%s' "vault_seal " "pass git push")"
}

test_passs_main_git_pull_seals_then_unseals_around_pass() {
	stub_recording vault_seal pass vault_unseal
	run passs_main git pull
	assert_success
	assert_calls "$(printf '%s\n%s\n%s' "vault_seal " "pass git pull" "vault_unseal ")"
}

test_passs_main_git_pull_fails_skips_unseal() {
	stub_recording vault_seal vault_unseal
	stub_failing pass
	run passs_main git pull
	assert_failure
	assert_calls "$(printf '%s\n%s' "vault_seal " "pass git pull")"
}

test_passs_main_git_seal_fails_skips_pass() {
	stub_failing vault_seal
	stub_recording pass
	run passs_main git push
	assert_failure
	assert_calls "vault_seal "
}

test_passs_main_other_git_command_skips_vault() {
	stub_recording vault_seal pass vault_unseal
	run passs_main git log
	assert_success
	assert_calls "pass git log"
}

test_passs_main_vault_entry_command_ensures_ignored_then_runs_vault_pass() {
	stub_recording ensure_vault_ignored vault_pass pass
	run passs_main insert vault/foo.com/bar
	assert_success
	assert_calls "$(printf '%s\n%s' "ensure_vault_ignored " "vault_pass insert vault/foo.com/bar")"
}

test_passs_main_vault_entry_command_ignore_fails_skips_pass() {
	stub_failing ensure_vault_ignored
	stub_recording vault_pass pass
	run passs_main insert vault/foo.com/bar
	assert_failure
	assert_calls "ensure_vault_ignored "
}

test_vault_git_runs_git_inside_vault() {
	git() { printf 'git %s\n' "$*"; }
	register_stub git
	run_with_output vault_git status
	assert_output "git -C $HOME/.password-store/vault status"
}

test_vault_history_commits_after_snapshot_print_fast_import_blocks() {
	vault_git() {
		case "$1 $3" in
		"rev-list "*) printf '%s\n' foo bar ;;
		"show --format=%B") printf 'Add %s.\n' "$4" ;;
		*) printf 'author a <a@b> 1 +0000\ncommitter a <a@b> 1 +0000\n' ;;
		esac
	}
	register_stub vault_git
	run_with_output vault_history snapshot
	assert_success
	assert_output "commit refs/heads/main
author a <a@b> 1 +0000
committer a <a@b> 1 +0000
data 9
Add foo.

commit refs/heads/main
author a <a@b> 1 +0000
committer a <a@b> 1 +0000
data 9
Add bar."
}

test_vault_history_no_commits_prints_nothing() {
	vault_git() { return 0; }
	register_stub vault_git
	run_with_output vault_history snapshot
	assert_success
	assert_output ""
}

stub_vault_pass_setup() {
	stub_store_in_tmpdir "$1"
	vault_git() {
		append_call "vault_git $1"
		[ "$1" = "rev-parse" ] && printf 'snapshot\n'
		return 0
	}
	register_stub vault_git
}

test_vault_pass_pass_commits_appends_history_and_cleans_up() {
	stub_vault_pass_setup appending
	printf 'old\n\n' >"$STUB_STORE_DIR/vault/.githistory"
	stub_recording pass
	stub_recording vault_seal
	vault_history() { printf 'new\n'; }
	register_stub vault_history
	run vault_pass insert vault/foo.com/bar
	assert_success
	assertEquals "old

new" "$(cat "$STUB_STORE_DIR/vault/.githistory")"
	assert_calls "$(printf '%s\n%s\n%s\n%s\n%s' \
		"vault_git init" \
		"vault_git add" \
		"vault_git commit" \
		"pass insert vault/foo.com/bar" \
		"vault_seal ")"
	assertEquals "" "$(ls "$STUB_STORE_DIR/.git")"
}

test_vault_pass_no_history_skips_history_file_and_seal() {
	stub_vault_pass_setup reading
	stub_recording pass vault_history vault_seal
	run vault_pass show vault/foo.com/bar
	assert_success
	assertFalse "expected no history file" "[ -e '$STUB_STORE_DIR/vault/.githistory' ]"
	case "$STUB_CALLS" in
	*vault_seal*) fail "expected no seal" ;;
	esac
}

test_vault_pass_seal_fails_returns_failure() {
	stub_vault_pass_setup sealing
	stub_recording pass
	stub_failing vault_seal
	vault_history() { printf 'new\n'; }
	register_stub vault_history
	run vault_pass insert vault/foo.com/bar
	assert_failure
}

test_vault_pass_link_removed_before_seal() {
	stub_vault_pass_setup linking
	stub_recording pass
	vault_history() { printf 'new\n'; }
	vault_seal() { append_call "vault_seal link=$(ls -A "$STUB_STORE_DIR/vault" | grep -c '^\.git$')"; }
	register_stub vault_history
	register_stub vault_seal
	touch "$STUB_STORE_DIR/vault/.git"
	run vault_pass insert vault/foo.com/bar
	case "$STUB_CALLS" in
	*"vault_seal link=0"*) : ;;
	*) fail "expected vault/.git removed before sealing" ;;
	esac
}

test_vault_pass_pass_fails_returns_its_status() {
	stub_vault_pass_setup failing
	pass() { return 3; }
	register_stub pass
	stub_recording vault_history
	run vault_pass insert vault/foo.com/bar
	assert_status 3
	assertEquals "" "$(ls "$STUB_STORE_DIR/.git")"
}

test_vault_pass_snapshot_fails_skips_pass_and_cleans_up() {
	stub_store_in_tmpdir snapshotting
	vault_git() {
		append_call "vault_git $1"
		[ "$1" != "commit" ]
	}
	register_stub vault_git
	stub_recording pass
	run vault_pass insert vault/foo.com/bar
	assert_failure
	assert_calls "$(printf '%s\n%s\n%s' "vault_git init" "vault_git add" "vault_git commit")"
	assertEquals "" "$(ls "$STUB_STORE_DIR/.git")"
}

. "$(command -v shunit2 || echo /usr/share/shunit2/shunit2)"
