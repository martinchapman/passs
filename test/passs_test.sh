#!/usr/bin/env sh

. "$(dirname "$0")/test_helper.sh"

setUp() {
	reset_test_state
	PASSS_TESTING=1 . ./passs.sh
}

test_meta_file_called_with_site_returns_path() {
	run_with_output meta_file "foo.com/bar"
	assert_success
	assert_output "$HOME/.password-store/foo.com/bar/.site.meta.json"
}

test_ensure_meta_file_file_missing_creates_with_defaults() {
	file="$HOME/.password-store/bar.com/.site.meta.json"
	make_dir() { append_call "make_dir $1"; }
	meta_file_exists() {
		append_call "meta_file_exists $1"
		return 1
	}
	write_default_meta_file() { append_call "write_default_meta_file $1"; }
	register_stub make_dir
	register_stub meta_file_exists
	register_stub write_default_meta_file
	run ensure_meta_file "bar.com"
	assert_success
	assert_calls "$(printf '%s\n%s\n%s' \
		"make_dir $HOME/.password-store/bar.com" \
		"meta_file_exists $file" \
		"write_default_meta_file $file")"
}

test_ensure_meta_file_file_exists_skips_write() {
	file="$HOME/.password-store/bar.com/.site.meta.json"
	make_dir() { append_call "make_dir $1"; }
	meta_file_exists() {
		append_call "meta_file_exists $1"
		return 0
	}
	write_default_meta_file() { append_call "write_default_meta_file $1"; }
	register_stub make_dir
	register_stub meta_file_exists
	register_stub write_default_meta_file
	run ensure_meta_file "bar.com"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"make_dir $HOME/.password-store/bar.com" \
		"meta_file_exists $file")"
}

test_store_temp_path_returns_path_inside_git_dir() {
	run_with_output store_temp_path foo
	assert_output "$HOME/.password-store/.git/passs-foo"
}

test_ensure_line_line_missing_appends_on_new_line() {
	file="$SHUNIT_TMPDIR/missing"
	printf 'foo' >"$file"
	run ensure_line "$file" "bar"
	assert_success
	assertEquals "foo
bar" "$(cat "$file")"
}

test_ensure_line_line_present_leaves_file_unchanged() {
	file="$SHUNIT_TMPDIR/present"
	printf 'bar\nfoo\n' >"$file"
	run ensure_line "$file" "bar"
	assert_success
	assertEquals "bar
foo" "$(cat "$file")"
}

test_ensure_line_file_absent_creates_file() {
	file="$SHUNIT_TMPDIR/absent"
	run ensure_line "$file" "bar"
	assert_success
	assertEquals "bar" "$(cat "$file")"
}

test_commit_store_change_add_succeeds_commits_only_given_paths() {
	store_git() { append_call "store_git $*"; }
	register_stub store_git
	run commit_store_change "foo" bar.com/.site.meta.json baz.com/.site.meta.json
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"store_git add -- bar.com/.site.meta.json baz.com/.site.meta.json" \
		"store_git commit -m foo -- bar.com/.site.meta.json baz.com/.site.meta.json")"
}

test_commit_store_change_add_fails_skips_commit() {
	store_git() {
		append_call "store_git $*"
		return 1
	}
	register_stub store_git
	run commit_store_change "foo" bar.com/.site.meta.json
	assert_failure
	assert_calls "store_git add -- bar.com/.site.meta.json"
}

test_add_tag_tag_is_new_appends_and_commits() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_entry_change_success
	meta_has_tag() { return 1; }
	append_meta_tag() {
		append_call "append_meta_tag $1 $2"
		return 0
	}
	register_stub meta_has_tag
	register_stub append_meta_tag
	run add_tag "bar.com" "foo"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"append_meta_tag $file foo" \
		"commit_entry_change Add tag 'foo' for bar.com $file")"
}

test_add_tag_tag_exists_reports_already_exists() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	meta_has_tag() { return 0; }
	register_stub meta_has_tag
	run_with_output add_tag "bar.com" "foo"
	assert_success
	assert_output "Tag 'foo' already exists in $file"
}

test_add_tag_commit_fails_returns_failure() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_entry_change_failure
	meta_has_tag() { return 1; }
	append_meta_tag() {
		append_call "append_meta_tag $1 $2"
		return 0
	}
	register_stub meta_has_tag
	register_stub append_meta_tag
	run add_tag "bar.com" "foo"
	assert_failure
	assert_calls "$(printf '%s\n%s' \
		"append_meta_tag $file foo" \
		"commit_entry_change Add tag 'foo' for bar.com $file")"
}

