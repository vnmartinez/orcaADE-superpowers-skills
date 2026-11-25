#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MANIFEST_JSON="$REPO_ROOT/plugin/manifest.json"
MINIMAL_AGENTS_FIXTURE="$REPO_ROOT/tests/fixtures/plugin-agents-minimal.json"
INSTALLER_SH="$REPO_ROOT/scripts/install-skills.sh"
PLUGIN_README="$REPO_ROOT/plugin/README.md"
ROOT_README="$REPO_ROOT/README.md"

PASS=0
FAIL=0

TMP_DIRS=""
cleanup_tmp_dirs() {
  local d
  for d in $TMP_DIRS; do
    if [ -n "$d" ] && [ -d "$d" ]; then
      rm -rf "$d"
    fi
  done
}
trap cleanup_tmp_dirs EXIT

make_tmp_dir() {
  local d
  d="$(mktemp -d)"
  TMP_DIRS="$TMP_DIRS $d"
  printf '%s\n' "$d"
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$name" "$expected" "$actual" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s (missing=%s)\n' "$name" "$needle" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    printf 'FAIL: %s (unexpected=%s)\n' "$name" "$needle" >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

assert_exists() {
  local name="$1"
  local target="$2"
  if [ -e "$target" ] || [ -L "$target" ]; then
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s (missing=%s)\n' "$name" "$target" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_not_exists() {
  local name="$1"
  local target="$2"
  if [ -e "$target" ] || [ -L "$target" ]; then
    printf 'FAIL: %s (should not exist=%s)\n' "$name" "$target" >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

parse_manifest_awk() {
  awk '
    function fail(msg) {
      printf "ERROR: %s\n", msg > "/dev/stderr"
      err = 1
    }
    function on_token(type, val) {
      if (type == "{") {
        brace_bal++
        depth++
        ctype[depth] = "obj"
        ckey[depth] = pending_key
        pending_key = ""
        expect_val[depth] = 0
        if (depth == 2 && ckey[2] == "layout") in_layout = 1
        if (depth == 2 && ckey[2] == "agentPaths") in_agent_paths = 1
        if (in_agent_paths && depth == 3) {
          cur_agent = ckey[3]
          ag_global = ""
          ag_local = ""
        }
        return
      }
      if (type == "}") {
        if (in_agent_paths && depth == 3 && cur_agent != "") {
          printf "AGENT_PATH|%s|%s|%s\n", cur_agent, ag_global, ag_local
          cur_agent = ""
        }
        if (depth == 2 && in_layout) in_layout = 0
        if (depth == 2 && in_agent_paths) in_agent_paths = 0
        brace_bal--
        if (brace_bal < 0) fail("unbalanced }")
        delete ctype[depth]; delete ckey[depth]; delete expect_val[depth]
        depth--
        pending_key = ""
        return
      }
      if (type == "[") {
        bracket_bal++
        depth++
        ctype[depth] = "arr"
        ckey[depth] = pending_key
        pending_key = ""
        expect_val[depth] = 0
        if (depth == 2 && ckey[2] == "skills") in_skills = 1
        return
      }
      if (type == "]") {
        if (depth == 2 && in_skills) in_skills = 0
        bracket_bal--
        if (bracket_bal < 0) fail("unbalanced ]")
        delete ctype[depth]; delete ckey[depth]; delete expect_val[depth]
        depth--
        pending_key = ""
        return
      }
      if (type == ":") {
        expect_val[depth] = 1
        return
      }
      if (type == ",") {
        expect_val[depth] = 0
        pending_key = ""
        return
      }
      if (ctype[depth] == "obj" && !expect_val[depth] && type == "STR") {
        pending_key = val
        return
      }
      if (ctype[depth] == "arr" && in_skills && depth == 2 && type == "STR") {
        printf "SKILL|%s\n", val
        return
      }
      if (ctype[depth] == "obj" && expect_val[depth]) {
        if (depth == 1) {
          if (pending_key == "manifestVersion" || pending_key == "id" || pending_key == "name" || pending_key == "version" || pending_key == "repository" || pending_key == "license") {
            printf "META|%s|%s\n", pending_key, val
          }
        } else if (in_layout && depth == 2) {
          printf "LAYOUT|%s|%s\n", pending_key, val
        } else if (in_agent_paths && depth == 3) {
          if (pending_key == "global") ag_global = val
          else if (pending_key == "local") ag_local = val
        }
        expect_val[depth] = 0
        pending_key = ""
      }
    }
    function scan_line(txt,   n, i, ch, str, lit) {
      n = length(txt)
      i = 1
      while (i <= n) {
        ch = substr(txt, i, 1)
        if (in_str) {
          if (esc) { str = str ch; esc = 0 }
          else if (ch == "\\") { esc = 1 }
          else if (ch == "\"") { in_str = 0; on_token("STR", str); str = "" }
          else { str = str ch }
          i++; continue
        }
        if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") { i++; continue }
        if (ch == "\"") { in_str = 1; esc = 0; str = ""; i++; continue }
        if (ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == ",") {
          on_token(ch, ch); i++; continue
        }
        lit = ""
        while (i <= n) {
          ch = substr(txt, i, 1)
          if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n" || ch == "," || ch == "}" || ch == "]") break
          lit = lit ch; i++
        }
        if (lit != "") on_token("LIT", lit)
      }
    }
    BEGIN { depth = 0; brace_bal = 0; bracket_bal = 0; err = 0; in_str = 0; esc = 0 }
    { scan_line($0 "\n") }
    END {
      if (brace_bal != 0) fail("unbalanced braces at EOF")
      if (bracket_bal != 0) fail("unbalanced brackets at EOF")
      if (err) exit 1
      print "JSON_VALID|1"
    }
  ' "$MANIFEST_JSON"
}

