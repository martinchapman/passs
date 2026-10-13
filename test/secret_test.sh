#!/usr/bin/env sh

. "$(dirname "$0")/test_helper.sh"

setUp() {
	reset_test_state
	PASSS_TESTING=1 . ./passs.sh
}

stub_next_secret_entry() {
	next_secret_entry() { printf '%s/hidden-credentials-1\n' "$1"; }
	register_stub next_secret_entry
}

test_next_secret_entry_none_exist_returns_first() {
	path_exists() { return 1; }
	register_stub path_exists
	run_with_output next_secret_entry foo.com
	assert_output "foo.com/hidden-credentials-1"
}

test_next_secret_entry_some_exist_returns_first_unused() {
	path_exists() {
		case "$1" in
		"$HOME"/.password-store/foo.com/hidden-credentials-[12].gpg) return 0 ;;
		esac
		return 1
	}
	register_stub path_exists
	run_with_output next_secret_entry foo.com
	assert_output "foo.com/hidden-credentials-3"
}

stub_pass_show_and_insert() {
	STUB_CONTENT="$1"
	pass() { printf '%s\n' "$STUB_CONTENT"; }
	pass_dispatch() {
		printf '%s\n' "$*" >"$SHUNIT_TMPDIR/pass-args"
		cat >"$SHUNIT_TMPDIR/pass-input"
	}
	register_stub pass
	register_stub pass_dispatch
}

test_write_secret_entry_password_only_appends_id_line() {
	stub_pass_show_and_insert bar
	run write_secret_entry foo.com/hidden-credentials-1 foo.com/hidden-credentials-1 foo-id
	assert_success
	assertEquals "insert -m -f foo.com/hidden-credentials-1" "$(cat "$SHUNIT_TMPDIR/pass-args")"
	assertEquals "bar
login: foo-id" "$(cat "$SHUNIT_TMPDIR/pass-input")"
}

test_write_secret_entry_extra_lines_inserts_id_after_password() {
	stub_pass_show_and_insert "bar
url: baz.com
qux"
	run write_secret_entry foo.com/foo-id foo.com/hidden-credentials-1 foo-id
	assert_success
	assertEquals "insert -m -f foo.com/hidden-credentials-1" "$(cat "$SHUNIT_TMPDIR/pass-args")"
	assertEquals "bar
login: foo-id
url: baz.com
qux" "$(cat "$SHUNIT_TMPDIR/pass-input")"
}

test_write_secret_entry_show_fails_skips_insert() {
	pass() { return 1; }
	pass_dispatch() { touch "$SHUNIT_TMPDIR/pass-inserted"; }
	register_stub pass
	register_stub pass_dispatch
	run write_secret_entry foo.com/foo-id foo.com/hidden-credentials-1 foo-id
	assert_failure
	assertFalse "[ -e '$SHUNIT_TMPDIR/pass-inserted' ]"
}

test_secret_entry_has_id_login_line_present_returns_true() {
	pass() { printf 'bar\nlogin: foo-id\n'; }
	register_stub pass
	assertTrue "secret_entry_has_id foo.com/hidden-credentials-1 foo-id"
}

test_secret_entry_has_id_login_line_absent_returns_false() {
	pass() { printf 'bar\nlogin: foo-idbaz\n'; }
	register_stub pass
	assertFalse "secret_entry_has_id foo.com/hidden-credentials-1 foo-id"
}

test_secret_entry_has_id_show_fails_returns_false() {
	stub_failing pass
	assertFalse "secret_entry_has_id foo.com/hidden-credentials-1 foo-id"
}

test_existing_secret_entry_id_in_entry_returns_entry() {
	stub_store_in_tmpdir store
	mkdir -p "$STUB_STORE_DIR/foo.com"
	touch "$STUB_STORE_DIR/foo.com/hidden-credentials-1.gpg" "$STUB_STORE_DIR/foo.com/hidden-credentials-2.gpg"
	secret_entry_has_id() { [ "$1 $2" = "foo.com/hidden-credentials-2 bar" ]; }
	register_stub secret_entry_has_id
	run_with_output existing_secret_entry foo.com bar
	assert_success
	assert_output "foo.com/hidden-credentials-2"
}

test_existing_secret_entry_id_in_no_entry_fails() {
	stub_store_in_tmpdir store
	mkdir -p "$STUB_STORE_DIR/foo.com"
	touch "$STUB_STORE_DIR/foo.com/hidden-credentials-1.gpg"
	stub_failing secret_entry_has_id
	run_with_output existing_secret_entry foo.com bar
	assert_failure
	assert_output ""
}

test_existing_secret_entry_no_entries_fails() {
	stub_store_in_tmpdir store
	stub_failing secret_entry_has_id
	run_with_output existing_secret_entry foo.com bar
	assert_failure
	assert_output ""
}

stub_new_secret_entry() {
	stub_failing existing_secret_entry secret_entry_has_id
	stub_next_secret_entry
}