test_add_description_description_matches_reports_already_set() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	meta_description() { printf '%s\n' "foo"; }
	register_stub meta_description
	run_with_output add_description "bar.com" "foo"
	assert_success
	assert_output "Description already set to 'foo' for bar.com"
}

test_add_description_description_missing_adds_and_commits() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_entry_change_success
	meta_description() { printf '\n'; }
	set_meta_description() {
		append_call "set_meta_description $1 $2"
		return 0
	}
	register_stub meta_description
	register_stub set_meta_description
	run add_description "bar.com" "bar"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"set_meta_description $file bar" \
		"commit_entry_change Add description for bar.com $file")"
}

test_add_description_description_differs_updates_and_commits() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_entry_change_success
	meta_description() { printf '%s\n' "foo"; }
	set_meta_description() {
		append_call "set_meta_description $1 $2"
		return 0
	}
	register_stub meta_description
	register_stub set_meta_description
	run add_description "bar.com" "bar"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"set_meta_description $file bar" \
		"commit_entry_change Update description for bar.com $file")"
}

test_add_description_commit_fails_returns_failure() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_entry_change_failure
	meta_description() { printf '%s\n' "foo"; }
	set_meta_description() {
		append_call "set_meta_description $1 $2"
		return 0
	}
	register_stub meta_description
	register_stub set_meta_description
	run add_description "bar.com" "bar"
	assert_failure
	assert_calls "$(printf '%s\n%s' \
		"set_meta_description $file bar" \
		"commit_entry_change Update description for bar.com $file")"
}

test_get_description_description_set_prints_description() {
	file="$TEST_ROOT/meta.json"
	stub_meta_file "$file"
	meta_file_exists() { return 0; }
	meta_description() { printf '%s\n' "foo"; }
	register_stub meta_file_exists
	register_stub meta_description
	run_with_output get_description "bar.com"
	assert_success
	assert_output "foo"
}

test_get_description_file_missing_returns_failure() {
	stub_meta_file "$TEST_ROOT/missing.json"
	meta_file_exists() { return 1; }
	register_stub meta_file_exists
	run_with_output get_description "bar.com"
	assert_failure
	assert_output ""
}

test_get_description_description_empty_returns_failure() {
	file="$TEST_ROOT/meta.json"
	stub_meta_file "$file"
	meta_file_exists() { return 0; }
	meta_description() { printf '\n'; }
	register_stub meta_file_exists
	register_stub meta_description
	run_with_output get_description "bar.com"
	assert_failure
	assert_output ""
}

test_list_by_tag_entries_match_prints_names() {
	metadata_files() {
		printf '%s\n' \
			"$HOME/.password-store/bar.com/.site.meta.json" \
			"$HOME/.password-store/baz.com/.site.meta.json"
	}
	meta_matches_tag() {
		[ "$1" = "$HOME/.password-store/bar.com/.site.meta.json" ]
	}
	register_stub metadata_files
	register_stub meta_matches_tag
	run_with_output list_by_tag "foo"
	assert_output "bar.com"
}

test_list_by_tag_store_empty_produces_no_output() {
	metadata_files() { return 0; }
	register_stub metadata_files
	run_with_output list_by_tag "foo"
	assert_success
	assert_output ""
}

test_list_by_tag_no_entries_match_produces_no_output() {
	metadata_files() { printf '%s\n' "$HOME/.password-store/bar.com/.site.meta.json"; }
	meta_matches_tag() { return 1; }
	register_stub metadata_files
	register_stub meta_matches_tag
	run_with_output list_by_tag "foo"
	assert_failure
	assert_output ""
}

test_lint_subdomain_folder_found_reports_error_and_remediation() {
	top_level_dirs() {
		printf '%s\n' \
			"$HOME/.password-store/foo.bar.baz.com" \
			"$HOME/.password-store/foo.bar.com" \
			"$HOME/.password-store/foo.ac.uk" \
			"$HOME/.password-store/bar.co.uk" \
			"$HOME/.password-store/192.168.0.1"
	}
	top_level_gpg_files() { return 0; }
	web_entries() { return 0; }
	register_stub top_level_dirs
	register_stub top_level_gpg_files
	register_stub web_entries
	run_with_output lint
	assert_output "error: folder name 'foo.bar.baz.com' appears to contain subdomain at foo.bar.baz.com
error: folder name 'foo.bar.com' appears to contain subdomain at foo.bar.com
Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/foo."
}

test_lint_subdomain_folder_violations_emit_records() {
	top_level_dirs() {
		printf '%s\n' \
			"$HOME/.password-store/foo.bar.com" \
			"$HOME/.password-store/bar.com"
	}
	register_stub top_level_dirs
	run_with_output lint_subdomain_folder_name_violations
	assert_output "$(printf 'foo.bar.com\tfoo.bar.com')"
}