test_manifest_exists_and_valid_json() {
  assert_exists "manifest_exists" "$MANIFEST_JSON"
  if [ ! -f "$MANIFEST_JSON" ]; then
    return
  fi
  local parsed status
  parsed="$(parse_manifest_awk 2>&1)"
  status=$?
  assert_eq "manifest_json_parse_exit" "0" "$status"
  assert_contains "manifest_json_valid" "JSON_VALID|1" "$parsed"
  assert_contains "manifest_version_1" "META|manifestVersion|1" "$parsed"
  assert_contains "manifest_id" "META|id|superpowers-skills" "$parsed"
  assert_contains "manifest_license" "META|license|MIT" "$parsed"
  assert_contains "manifest_shared_dir" "LAYOUT|sharedDir|.agents/skills" "$parsed"
  assert_contains "manifest_backup_dir" "LAYOUT|backupDir|.agents/.orca-superpowers-backups" "$parsed"
  assert_contains "manifest_state_file" "LAYOUT|stateFile|.agents/.orca-superpowers-installed" "$parsed"

  local ver
  ver="$(printf '%s\n' "$parsed" | awk -F'|' '$1=="META" && $2=="version" { print $3; exit }')"
  if printf '%s\n' "$ver" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf 'PASS: manifest_version_semver (%s)\n' "$ver"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: manifest_version_semver (actual=%s)\n' "$ver" >&2
    FAIL=$((FAIL + 1))
  fi
}

test_manifest_skills_match_repo_root() {
  if [ ! -f "$MANIFEST_JSON" ]; then
    printf 'FAIL: test_manifest_skills_match_repo_root (manifest missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local parsed skills count s
  parsed="$(parse_manifest_awk 2>/dev/null || true)"
  skills="$(printf '%s\n' "$parsed" | awk -F'|' '$1=="SKILL" { print $2 }')"
  count="$(printf '%s\n' "$skills" | awk 'NF { c++ } END { print c+0 }')"
  assert_eq "manifest_skill_count" "4" "$count"

  for s in \
    orca-superpowers-orchestrator \
    orca-superpowers-orchestration-auto \
    orca-superpowers-review-loop \
    orca-superpowers-merge
  do
    assert_contains "manifest_has_skill_$s" "$s" "$skills"
    assert_exists "repo_skill_md_$s" "$REPO_ROOT/$s/SKILL.md"
  done
}

