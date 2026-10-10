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

test_add_secret_entry_generate_uses_last_path_part_as_id() {
	stub_next_secret_entry
	stub_recording pass_dispatch write_secret_entry
	run add_secret_entry generate foo.com/baz/bar -n 12
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"pass_dispatch generate foo.com/baz/hidden-credentials-1 -n 12" \
		"write_secret_entry foo.com/baz/hidden-credentials-1 foo.com/baz/hidden-credentials-1 bar")"
}

test_add_secret_entry_insert_uses_last_path_part_as_id() {
	stub_next_secret_entry
	stub_recording pass_dispatch write_secret_entry
	run add_secret_entry insert foo.com/bar -m
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"pass_dispatch insert foo.com/hidden-credentials-1 -m" \
		"write_secret_entry foo.com/hidden-credentials-1 foo.com/hidden-credentials-1 bar")"
}

test_add_secret_entry_pass_overwrites_id_variable_writes_path_id() {
	stub_next_secret_entry
	pass_dispatch() { id=; }
	register_stub pass_dispatch
	stub_recording write_secret_entry
	run add_secret_entry generate foo.com/bar
	assert_success
	assert_calls "write_secret_entry foo.com/hidden-credentials-1 foo.com/hidden-credentials-1 bar"
}

test_add_secret_entry_pass_fails_skips_write() {
	stub_next_secret_entry
	stub_failing pass_dispatch
	stub_recording write_secret_entry
	run add_secret_entry generate foo.com/bar
	assert_failure
	assert_calls "pass_dispatch generate foo.com/hidden-credentials-1"
}

test_add_secret_entry_path_without_folder_and_id_shows_usage() {
	stub_recording pass_dispatch write_secret_entry
	for path in "" -n bar foo.com/ /bar; do
		run_with_output add_secret_entry insert "$path"
		assert_failure
		assert_output "Usage: passs insert --secret pass-folder/id [pass insert args]"
	done
	assert_calls ""
}

test_passs_main_generate_secret_routes_to_add_secret_entry() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main generate --secret foo.com/bar -n 12
	assert_success
	assert_calls "add_secret_entry generate foo.com/bar -n 12"
}

test_passs_main_insert_secret_routes_to_add_secret_entry() {
	stub_recording add_secret_entry pass_dispatch
	run passs_main insert --secret foo.com/bar -m
	assert_success
	assert_calls "add_secret_entry insert foo.com/bar -m"
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