test_lint_subdomain_folder_message_formats_record() {
	run_with_output lint_subdomain_folder_name_message "$(printf 'foo.bar.com\tfoo.bar.com')"
	assert_success
	assert_output "error: folder name 'foo.bar.com' appears to contain subdomain at foo.bar.com"
}

test_lint_subdomain_folder_remediation_reports_overall_advice() {
	run_with_output lint_subdomain_folder_name_remediation
	assert_success
	assert_output "Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/foo."
}

test_lint_no_violations_found_produces_no_output() {
	top_level_dirs() { return 0; }
	top_level_gpg_files() { return 0; }
	web_entries() { return 0; }
	register_stub top_level_dirs
	register_stub top_level_gpg_files
	register_stub web_entries
	run_with_output lint
	assert_success
	assert_output ""
}

test_lint_gpg_at_top_level_gpg_file_found_reports_error_and_remediation() {
	top_level_gpg_files() { printf '%s\n' "$HOME/.password-store/foo.gpg"; }
	register_stub top_level_gpg_files
	run_with_output lint_rule_report gpg_at_top_level
	assert_output "error: file 'foo.gpg' is a .gpg file at the top level
Password files should live inside site folders, for example foo.bar.gpg -> foo.bar/password.gpg."
}

test_lint_gpg_at_top_level_no_gpg_files_produces_no_output() {
	top_level_gpg_files() { return 0; }
	register_stub top_level_gpg_files
	run_with_output lint_rule_report gpg_at_top_level
	assert_success
	assert_output ""
}

test_lint_gpg_at_top_level_violations_emit_records() {
	top_level_gpg_files() { printf '%s\n' "$HOME/.password-store/foo.gpg"; }
	register_stub top_level_gpg_files
	run_with_output lint_gpg_at_top_level_violations
	assert_success
	assert_output "$(printf 'foo.gpg\tfoo.gpg')"
}

test_lint_gpg_at_top_level_message_formats_record() {
	run_with_output lint_gpg_at_top_level_message "$(printf 'foo.gpg\tfoo.gpg')"
	assert_success
	assert_output "error: file 'foo.gpg' is a .gpg file at the top level"
}

test_lint_rules_lists_registered_rule_ids() {
	run_with_output lint_rules
	assert_success
	assert_output "subdomain_folder_name
gpg_at_top_level
redundant_address
leaked_id
non_address_folder"
}

test_lint_rule_report_reports_rule_advice() {
	top_level_dirs() { printf '%s\n' "$HOME/.password-store/foo.bar.com"; }
	register_stub top_level_dirs
	run_with_output lint_rule_report subdomain_folder_name
	assert_success
	assert_output "error: folder name 'foo.bar.com' appears to contain subdomain at foo.bar.com
Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/foo."
}

test_passs_script_lint_defines_rules_before_running_main() {
	run_passs_lint_from_source() {
		find() {
			case " $* " in
			*" -type d "*) printf '%s\n' "$HOME/.password-store" "$HOME/.password-store/foo.bar.com" ;;
			*" -maxdepth 1 "*) return 0 ;;
			*) return 1 ;;
			esac
		}

		for rule in $(lint_rules); do
			unset -f "lint_${rule}_violations"
			unset -f "lint_${rule}_message"
			unset -f "lint_${rule}_remediation"
			unset -f "lint_${rule}_fix"
		done

		set -- lint
		PASSS_TESTING=0 . ./passs.sh
	}
	register_stub run_passs_lint_from_source

	run_with_output run_passs_lint_from_source
	assert_success
	assert_output "error: folder name 'foo.bar.com' appears to contain subdomain at foo.bar.com
Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/foo."
}

test_top_level_gpg_files_vault_present_searches_store_and_vault() {
	stub_store_in_tmpdir rooted
	touch "$STUB_STORE_DIR/foo.gpg" "$STUB_STORE_DIR/vault/bar.gpg"
	mkdir -p "$STUB_STORE_DIR/vault/baz.com" && touch "$STUB_STORE_DIR/vault/baz.com/qux.gpg"
	run_with_output top_level_gpg_files
	assert_success
	assert_output "$(printf '%s\n%s' "$STUB_STORE_DIR/foo.gpg" "$STUB_STORE_DIR/vault/bar.gpg")"
}

