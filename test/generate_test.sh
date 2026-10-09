#!/usr/bin/env sh

. "$(dirname "$0")/test_helper.sh"

setUp() {
	reset_test_state
	PASSS_TESTING=1 . ./passs.sh
}

stub_secret_inputs() {
	STUB_SECRET_ID="$1"
	prompt_secret_id() { printf '%s\n' "$STUB_SECRET_ID"; }
	next_secret_entry() { printf '%s/hidden_credentials_1\n' "$1"; }
	register_stub prompt_secret_id
	register_stub next_secret_entry
}

test_next_secret_entry_none_exist_returns_first() {
	path_exists() { return 1; }
	register_stub path_exists
	run_with_output next_secret_entry foo.com
	assert_output "foo.com/hidden_credentials_1"
}

test_next_secret_entry_some_exist_returns_first_unused() {
	path_exists() {
		case "$1" in
		"$HOME"/.password-store/foo.com/hidden_credentials_[12].gpg) return 0 ;;
		esac
		return 1
	}
	register_stub path_exists
	run_with_output next_secret_entry foo.com
	assert_output "foo.com/hidden_credentials_3"
}

test_prompt_secret_id_reads_line_from_input() {
	TEST_OUTPUT="$(echo foo-id | prompt_secret_id foo.com/hidden_credentials_1 2>/dev/null)"
	assertEquals "foo-id" "$TEST_OUTPUT"
}

test_prompt_secret_id_names_entry_in_prompt() {
	TEST_OUTPUT="$(echo foo-id | prompt_secret_id foo.com/hidden_credentials_1 2>&1 >/dev/null)"
	assertEquals "Enter id for foo.com/hidden_credentials_1: " "$TEST_OUTPUT"
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
	run write_secret_entry foo.com/hidden_credentials_1 foo.com/hidden_credentials_1 foo-id
	assert_success
	assertEquals "insert -m -f foo.com/hidden_credentials_1" "$(cat "$SHUNIT_TMPDIR/pass-args")"
	assertEquals "bar
id: foo-id" "$(cat "$SHUNIT_TMPDIR/pass-input")"
}

test_write_secret_entry_extra_lines_inserts_id_after_password() {
	stub_pass_show_and_insert "bar
url: baz.com
qux"
	run write_secret_entry foo.com/foo-id foo.com/hidden_credentials_1 foo-id
	assert_success
	assertEquals "insert -m -f foo.com/hidden_credentials_1" "$(cat "$SHUNIT_TMPDIR/pass-args")"
	assertEquals "bar
id: foo-id
url: baz.com
qux" "$(cat "$SHUNIT_TMPDIR/pass-input")"
}

test_write_secret_entry_show_fails_skips_insert() {
	pass() { return 1; }
	pass_dispatch() { touch "$SHUNIT_TMPDIR/pass-inserted"; }
	register_stub pass
	register_stub pass_dispatch
	run write_secret_entry foo.com/foo-id foo.com/hidden_credentials_1 foo-id
	assert_failure
	assertFalse "[ -e '$SHUNIT_TMPDIR/pass-inserted' ]"
}

test_generate_secret_generates_then_writes_id() {
	stub_secret_inputs foo-id
	stub_recording pass_dispatch write_secret_entry
	run generate_secret foo.com/ -n 12
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"pass_dispatch generate foo.com/hidden_credentials_1 -n 12" \
		"write_secret_entry foo.com/hidden_credentials_1 foo.com/hidden_credentials_1 foo-id")"
}

test_generate_secret_generate_overwrites_id_variable_writes_entered_id() {
	stub_secret_inputs foo-id
	pass_dispatch() { id=; }
	register_stub pass_dispatch
	stub_recording write_secret_entry
	run generate_secret foo.com
	assert_success
	assert_calls "write_secret_entry foo.com/hidden_credentials_1 foo.com/hidden_credentials_1 foo-id"
}

test_generate_secret_generate_fails_skips_write() {
	stub_secret_inputs foo-id
	stub_failing pass_dispatch
	stub_recording write_secret_entry
	run generate_secret foo.com
	assert_failure
	assert_calls "pass_dispatch generate foo.com/hidden_credentials_1"
}

test_generate_secret_missing_or_option_folder_shows_usage() {
	for folder in "" -n; do
		run_with_output generate_secret "$folder"
		assert_failure
		assert_output "Usage: passs generate --secret pass-folder [pass generate args]"
	done
}

test_generate_secret_empty_id_reports_error() {
	stub_secret_inputs ""
	stub_recording pass_dispatch write_secret_entry
	run_with_output generate_secret foo.com
	assert_failure
	assert_output "error: id can't be empty"
}

test_passs_main_generate_secret_routes_to_generate_secret() {
	stub_recording generate_secret pass_dispatch
	run passs_main generate --secret foo.com -n 12
	assert_success
	assert_calls "generate_secret foo.com -n 12"
}

test_passs_main_generate_without_secret_routes_to_pass_dispatch() {
	stub_recording generate_secret pass_dispatch
	run passs_main generate foo.com/bar 12
	assert_success
	assert_calls "pass_dispatch generate foo.com/bar 12"
}

. "$(command -v shunit2 || echo /usr/share/shunit2/shunit2)"