test_add_secret_entry_generate_uses_last_path_part_as_id() {
	stub_new_secret_entry
	stub_recording pass_dispatch write_secret_entry
	run add_secret_entry generate --secret foo.com/baz/bar -n 12
	assert_success
	assert_calls "$(printf '%s\n%s\n%s' \
		"pass_dispatch generate foo.com/baz/hidden-credentials-1 -n 12" \
		"secret_entry_has_id foo.com/baz/hidden-credentials-1 bar" \
		"write_secret_entry foo.com/baz/hidden-credentials-1 foo.com/baz/hidden-credentials-1 bar")"
}

test_add_secret_entry_insert_uses_last_path_part_as_id() {
	stub_new_secret_entry
	stub_recording pass_dispatch write_secret_entry
	run add_secret_entry insert --secret foo.com/bar -m
	assert_success
	assert_calls "$(printf '%s\n%s\n%s' \
		"pass_dispatch insert foo.com/hidden-credentials-1 -m" \
		"secret_entry_has_id foo.com/hidden-credentials-1 bar" \
		"write_secret_entry foo.com/hidden-credentials-1 foo.com/hidden-credentials-1 bar")"
}

test_add_secret_entry_options_before_secret_passes_them_to_pass() {
	stub_new_secret_entry
	stub_recording pass_dispatch write_secret_entry
	run add_secret_entry generate -c -n --secret foo.com/bar 12
	assert_success
	assert_calls "$(printf '%s\n%s\n%s' \
		"pass_dispatch generate foo.com/hidden-credentials-1 -c -n 12" \
		"secret_entry_has_id foo.com/hidden-credentials-1 bar" \
		"write_secret_entry foo.com/hidden-credentials-1 foo.com/hidden-credentials-1 bar")"
}

test_add_secret_entry_existing_id_reuses_entry() {
	existing_secret_entry() { printf '%s/hidden-credentials-2\n' "$1"; }
	register_stub existing_secret_entry
	stub_failing secret_entry_has_id
	stub_recording next_secret_entry pass_dispatch write_secret_entry
	run add_secret_entry generate -f --secret foo.com/bar
	assert_success
	assert_calls "$(printf '%s\n%s\n%s' \
		"pass_dispatch generate foo.com/hidden-credentials-2 -f" \
		"secret_entry_has_id foo.com/hidden-credentials-2 bar" \
		"write_secret_entry foo.com/hidden-credentials-2 foo.com/hidden-credentials-2 bar")"
}

test_add_secret_entry_id_kept_by_pass_skips_write() {
	stub_new_secret_entry
	stub_recording secret_entry_has_id pass_dispatch write_secret_entry
	run add_secret_entry generate -i --secret foo.com/bar
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"pass_dispatch generate foo.com/hidden-credentials-1 -i" \
		"secret_entry_has_id foo.com/hidden-credentials-1 bar")"
}

test_add_secret_entry_pass_overwrites_id_variable_writes_path_id() {
	stub_new_secret_entry
	pass_dispatch() { id=; }
	register_stub pass_dispatch
	stub_recording write_secret_entry
	run add_secret_entry generate --secret foo.com/bar
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"secret_entry_has_id foo.com/hidden-credentials-1 bar" \
		"write_secret_entry foo.com/hidden-credentials-1 foo.com/hidden-credentials-1 bar")"
}

test_add_secret_entry_pass_fails_skips_write() {
	stub_new_secret_entry
	stub_failing pass_dispatch
	stub_recording write_secret_entry
	run add_secret_entry generate --secret foo.com/bar
	assert_failure
	assert_calls "pass_dispatch generate foo.com/hidden-credentials-1"
}

test_add_secret_entry_path_without_folder_and_id_shows_usage() {
	stub_recording pass_dispatch write_secret_entry
	for path in "" -n bar foo.com/ /bar; do
		run_with_output add_secret_entry insert --secret "$path"
		assert_failure
		assert_output "Usage: passs insert --secret pass-folder/id [pass insert args]"
	done
	run_with_output add_secret_entry insert -m --secret
	assert_failure
	assert_output "Usage: passs insert --secret pass-folder/id [pass insert args]"
	assert_calls ""
}

test_passs_main_generate_secret_routes_to_add_secret_entry() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main generate --secret foo.com/bar -n 12
	assert_success
	assert_calls "add_secret_entry generate --secret foo.com/bar -n 12"
}

test_passs_main_insert_secret_routes_to_add_secret_entry() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main insert --secret foo.com/bar -m
	assert_success
	assert_calls "add_secret_entry insert --secret foo.com/bar -m"
}

test_passs_main_secret_after_options_routes_to_add_secret_entry() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main generate -c --secret foo.com/bar
	assert_success
	assert_calls "add_secret_entry generate -c --secret foo.com/bar"
}

test_passs_main_generate_without_secret_routes_to_pass_dispatch() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main generate foo.com/bar 12
	assert_success
	assert_calls "pass_dispatch generate foo.com/bar 12"
}

test_passs_main_insert_without_secret_routes_to_pass_dispatch() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main insert foo.com/bar
	assert_success
	assert_calls "pass_dispatch insert foo.com/bar"
}

. "$(command -v shunit2 || echo /usr/share/shunit2/shunit2)"