test_top_level_dirs_vault_present_lists_children_of_each_root() {
	stub_store_in_tmpdir listing
	mkdir -p "$STUB_STORE_DIR/foo.com/bar" "$STUB_STORE_DIR/vault/baz.com/qux"
	run_with_output top_level_dirs
	assert_success
	assertEquals "$(printf '%s\n' \
		"$STUB_STORE_DIR/.git" \
		"$STUB_STORE_DIR/foo.com" \
		"$STUB_STORE_DIR/vault" \
		"$STUB_STORE_DIR/vault/baz.com" | sort)" "$(printf '%s\n' "$TEST_OUTPUT" | sort)"
}

test_lint_roots_vault_absent_lists_store_only() {
	stub_store_in_tmpdir unrooted
	rmdir "$STUB_STORE_DIR/vault"
	run_with_output lint_roots
	assert_output "$STUB_STORE_DIR"
}

test_lint_subdomain_folder_vault_folder_emits_record() {
	top_level_dirs() {
		printf '%s\n' \
			"$HOME/.password-store/vault" \
			"$HOME/.password-store/vault/foo.bar.com"
	}
	register_stub top_level_dirs
	run_with_output lint_subdomain_folder_name_violations
	assert_output "$(printf 'foo.bar.com\tvault/foo.bar.com')"
}

test_lint_gpg_at_top_level_message_vault_file_shows_path() {
	run_with_output lint_gpg_at_top_level_message "$(printf 'foo.gpg\tvault/foo.gpg')"
	assert_output "error: file 'vault/foo.gpg' is a .gpg file at the top level"
}

test_lint_gpg_at_top_level_fix_vault_file_moves_within_vault() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	make_dir() { append_call "make_dir $1"; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run lint_gpg_at_top_level_fix "$(printf 'foo.gpg\tvault/foo.gpg')"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"make_dir $TEST_ROOT/store/vault/foo" \
		"move_file $TEST_ROOT/store/vault/foo.gpg $TEST_ROOT/store/vault/foo/password.gpg")"
}

test_lint_subdomain_folder_name_fix_vault_folder_nests_within_vault() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	make_dir() { append_call "make_dir $1"; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run lint_subdomain_folder_name_fix "$(printf 'foo.bar.com\tvault/foo.bar.com')"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"make_dir $TEST_ROOT/store/vault/bar.com" \
		"move_file $TEST_ROOT/store/vault/foo.bar.com $TEST_ROOT/store/vault/bar.com/foo")"
}

test_lint_rule_fix_without_fix_function_returns_success() {
	run_with_output lint_rule_fix missing "$(printf 'foo\tfoo')"
	assert_success
	assert_output ""
}

test_lint_gpg_at_top_level_fix_target_absent_moves_into_folder() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	make_dir() {
		append_call "make_dir $1"
		return 0
	}
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run lint_gpg_at_top_level_fix "$(printf 'foo.gpg\tfoo.gpg')"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"make_dir $TEST_ROOT/store/foo" \
		"move_file $TEST_ROOT/store/foo.gpg $TEST_ROOT/store/foo/password.gpg")"
}

test_lint_gpg_at_top_level_fix_target_absent_reports_change() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	make_dir() { return 0; }
	move_file() { return 0; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run_with_output lint_gpg_at_top_level_fix "$(printf 'foo.gpg\tfoo.gpg')"
	assert_success
	assert_output "fixed: moved 'foo.gpg' to 'foo/password.gpg'"
}

test_lint_gpg_at_top_level_fix_target_exists_refuses_to_overwrite() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 0; }
	make_dir() { append_call "make_dir $1"; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run_with_output lint_gpg_at_top_level_fix "$(printf 'foo.gpg\tfoo.gpg')"
	assert_success
	assert_output "error: cannot fix 'foo.gpg', 'foo/password.gpg' already exists"
	assert_calls ""
}

test_subdomain_to_nested_path_three_labels_nests_under_registrable() {
	run_with_output subdomain_to_nested_path "foo.bar.com"
	assert_success
	assert_output "bar.com/foo"
}

test_subdomain_to_nested_path_four_labels_nests_each_label_in_reverse() {
	run_with_output subdomain_to_nested_path "foo.bar.baz.com"
	assert_success
	assert_output "baz.com/bar/foo"
}

test_lint_subdomain_folder_name_fix_target_absent_moves_into_nested_path() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	make_dir() {
		append_call "make_dir $1"
		return 0
	}
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run lint_subdomain_folder_name_fix "$(printf 'foo.bar.baz.com\tfoo.bar.baz.com')"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"make_dir $TEST_ROOT/store/baz.com/bar" \
		"move_file $TEST_ROOT/store/foo.bar.baz.com $TEST_ROOT/store/baz.com/bar/foo")"
}