test_manifest_agent_paths_complete() {
  if [ ! -f "$MANIFEST_JSON" ]; then
    printf 'FAIL: test_manifest_agent_paths_complete (manifest missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local parsed ag line ag_global ag_local
  parsed="$(parse_manifest_awk 2>/dev/null || true)"
  for ag in \
    claude antigravity cursor droid continue trae \
    grok aug zcode codebuddy kiro openclaude
  do
    line="$(printf '%s\n' "$parsed" | awk -F'|' -v a="$ag" '$1=="AGENT_PATH" && $2==a { print $0; exit }')"
    ag_global="$(printf '%s\n' "$line" | awk -F'|' '{ print $3 }')"
    ag_local="$(printf '%s\n' "$line" | awk -F'|' '{ print $4 }')"
    if [ -n "$ag_global" ] && [ -n "$ag_local" ]; then
      printf 'PASS: manifest_agent_path_%s\n' "$ag"
      PASS=$((PASS + 1))
    else
      printf 'FAIL: manifest_agent_path_%s (line=%s)\n' "$ag" "$line" >&2
      FAIL=$((FAIL + 1))
    fi
  done
  assert_contains "manifest_antigravity_paths" "AGENT_PATH|antigravity|.gemini/config/skills|.agents/skills" "$parsed"
}

test_manifest_and_fixture_no_pii_or_windows_paths() {
  assert_exists "fixture_minimal_exists" "$MINIMAL_AGENTS_FIXTURE"
  local combined=""
  if [ -f "$MANIFEST_JSON" ]; then
    combined="$combined
$(cat "$MANIFEST_JSON")"
  fi
  if [ -f "$MINIMAL_AGENTS_FIXTURE" ]; then
    combined="$combined
$(cat "$MINIMAL_AGENTS_FIXTURE")"
  fi
  assert_not_contains "no_pii_at" "@" "$combined"
  assert_not_contains "no_pii_org_uuid" "organizationUuid" "$combined"
  assert_not_contains "no_pii_win_users" 'C:\Users' "$combined"
  assert_not_contains "no_win_appdata" "%APPDATA%" "$combined"
  assert_not_contains "no_win_temp" "%TEMP%" "$combined"
  assert_not_contains "no_ps_userprofile" '$env:USERPROFILE' "$combined"
  assert_not_contains "no_backslash" '\' "$combined"
}

test_manifest_exists_and_valid_json
test_manifest_skills_match_repo_root
test_manifest_agent_paths_complete
test_manifest_and_fixture_no_pii_or_windows_paths

test_installer_exists_syntax_lf_and_no_forbidden_runtimes() {
  assert_exists "installer_exists" "$INSTALLER_SH"
  if [ ! -f "$INSTALLER_SH" ]; then
    return
  fi
  if bash -n "$INSTALLER_SH" 2>/dev/null; then
    printf 'PASS: installer_bash_syntax\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL: installer_bash_syntax\n' >&2
    FAIL=$((FAIL + 1))
  fi
  if awk '{ if (index($0, "\r") > 0) exit 1 }' "$INSTALLER_SH"; then
    printf 'PASS: installer_lf_only\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL: installer_lf_only (contains CRLF)\n' >&2
    FAIL=$((FAIL + 1))
  fi
  local content
  content="$(cat "$INSTALLER_SH")"
  if printf '%s\n' "$content" | grep -E -q '(^|[^a-zA-Z0-9_-])(python3?|node|jq|pwsh|powershell)([^a-zA-Z0-9_-]|$)'; then
    printf 'FAIL: installer_no_forbidden_runtimes\n' >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: installer_no_forbidden_runtimes\n'
    PASS=$((PASS + 1))
  fi
  assert_not_contains "installer_no_cmd_exe" "cmd.exe" "$content"
  assert_not_contains "installer_no_appdata" "%APPDATA%" "$content"
  assert_not_contains "installer_no_temp" "%TEMP%" "$content"
  assert_not_contains "installer_no_userprofile" '$env:USERPROFILE' "$content"
}

