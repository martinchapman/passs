#!/usr/bin/env sh

. "$(dirname "$0")/test_helper.sh"

setUp() {
	reset_test_state
	PASSS_TESTING=1 . ./install.sh
}

test_info_called_with_message_writes_to_stdout() {
	run_with_output info "foo"
	assert_success
	assert_output "foo"
}

test_warn_called_with_message_prefixes_with_warning() {
	run_with_output warn "foo"
	assert_success
	assert_output "warning: foo"
}

test_die_called_with_message_prefixes_with_error_and_exits() {
	run_with_output die "foo"
	assert_status 1
	assert_output "error: foo"
}

test_download_curl_available_uses_curl() {
	stub_curl_success
	run_with_output download "https://foo.com/passs.sh" "$TEST_ROOT/passs"
	assert_success
	assert_output ""
}

test_download_curl_unavailable_falls_back_to_wget() {
	stub_has_command_finds_wget_only
	stub_wget_success
	run_with_output download "https://foo.com/_passs" "$TEST_ROOT/_passs"
	assert_success
	assert_output ""
}

test_download_no_downloader_available_returns_failure() {
	stub_has_command_finds_no_downloaders
	run_with_output download "https://foo.com/passs.sh" "$TEST_ROOT/passs"
	assert_status 1
	assert_output "error: install requires curl or wget"
}

test_path_contains_dir_in_path_returns_success() {
	PATH="/usr/bin:$TEST_ROOT/bin:/bin"
	run_with_output path_contains "$TEST_ROOT/bin"
	assert_success
}

test_path_contains_dir_not_in_path_returns_failure() {
	PATH="/usr/bin:/bin"
	run_with_output path_contains "$TEST_ROOT/bin"
	assert_failure
}

test_display_dir_path_below_home_shortens_with_home_prefix() {
	run_with_output display_dir "$HOME/.local/bin"
	assert_success
	assert_output '$HOME/.local/bin'
}

test_display_dir_path_outside_home_leaves_unchanged() {
	run_with_output display_dir "/foo/passs/bin"
	assert_success
	assert_output "/foo/passs/bin"
}

test_uses_zsh_zsh_version_set_returns_success() {
	ZSH_VERSION="5.9"
	SHELL="/bin/bash"
	export ZSH_VERSION SHELL
	run_with_output uses_zsh
	assert_success
}

test_uses_zsh_shell_is_zsh_returns_success() {
	export SHELL="/usr/bin/zsh"
	run_with_output uses_zsh
	assert_success
}

test_uses_zsh_shell_not_zsh_returns_failure() {
	export SHELL="/bin/bash"
	run_with_output uses_zsh
	assert_failure
}

test_zsh_fpath_contains_zsh_available_delegates_to_zsh() {
	has_command() {
		[ "$1" = "zsh" ]
	}
	zsh() {
		return 0
	}
	register_stub has_command
	register_stub zsh
	run_with_output zsh_fpath_contains "$TEST_ROOT/site-functions"
	assert_success
}

test_zsh_fpath_contains_zsh_unavailable_returns_failure() {
	has_command() {
		return 1
	}
	register_stub has_command
	run_with_output zsh_fpath_contains "$TEST_ROOT/site-functions"
	assert_failure
}

test_install_main_successful_install_uses_wrapped_file_ops() {
	REPO_URL="https://foo.com/passs"
	BIN_DIR="$TEST_ROOT/bin"
	ZSH_COMPLETION_DIR="$TEST_ROOT/zsh"
	PATH="$BIN_DIR:/usr/bin:/bin"
	export SHELL="/bin/bash"
	stub_download_success
	stub_install_file_ops_success
	uses_zsh() { return 1; }
	register_stub uses_zsh
	run install_main
	assert_success
	assert_calls "$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s' \
		"make_dir $BIN_DIR $ZSH_COMPLETION_DIR" \
		"download https://foo.com/passs/passs.sh $TEST_ROOT/tmp/passs" \
		"download https://foo.com/passs/_passs $TEST_ROOT/tmp/_passs" \
		"set_file_mode 755 $TEST_ROOT/tmp/passs" \
		"set_file_mode 644 $TEST_ROOT/tmp/_passs" \
		"move_file $TEST_ROOT/tmp/passs $BIN_DIR/passs" \
		"move_file $TEST_ROOT/tmp/_passs $ZSH_COMPLETION_DIR/_passs")"
}

test_install_main_bin_dir_not_on_path_warns_user() {
	REPO_URL="https://foo.com/passs"
	BIN_DIR="$TEST_ROOT/bin"
	ZSH_COMPLETION_DIR="$TEST_ROOT/zsh"
	PATH="/usr/bin:/bin"
	export SHELL="/bin/bash"
	stub_download_success
	stub_install_file_ops_success
	uses_zsh() { return 1; }
	register_stub uses_zsh
	run_with_output install_main
	assert_success
	assert_output_contains "Installed passs to $BIN_DIR/passs"
	assert_output_contains "warning: $BIN_DIR is not on PATH"
}

test_install_main_zsh_fpath_unconfigured_warns_user() {
	REPO_URL="https://foo.com/passs"
	BIN_DIR="$TEST_ROOT/bin"
	ZSH_COMPLETION_DIR="$TEST_ROOT/zsh"
	PATH="$BIN_DIR:/usr/bin:/bin"
	export SHELL="/usr/bin/zsh"
	stub_download_success
	stub_install_file_ops_success
	uses_zsh() { return 0; }
	zsh_fpath_contains() { return 1; }
	register_stub uses_zsh
	register_stub zsh_fpath_contains
	run_with_output install_main
	assert_success
	assert_output_contains "warning: $ZSH_COMPLETION_DIR is not in your zsh fpath"
}

. /usr/share/shunit2/shunit2