test_lint_subdomain_folder_name_fix_target_absent_reports_change() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	make_dir() { return 0; }
	move_file() { return 0; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run_with_output lint_subdomain_folder_name_fix "$(printf 'foo.bar.baz.com\tfoo.bar.baz.com')"
	assert_success
	assert_output "fixed: moved 'foo.bar.baz.com' to 'baz.com/bar/foo'"
}

test_lint_subdomain_folder_name_fix_target_exists_refuses_to_overwrite() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 0; }
	make_dir() { append_call "make_dir $1"; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub make_dir
	register_stub move_file
	run_with_output lint_subdomain_folder_name_fix "$(printf 'foo.bar.com\tfoo.bar.com')"
	assert_success
	assert_output "error: cannot fix 'foo.bar.com', 'bar.com/foo' already exists"
	assert_calls ""
}

test_lint_fix_routes_violations_to_fix_function() {
	lint_rules() { printf '%s\n' foo; }
	lint_foo_violations() {
		printf '%s\n' \
			"first" \
			"second"
	}
	lint_foo_fix() {
		printf 'lint_foo_fix %s\n' "$1"
	}
	register_stub lint_rules
	register_stub lint_foo_violations
	register_stub lint_foo_fix
	run_with_output lint_fix
	assert_success
	assert_output "$(printf '%s\n%s' \
		"lint_foo_fix first" \
		"lint_foo_fix second")"
}

test_user_full_name_returns_first_gecos_field() {
	getent() { printf '%s\n' 'foo:x:1000:1000:Foo Bar,1,2,3:/home/foo:/bin/sh'; }
	register_stub getent
	run_with_output user_full_name
	assert_success
	assert_output "Foo Bar"
}

test_web_entries_lists_entries_under_web_address_folders_only() {
	stub_store_in_tmpdir web
	mkdir -p "$STUB_STORE_DIR/foo.com/bar" "$STUB_STORE_DIR/codes" "$STUB_STORE_DIR/vault/baz.com"
	touch "$STUB_STORE_DIR/foo.com/qux.gpg" "$STUB_STORE_DIR/foo.com/bar/baz.gpg" \
		"$STUB_STORE_DIR/codes/qux.gpg" "$STUB_STORE_DIR/qux.com.gpg" \
		"$STUB_STORE_DIR/vault/baz.com/qux.gpg" "$STUB_STORE_DIR/.git/qux.gpg"
	TEST_OUTPUT="$(web_entries | sort)"
	assert_output "foo.com/bar/baz
foo.com/qux"
}

test_web_entries_lists_owned_host_entries_except_port_names() {
	stub_store_in_tmpdir owned
	mkdir -p "$STUB_STORE_DIR/owned/foo/:22"
	touch "$STUB_STORE_DIR/owned/qux.gpg" "$STUB_STORE_DIR/owned/foo/bar.gpg" \
		"$STUB_STORE_DIR/owned/foo/:22/baz.gpg" "$STUB_STORE_DIR/owned/foo/:80.gpg"
	TEST_OUTPUT="$(web_entries | sort)"
	assert_output "owned/foo/:22/baz
owned/foo/bar"
}

test_host_folders_pattern_joins_folders_as_alternatives() {
	host_folders() { printf '%s\n' owned qux; }
	register_stub host_folders
	run_with_output host_folders_pattern
	assert_success
	assert_output "owned|qux"
}

test_path_without_host_folder_and_ports_any_host_folder_strips_prefix() {
	host_folders() { printf '%s\n' owned qux; }
	register_stub host_folders
	run_with_output path_without_host_folder_and_ports qux/foo/bar
	assert_output "foo/bar"
}

test_path_without_host_folder_and_ports_strips_owned_prefix_and_ports() {
	run_with_output path_without_host_folder_and_ports owned/foo.com/:22/bar
	assert_success
	assert_output "foo.com/bar"
}

test_looks_like_id_unrecognised_name_returns_success() {
	run looks_like_id x7Fq2 "Foo Bar"
	assert_success
}

test_looks_like_id_email_returns_failure() {
	run looks_like_id qux@baz.com "Foo Bar"
	assert_failure
}

test_looks_like_id_hidden_credentials_returns_failure() {
	run looks_like_id hidden-credentials-12 "Foo Bar"
	assert_failure
}

test_looks_like_id_generic_word_in_any_case_returns_failure() {
	run looks_like_id Administrator "Foo Bar"
	assert_failure
}

test_looks_like_id_contains_name_part_in_any_case_returns_failure() {
	run looks_like_id qfoobar "Foo Bar"
	assert_failure
}