test_installer_list_and_help() {
  if [ ! -f "$INSTALLER_SH" ]; then
    printf 'FAIL: test_installer_list_and_help (installer missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local out status
  out="$(bash "$INSTALLER_SH" --list 2>&1)"
  status=$?
  assert_eq "installer_list_exit" "0" "$status"
  assert_contains "installer_list_id" "superpowers-skills" "$out"
  assert_contains "installer_list_version" "1.0.0" "$out"
  assert_contains "installer_list_s1" "orca-superpowers-orchestrator" "$out"
  assert_contains "installer_list_s2" "orca-superpowers-orchestration-auto" "$out"
  assert_contains "installer_list_s3" "orca-superpowers-review-loop" "$out"
  assert_contains "installer_list_s4" "orca-superpowers-merge" "$out"

  out="$(bash "$INSTALLER_SH" --help 2>&1)"
  status=$?
  assert_eq "installer_help_exit" "0" "$status"
  assert_contains "installer_help_dry_run" "--dry-run" "$out"
  assert_contains "installer_help_force" "--force" "$out"
  assert_contains "installer_help_uninstall" "--uninstall" "$out"
  assert_contains "installer_help_local" "--local" "$out"
  assert_contains "installer_help_agent" "--agent" "$out"
  assert_contains "installer_help_skill" "--skill" "$out"

  bash "$INSTALLER_SH" --nao-existe >/dev/null 2>&1
  status=$?
  assert_eq "installer_invalid_arg_exit_2" "2" "$status"

  bash "$INSTALLER_SH" --skill nao-existe >/dev/null 2>&1
  status=$?
  assert_eq "installer_unknown_skill_exit_1" "1" "$status"
}

test_installer_dry_run_is_read_only() {
  if [ ! -f "$INSTALLER_SH" ]; then
    printf 'FAIL: test_installer_dry_run_is_read_only (installer missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local tmp out status created
  tmp="$(make_tmp_dir)"
  out="$(HOME="$tmp" bash "$INSTALLER_SH" --agents-file "$MINIMAL_AGENTS_FIXTURE" --dry-run 2>&1)"
  status=$?
  assert_eq "dry_run_exit" "0" "$status"
  assert_contains "dry_run_plugin_header" "PLUGIN|superpowers-skills|1.0.0|global|dry-run|agents:claude,codex,antigravity,future-cli" "$out"
  assert_contains "dry_run_canonical_orch" "ACTION|INSTALL|orca-superpowers-orchestrator|.agents/skills/orca-superpowers-orchestrator|" "$out"
  assert_contains "dry_run_claude_link" "ACTION|LINK|orca-superpowers-orchestrator|.claude/skills/orca-superpowers-orchestrator|" "$out"
  assert_contains "dry_run_antigravity_link" "ACTION|LINK|orca-superpowers-orchestrator|.gemini/config/skills/orca-superpowers-orchestrator|" "$out"

  created="$(find "$tmp" -mindepth 1)"
  assert_eq "dry_run_creates_nothing" "" "$created"
}

test_installer_global_smoke_dynamic_and_subdirectories() {
  if [ ! -f "$INSTALLER_SH" ]; then
    printf 'FAIL: test_installer_global_smoke_dynamic_and_subdirectories (installer missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local tmp out status s state_content
  tmp="$(make_tmp_dir)"
  out="$(HOME="$tmp" bash "$INSTALLER_SH" --agents-file "$MINIMAL_AGENTS_FIXTURE" 2>&1)"
  status=$?
  assert_eq "global_install_exit" "0" "$status"
  assert_contains "global_install_header" "PLUGIN|superpowers-skills|1.0.0|global|apply|agents:claude,codex,antigravity,future-cli" "$out"

  for s in \
    orca-superpowers-orchestrator \
    orca-superpowers-orchestration-auto \
    orca-superpowers-review-loop \
    orca-superpowers-merge
  do
    assert_exists "global_shared_$s" "$tmp/.agents/skills/$s/SKILL.md"
    assert_exists "global_claude_$s" "$tmp/.claude/skills/$s/SKILL.md"
    assert_exists "global_antigravity_$s" "$tmp/.gemini/config/skills/$s/SKILL.md"
  done

  assert_exists "global_subdir_get_quotas" "$tmp/.agents/skills/orca-superpowers-orchestration-auto/scripts/get-quotas.sh"
  if bash -n "$tmp/.agents/skills/orca-superpowers-orchestration-auto/scripts/get-quotas.sh" 2>/dev/null; then
    printf 'PASS: global_subdir_get_quotas_syntax\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL: global_subdir_get_quotas_syntax\n' >&2
    FAIL=$((FAIL + 1))
  fi

  assert_not_exists "global_no_codex_dir" "$tmp/.codex"
  assert_not_exists "global_no_future_cli_dir" "$tmp/.future-cli"
  assert_exists "global_state_file_exists" "$tmp/.agents/.orca-superpowers-installed"
  if [ -f "$tmp/.agents/.orca-superpowers-installed" ]; then
    state_content="$(cat "$tmp/.agents/.orca-superpowers-installed")"
    assert_not_contains "global_state_no_tmp_abs_path" "$tmp" "$state_content"
    assert_not_contains "global_state_no_at_pii" "@" "$state_content"
  fi
}

