ORIGINAL_PATH="$PATH"
ORIGINAL_SHELL="${SHELL:-}"

append_call() {
	if [ -n "$STUB_CALLS" ]; then
		STUB_CALLS="${STUB_CALLS}
$*"
	else
		STUB_CALLS="$*"
	fi
}

run_with_output() {
	TEST_OUTPUT="$("$@" 2>&1)"
	TEST_STATUS=$?
}

run() {
	"$@" >/dev/null 2>&1
	TEST_STATUS=$?
}

assert_status() {
	assertEquals "unexpected status" "$1" "$TEST_STATUS"
}

assert_success() {
	assert_status 0
}

assert_failure() {
	if [ "$TEST_STATUS" -eq 0 ]; then
		fail "expected command to fail"
	fi
}

assert_output() {
	assertEquals "unexpected output" "$1" "$TEST_OUTPUT"
}

assert_output_contains() {
	case "$TEST_OUTPUT" in
	*"$1"*) : ;;
	*) fail "expected output to contain: $1" ;;
	esac
}

assert_calls() {
	assertEquals "unexpected calls" "$1" "$STUB_CALLS"
}

stub_meta_file() {
	STUB_META_FILE=$1
	meta_file() {
		printf '%s\n' "$STUB_META_FILE"
	}
	register_stub meta_file
}

stub_ensure_meta_file() {
	STUB_META_FILE=$1
	ensure_meta_file() {
		printf '%s\n' "$STUB_META_FILE"
	}
	register_stub ensure_meta_file
}

stub_commit_entry_change_success() {
	commit_entry_change() {
		append_call "commit_entry_change $*"
		return 0
	}
	register_stub commit_entry_change
}

stub_commit_entry_change_failure() {
	commit_entry_change() {
		append_call "commit_entry_change $*"
		return 1
	}
	register_stub commit_entry_change
}

stub_download_success() {
	download() {
		append_call "download $1 $2"
		return 0
	}
	register_stub download
}

stub_curl_success() {
	curl() { return 0; }
	register_stub curl
}

stub_wget_success() {
	wget() { return 0; }
	register_stub wget
}

stub_has_command_finds_wget_only() {
	has_command() {
		[ "$1" = "wget" ]
	}
	register_stub has_command
}

stub_has_command_finds_no_downloaders() {
	has_command() { return 1; }
	register_stub has_command
}

stub_install_file_ops_success() {
	make_temp_dir() {
		append_call "make_temp_dir"
		printf '%s\n' "$TEST_ROOT/tmp"
	}
	make_dir() {
		append_call "make_dir $*"
	}
	set_file_mode() {
		append_call "set_file_mode $1 $2"
	}
	move_file() {
		append_call "move_file $1 $2"
	}
	remove_dir() {
		append_call "remove_dir $1"
	}
	register_stub make_temp_dir
	register_stub make_dir
	register_stub set_file_mode
	register_stub move_file
	register_stub remove_dir
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

reset_stubs() {
	for function_name in $STUB_FUNCTIONS; do
		unset -f "$function_name"
	done
	STUB_FUNCTIONS=
}

register_stub() {
	STUB_FUNCTIONS="${STUB_FUNCTIONS} $1"
}

reset_test_state() {
	trap - EXIT HUP INT TERM
	reset_stubs
	export TEST_ROOT="/test-root"
	export HOME="$TEST_ROOT/home"
	PATH="$ORIGINAL_PATH"
	SHELL="$ORIGINAL_SHELL"
	STUB_CALLS=
	unset ZSH_VERSION
	export PATH SHELL
}

tearDown() {
	reset_test_state
}

oneTimeTearDown() {
	:
}