test_looks_like_id_contains_shortened_name_returns_success() {
	run looks_like_id BA1234 "Foo Bar"
	assert_success
}

test_looks_like_id_user_name_empty_returns_success() {
	run looks_like_id x7Fq2 ""
	assert_success
}

test_lint_leaked_id_violations_emit_records_for_ids_only() {
	web_entries() { printf '%s\n' foo.com/x7Fq2 foo.com/bar/foo baz.com/qux@baz.com; }
	user_full_name() { echo "Foo Bar"; }
	register_stub web_entries
	register_stub user_full_name
	run_with_output lint_leaked_id_violations
	assert_output "$(printf 'x7Fq2\tfoo.com/x7Fq2')"
}

test_lint_leaked_id_message_formats_record() {
	run_with_output lint_leaked_id_message "$(printf 'x7Fq2\tfoo.com/x7Fq2')"
	assert_success
	assert_output "error: entry name 'x7Fq2' appears to be an id at foo.com/x7Fq2"
}

test_lint_leaked_id_remediation_reports_overall_advice() {
	run_with_output lint_leaked_id_remediation
	assert_success
	assert_output "Entry names aren't encrypted, so they shouldn't contain ids. Move the id into the entry, for example foo.com/bar -> foo.com/hidden-credentials-1 with 'login: bar' after the password, or into the vault."
}

test_lint_leaked_id_fix_write_succeeds_writes_new_entry_then_removes_old() {
	next_secret_entry() { printf '%s/hidden-credentials-2\n' "$1"; }
	register_stub next_secret_entry
	stub_recording write_secret_entry pass_dispatch
	run lint_leaked_id_fix "$(printf 'x7Fq2\tfoo.com/bar/x7Fq2')"
	assert_success
	assert_calls "$(printf '%s\n%s' \
		"write_secret_entry foo.com/bar/x7Fq2 foo.com/bar/hidden-credentials-2 x7Fq2" \
		"pass_dispatch rm -f foo.com/bar/x7Fq2")"
}

test_lint_leaked_id_fix_write_succeeds_reports_change() {
	next_secret_entry() { printf '%s/hidden-credentials-2\n' "$1"; }
	write_secret_entry() { :; }
	pass_dispatch() { :; }
	register_stub next_secret_entry
	register_stub write_secret_entry
	register_stub pass_dispatch
	run_with_output lint_leaked_id_fix "$(printf 'x7Fq2\tfoo.com/x7Fq2')"
	assert_success
	assert_output "fixed: moved 'foo.com/x7Fq2' to 'foo.com/hidden-credentials-2' with its id"
}

test_lint_leaked_id_fix_write_fails_keeps_old_entry() {
	next_secret_entry() { printf '%s/hidden-credentials-2\n' "$1"; }
	register_stub next_secret_entry
	stub_failing write_secret_entry
	stub_recording pass_dispatch
	run lint_leaked_id_fix "$(printf 'x7Fq2\tfoo.com/x7Fq2')"
	assert_failure
	assert_calls "write_secret_entry foo.com/x7Fq2 foo.com/hidden-credentials-2 x7Fq2"
}

test_repeated_site_address_address_in_name_prints_address() {
	run_with_output repeated_site_address foo.com/bar.foo.com
	assert_output "foo.com"
}

test_repeated_site_address_subdomain_folder_prints_longest_address() {
	run_with_output repeated_site_address foo.com/baz/bar@baz.foo.com
	assert_output "baz.foo.com"
}

test_repeated_site_address_no_address_in_name_prints_nothing() {
	run_with_output repeated_site_address foo.com/bar@foo.net
	assert_output ""
}

test_has_redundant_address_address_in_name_returns_success() {
	repeated_site_address() { echo foo.com; }
	register_stub repeated_site_address
	run has_redundant_address foo.com/bar.foo.com
	assert_success
}

test_has_redundant_address_email_address_returns_failure() {
	repeated_site_address() { echo foo.com; }
	register_stub repeated_site_address
	run has_redundant_address foo.com/bar@foo.com
	assert_failure
}

test_has_redundant_address_name_is_label_in_any_case_returns_success() {
	repeated_site_address() { :; }
	register_stub repeated_site_address
	run has_redundant_address foo.com/Foo
	assert_success
}

test_has_redundant_address_label_inside_name_returns_failure() {
	repeated_site_address() { :; }
	register_stub repeated_site_address
	run has_redundant_address foo.com/barfoo
	assert_failure
}

test_redundant_address_fixed_name_address_at_end_strips_address_and_separator() {
	repeated_site_address() { echo foo.com; }
	register_stub repeated_site_address
	run_with_output redundant_address_fixed_name foo.com/bar.foo.com
	assert_output "bar"
}