test_installer_idempotent_second_run() {
  if [ ! -f "$INSTALLER_SH" ]; then
    printf 'FAIL: test_installer_idempotent_second_run (installer missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local tmp out status
  tmp="$(make_tmp_dir)"
  HOME="$tmp" bash "$INSTALLER_SH" --agents-file "$MINIMAL_AGENTS_FIXTURE" >/dev/null 2>&1
  out="$(HOME="$tmp" bash "$INSTALLER_SH" --agents-file "$MINIMAL_AGENTS_FIXTURE" 2>&1)"
  status=$?
  assert_eq "idempotent_exit" "0" "$status"
  assert_contains "idempotent_summary" "SUMMARY|installed=0|updated=0|linked=0|copied=0|kept=12|skipped=0|backed_up=0|removed=0" "$out"
}

test_installer_universal_and_skill_filter() {
  if [ ! -f "$INSTALLER_SH" ]; then
    printf 'FAIL: test_installer_universal_and_skill_filter (installer missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local tmp out status
  tmp="$(make_tmp_dir)"
  out="$(HOME="$tmp" bash "$INSTALLER_SH" --agent universal --skill orca-superpowers-merge 2>&1)"
  status=$?
  assert_eq "universal_filter_exit" "0" "$status"
  assert_contains "universal_filter_header" "PLUGIN|superpowers-skills|1.0.0|global|apply|agents:universal" "$out"
  assert_exists "universal_merge_installed" "$tmp/.agents/skills/orca-superpowers-merge/SKILL.md"
  assert_not_exists "universal_no_orch" "$tmp/.agents/skills/orca-superpowers-orchestrator"
  assert_not_exists "universal_no_claude" "$tmp/.claude"
  assert_not_exists "universal_no_gemini" "$tmp/.gemini"
}

test_installer_copy_mode_idempotent() {
  if [ ! -f "$INSTALLER_SH" ]; then
    printf 'FAIL: test_installer_copy_mode_idempotent (installer missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local tmp out status dest state_content
  tmp="$(make_tmp_dir)"
  out="$(HOME="$tmp" bash "$INSTALLER_SH" --copy --agents-file "$MINIMAL_AGENTS_FIXTURE" 2>&1)"
  status=$?
  assert_eq "copy_mode_exit" "0" "$status"
  dest="$tmp/.claude/skills/orca-superpowers-merge"
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    printf 'PASS: copy_mode_claude_is_real_dir\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL: copy_mode_claude_is_real_dir\n' >&2
    FAIL=$((FAIL + 1))
  fi
  state_content="$(cat "$tmp/.agents/.orca-superpowers-installed")"
  assert_contains "copy_mode_state_records_copy" "|copy|" "$state_content"

  out="$(HOME="$tmp" bash "$INSTALLER_SH" --copy --agents-file "$MINIMAL_AGENTS_FIXTURE" 2>&1)"
  status=$?
  assert_eq "copy_mode_second_exit" "0" "$status"
  assert_contains "copy_mode_second_kept_12" "kept=12|" "$out"
  assert_contains "copy_mode_second_copied_0" "|copied=0|" "$out"
}

test_installer_exists_syntax_lf_and_no_forbidden_runtimes
test_installer_list_and_help
test_installer_dry_run_is_read_only
test_installer_global_smoke_dynamic_and_subdirectories
test_installer_idempotent_second_run
test_installer_universal_and_skill_filter
test_installer_copy_mode_idempotent

printf 'Summary: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
