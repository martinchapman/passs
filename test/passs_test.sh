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

test_commit_meta_change_git_succeeds_returns_success() {
	stub_git_success
	run_with_output commit_meta_change "bar.com/.site.meta.json" "foo"
	assert_success
	assert_output ""
}

test_commit_meta_change_git_add_fails_returns_failure() {
	stub_git_add_failure
	run_with_output commit_meta_change "bar.com/.site.meta.json" "foo"
	assert_failure
	assert_output ""
}

test_add_tag_tag_is_new_appends_and_commits() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_meta_change_success
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
		"commit_meta_change $file Add tag 'foo' for bar.com")"
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
	stub_commit_meta_change_failure
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
		"commit_meta_change $file Add tag 'foo' for bar.com")"
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
	stub_commit_meta_change_success
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
		"commit_meta_change $file Add description for bar.com")"
}

test_add_description_description_differs_updates_and_commits() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_meta_change_success
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
		"commit_meta_change $file Update description for bar.com")"
}

test_add_description_commit_fails_returns_failure() {
	file="$TEST_ROOT/meta.json"
	stub_ensure_meta_file "$file"
	stub_commit_meta_change_failure
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
		"commit_meta_change $file Update description for bar.com")"
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
	password_store_dirs() {
		printf '%s\n' \
			"$HOME/.password-store" \
			"$HOME/.password-store/foo.bar.baz.com" \
			"$HOME/.password-store/foo.bar.com" \
			"$HOME/.password-store/foo.ac.uk" \
			"$HOME/.password-store/bar.co.uk" \
			"$HOME/.password-store/192.168.0.1" \
			"$HOME/.password-store/bar.com/baz"
	}
	top_level_gpg_files() { return 0; }
	register_stub password_store_dirs
	register_stub top_level_gpg_files
	run_with_output lint
	assert_output "error: folder name 'foo.bar.baz.com' appears to contain subdomain at foo.bar.baz.com
error: folder name 'foo.bar.com' appears to contain subdomain at foo.bar.com
Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/app.
Password files should live inside site folders, for example foo.bar.gpg -> foo.bar.gpg/password.gpg."
}

test_lint_subdomain_folder_violations_emit_records() {
	password_store_dirs() {
		printf '%s\n' \
			"$HOME/.password-store" \
			"$HOME/.password-store/foo.bar.com" \
			"$HOME/.password-store/bar.com/baz"
	}
	register_stub password_store_dirs
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
	assert_output "Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/app."
}

test_lint_no_violations_found_reports_remediation() {
	password_store_dirs() { printf '%s\n' "$HOME/.password-store"; }
	top_level_gpg_files() { return 0; }
	register_stub password_store_dirs
	register_stub top_level_gpg_files
	run_with_output lint
	assert_success
	assert_output "Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/app.
Password files should live inside site folders, for example foo.bar.gpg -> foo.bar.gpg/password.gpg."
}

test_lint_gpg_at_top_level_gpg_file_found_reports_error_and_remediation() {
	top_level_gpg_files() { printf '%s\n' "$HOME/.password-store/foo.gpg"; }
	register_stub top_level_gpg_files
	run_with_output lint_rule_report gpg_at_top_level
	assert_output "error: file 'foo.gpg' is a .gpg file at the top level
Password files should live inside site folders, for example foo.bar.gpg -> foo.bar.gpg/password.gpg."
}

test_lint_gpg_at_top_level_no_gpg_files_reports_remediation() {
	top_level_gpg_files() { return 0; }
	register_stub top_level_gpg_files
	run_with_output lint_rule_report gpg_at_top_level
	assert_success
	assert_output "Password files should live inside site folders, for example foo.bar.gpg -> foo.bar.gpg/password.gpg."
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
gpg_at_top_level"
}

test_lint_rule_report_reports_rule_advice() {
	password_store_dirs() { printf '%s\n' "$HOME/.password-store"; }
	register_stub password_store_dirs
	run_with_output lint_rule_report subdomain_folder_name
	assert_success
	assert_output "Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/app."
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
Top-level folders should be registrable domains. Put subdomains underneath the parent domain instead, for example foo.bar.com -> bar.com/app.
Password files should live inside site folders, for example foo.bar.gpg -> foo.bar/password.gpg."
}

test_passs_main_version_flag_prints_version() {
	run_with_output passs_main version
	assert_success
	assert_output "pass wrapper v$VERSION"
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