test_redundant_address_fixed_name_address_in_middle_joins_remainder() {
	repeated_site_address() { echo foo.com; }
	register_stub repeated_site_address
	run_with_output redundant_address_fixed_name foo.com/bar.foo.com-baz
	assert_output "barbaz"
}

test_redundant_address_fixed_name_whole_name_is_address_returns_user() {
	repeated_site_address() { echo foo.com; }
	register_stub repeated_site_address
	run_with_output redundant_address_fixed_name foo.com/foo.com
	assert_output "user"
}

test_redundant_address_fixed_name_no_address_returns_user() {
	repeated_site_address() { :; }
	register_stub repeated_site_address
	run_with_output redundant_address_fixed_name foo.com/foo
	assert_output "user"
}

test_lint_redundant_address_violations_emit_records_for_repeats_only() {
	web_entries() { printf '%s\n' foo.com/bar.foo.com foo.com/baz; }
	register_stub web_entries
	run_with_output lint_redundant_address_violations
	assert_output "$(printf 'bar.foo.com\tfoo.com/bar.foo.com')"
}

test_lint_redundant_address_violations_owned_entry_ignores_owned_and_port() {
	web_entries() { printf '%s\n' owned/foo.com/:22/bar.foo.com owned/baz/:22/qux; }
	register_stub web_entries
	run_with_output lint_redundant_address_violations
	assert_output "$(printf 'bar.foo.com\towned/foo.com/:22/bar.foo.com')"
}

test_lint_redundant_address_message_formats_record() {
	run_with_output lint_redundant_address_message "$(printf 'bar.foo.com\tfoo.com/bar.foo.com')"
	assert_success
	assert_output "error: entry name 'bar.foo.com' repeats its site address at foo.com/bar.foo.com"
}

test_lint_redundant_address_remediation_reports_overall_advice() {
	run_with_output lint_redundant_address_remediation
	assert_success
	assert_output "Entry names shouldn't repeat the site they're filed under, for example foo.com/bar.foo.com -> foo.com/bar, or foo.com/foo.com -> foo.com/user."
}

test_lint_redundant_address_fix_target_absent_renames_entry() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub move_file
	run lint_redundant_address_fix "$(printf 'bar.foo.com\tfoo.com/bar.foo.com')"
	assert_success
	assert_calls "move_file $TEST_ROOT/store/foo.com/bar.foo.com.gpg $TEST_ROOT/store/foo.com/bar.gpg"
}

test_lint_redundant_address_fix_owned_entry_renames_within_port_folder() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub move_file
	run lint_redundant_address_fix "$(printf 'bar.foo.com\towned/foo.com/:22/bar.foo.com')"
	assert_success
	assert_calls "move_file $TEST_ROOT/store/owned/foo.com/:22/bar.foo.com.gpg $TEST_ROOT/store/owned/foo.com/:22/bar.gpg"
}

test_lint_redundant_address_fix_target_absent_reports_change() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 1; }
	move_file() { return 0; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub move_file
	run_with_output lint_redundant_address_fix "$(printf 'foo.com\tfoo.com/foo.com')"
	assert_success
	assert_output "fixed: moved 'foo.com/foo.com' to 'foo.com/user'"
}

test_lint_redundant_address_fix_target_exists_refuses_to_overwrite() {
	password_store_dir() { printf '%s\n' "$TEST_ROOT/store"; }
	path_exists() { return 0; }
	move_file() { append_call "move_file $1 $2"; }
	register_stub password_store_dir
	register_stub path_exists
	register_stub move_file
	run_with_output lint_redundant_address_fix "$(printf 'foo.com\tfoo.com/foo.com')"
	assert_success
	assert_output "error: cannot fix 'foo.com/foo.com', 'foo.com/user' already exists"
	assert_calls ""
}

test_lint_non_address_folder_violations_emit_records_for_non_addresses_only() {
	top_level_dirs() {
		printf '%s\n' \
			"$HOME/.password-store/foo" \
			"$HOME/.password-store/foo bar" \
			"$HOME/.password-store/foo.com" \
			"$HOME/.password-store/192.168.0.1" \
			"$HOME/.password-store/.git" \
			"$HOME/.password-store/vault" \
			"$HOME/.password-store/vault/baz" \
			"$HOME/.password-store/local" \
			"$HOME/.password-store/encrypt" \
			"$HOME/.password-store/owned" \
			"$HOME/.password-store/tokens" \
			"$HOME/.password-store/codes" \
			"$HOME/.password-store/devices"
	}
	register_stub top_level_dirs
	run_with_output lint_non_address_folder_violations
	assert_output "$(printf '%s\t%s\n%s\t%s\n%s\t%s' \
		foo foo "foo bar" "foo bar" baz vault/baz)"
}

test_lint_non_address_folder_message_formats_record() {
	run_with_output lint_non_address_folder_message "$(printf 'foo\tvault/foo')"
	assert_success
	assert_output "error: folder name 'foo' isn't a web address at vault/foo"
}

test_lint_non_address_folder_remediation_reports_overall_advice() {
	run_with_output lint_non_address_folder_remediation
	assert_success
	assert_output "Top-level folders should be web addresses, for example foo -> foo.com, apart from local, encrypt, owned, tokens, codes and devices."
}

test_passs_main_version_flag_prints_version() {
	run_with_output passs_main version
	assert_success
	assert_output "pass wrapper v$VERSION"
}

test_passs_main_help_flags_print_help() {
	for flag in help -h --help; do
		run_with_output passs_main "$flag"
		assert_success
		assert_output_contains "Usage: passs <command> [args]"
		assert_output_contains "Entries under vault/ are committed as one encrypted file (.vault.enc)"
		assert_output_contains "For all other functionality, call pass directly (see 'pass help')."
	done
}

test_passs_main_tag_command_routes_to_add_tag() {
	add_tag() {
		printf 'add_tag %s %s\n' "$1" "$2"
	}
	register_stub add_tag
	run_with_output passs_main tag "bar.com" "foo"
	assert_success
	assert_output "add_tag bar.com foo"
}

test_passs_main_tag_list_command_routes_to_list_by_tag() {
	list_by_tag() {
		printf 'list_by_tag %s\n' "$1"
	}
	register_stub list_by_tag
	run_with_output passs_main tag list "foo"
	assert_success
	assert_output "list_by_tag foo"
}

test_passs_main_description_get_command_routes_to_get_description() {
	get_description() {
		printf 'get_description %s\n' "$1"
	}
	register_stub get_description
	run_with_output passs_main description get "bar.com"
	assert_success
	assert_output "get_description bar.com"
}

test_passs_main_description_add_command_routes_to_add_description() {
	add_description() {
		printf 'add_description %s %s\n' "$1" "$2"
	}
	register_stub add_description
	run_with_output passs_main description "bar.com" "bar"
	assert_success
	assert_output "add_description bar.com bar"
}

test_passs_main_lint_command_routes_to_lint() {
	lint() {
		printf 'lint\n'
	}
	register_stub lint
	run_with_output passs_main lint
	assert_success
	assert_output "lint"
}

test_passs_main_lint_fix_flag_routes_to_lint_then_lint_fix() {
	lint() {
		printf 'lint\n'
	}
	lint_fix() {
		printf 'lint_fix\n'
	}
	register_stub lint
	register_stub lint_fix
	run_with_output passs_main lint --fix
	assert_success
	assert_output "lint
lint_fix"
}

test_passs_main_lint_fix_flag_reports_lint_when_nothing_is_fixed() {
	lint() {
		printf 'lint errors\n'
	}
	lint_fix() {
		return 0
	}
	register_stub lint
	register_stub lint_fix
	run_with_output passs_main lint --fix
	assert_success
	assert_output "lint errors"
}

test_passs_main_lint_fix_word_routes_to_lint() {
	lint() {
		printf 'lint\n'
	}
	lint_fix() {
		printf 'lint_fix\n'
	}
	register_stub lint
	register_stub lint_fix
	run_with_output passs_main lint fix
	assert_success
	assert_output "lint"
}

test_passs_main_unknown_command_delegates_to_pass() {
	pass() {
		printf 'pass %s %s\n' "$1" "$2"
	}
	register_stub pass
	run_with_output passs_main show "bar.com"
	assert_success
	assert_output "pass show bar.com"
}

test_passs_main_tag_too_few_args_shows_usage() {
	run_with_output passs_main tag "bar.com"
	assert_failure
	assert_output "Usage: passs tag pass-name <tag>"
}

test_passs_main_tag_list_too_few_args_shows_usage() {
	run_with_output passs_main tag list
	assert_failure
	assert_output "Usage: passs tag list <tag>"
}

test_passs_main_description_get_too_few_args_shows_usage() {
	run_with_output passs_main description get
	assert_failure
	assert_output "Usage: passs description get pass-name"
}

test_passs_main_description_add_too_few_args_shows_usage() {
	run_with_output passs_main description "bar.com"
	assert_failure
	assert_output "Usage: passs description pass-name <description>"
}

. "$(command -v shunit2 || echo /usr/share/shunit2/shunit2)"
