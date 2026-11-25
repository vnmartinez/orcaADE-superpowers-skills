#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GET_QUOTAS="$REPO_ROOT/orca-superpowers-orchestration-auto/scripts/get-quotas.sh"
SKILL_MD="$REPO_ROOT/orca-superpowers-orchestration-auto/SKILL.md"
AGENTS_FIXTURE="$REPO_ROOT/tests/fixtures/agent-installed.json"
ACCOUNTS_FIXTURE="$REPO_ROOT/tests/fixtures/account-list.json"

PASS=0
FAIL=0

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

run_collector_fixture() {
  bash "$GET_QUOTAS" --agents-file "$AGENTS_FIXTURE" --accounts-file "$ACCOUNTS_FIXTURE"
}

test_script_exists_and_bash_syntax() {
  if [ -f "$GET_QUOTAS" ] && bash -n "$GET_QUOTAS" 2>/dev/null; then
    printf 'PASS: test_script_exists_and_bash_syntax\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL: test_script_exists_and_bash_syntax (missing or syntax error: %s)\n' "$GET_QUOTAS" >&2
    FAIL=$((FAIL + 1))
  fi
}

test_no_forbidden_runtimes_in_script() {
  if [ ! -f "$GET_QUOTAS" ]; then
    printf 'FAIL: test_no_forbidden_runtimes_in_script (file missing)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local content
  content="$(cat "$GET_QUOTAS")"
  if printf '%s\n' "$content" | grep -E -q '(^|[^a-zA-Z0-9_-])(python3?|node|jq|pwsh|powershell)([^a-zA-Z0-9_-]|$)'; then
    printf 'FAIL: test_no_forbidden_runtimes_in_script (forbidden runtime found)\n' >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: test_no_forbidden_runtimes_in_script\n'
    PASS=$((PASS + 1))
  fi
}

test_installed_agents_extracted() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "installed_source_orca" "SOURCE|orca" "$out"
  assert_contains "installed_claude_default" "INSTALLED|claude|default" "$out"
  assert_contains "installed_codex" "INSTALLED|codex|" "$out"
  assert_contains "installed_opencode" "INSTALLED|opencode|" "$out"
  assert_contains "installed_opencode2" "INSTALLED|opencode2|" "$out"
  assert_contains "installed_antigravity" "INSTALLED|antigravity|" "$out"
  assert_contains "installed_copilot" "INSTALLED|copilot|" "$out"
}

test_claude_5h_and_weekly() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "claude_5h_and_weekly" "QUOTA|claude|ok|5|66|weekly|66|pro" "$out"
}

test_codex_5h_and_weekly() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "codex_5h_and_weekly" "QUOTA|codex|ok|0|74|weekly|74|plus" "$out"
}

test_antigravity_windows_and_buckets() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "antigravity_quota" "QUOTA|antigravity|ok|12|6|session|12|-" "$out"
  assert_contains "antigravity_bucket_gemini_weekly" "BUCKET|antigravity|Gemini Models|10080|6" "$out"
  assert_contains "antigravity_bucket_gemini_5h" "BUCKET|antigravity|Gemini Models|300|12" "$out"
  assert_contains "antigravity_bucket_claude_gpt_weekly" "BUCKET|antigravity|Claude and GPT models|10080|0" "$out"
  assert_contains "antigravity_bucket_claude_gpt_5h" "BUCKET|antigravity|Claude and GPT models|300|0" "$out"
}

test_unavailable_providers() {
  local out
  out="$(run_collector_fixture 2>/dev/null || true)"
  assert_contains "unavailable_gemini" "QUOTA|gemini|unavailable|-|-|-|-|-" "$out"
  assert_contains "unavailable_kimi" "QUOTA|kimi|unavailable|-|-|-|-|-" "$out"
  assert_contains "unavailable_opencodeGo" "QUOTA|opencodeGo|unavailable|-|-|-|-|-" "$out"
}

test_no_pii_or_secrets() {
  local out combined
  out="$(run_collector_fixture 2>/dev/null || true)"
  combined="$(cat "$AGENTS_FIXTURE" "$ACCOUNTS_FIXTURE")
$out"
  assert_not_contains "no_pii_at" "@" "$combined"
  assert_not_contains "no_pii_org_uuid" "organizationUuid" "$combined"
  assert_not_contains "no_secret_bearer" "Bearer " "$combined"
  assert_not_contains "no_secret_access_token_snake" "access_token" "$combined"
  assert_not_contains "no_secret_access_token_camel" "accessToken" "$combined"
  assert_not_contains "no_secret_refresh_token" "refresh_token" "$combined"
  assert_not_contains "no_pii_win_users" 'C:\Users' "$combined"
}

test_skill_frontmatter() {
  if [ ! -f "$SKILL_MD" ]; then
    printf 'FAIL: test_skill_frontmatter (missing: %s)\n' "$SKILL_MD" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local first_line head_block
  first_line="$(sed -n '1p' "$SKILL_MD")"
  head_block="$(sed -n '1,10p' "$SKILL_MD")"
  assert_eq "skill_starts_with_yaml_fence" "---" "$first_line"
  assert_contains "skill_frontmatter_name" "name: orca-superpowers-orchestration-auto" "$head_block"
  assert_contains "skill_frontmatter_description" "description: Use when " "$head_block"
}

test_skill_required_sections_and_contract() {
  if [ ! -f "$SKILL_MD" ]; then
    printf 'FAIL: test_skill_required_sections_and_contract (missing: %s)\n' "$SKILL_MD" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local doc
  doc="$(cat "$SKILL_MD")"

  assert_contains "skill_sec_overview" "## Overview" "$doc"
  assert_contains "skill_sec_discovery" "## Descoberta Dinâmica de Agentes" "$doc"
  assert_contains "skill_sec_when" "## Quando Usar" "$doc"
  assert_contains "skill_sec_quotas" "## Medição Real de Cotas" "$doc"
  assert_contains "skill_sec_engine" "## Motor Determinístico de Roteamento" "$doc"
  assert_contains "skill_sec_presets" "## Presets de Roteamento" "$doc"
  assert_contains "skill_sec_protocol" "## Protocolo Operacional" "$doc"
  assert_contains "skill_sec_audit" "## Trilha de Auditoria" "$doc"
  assert_contains "skill_sec_commands" "## Comandos Úteis" "$doc"
  assert_contains "skill_sec_red_flags" "## Red Flags" "$doc"

  assert_contains "skill_orca_installed" "orca agent installed --worktree active --json" "$doc"
  assert_contains "skill_orca_account_list" "orca account list --json" "$doc"
  assert_contains "skill_result_rate_limits" "result.rateLimits" "$doc"
  assert_contains "skill_orca_agent_launch" "orca agent launch --agent" "$doc"
  assert_contains "skill_surface_terminal" "--surface terminal" "$doc"
  assert_contains "skill_focus" "--focus" "$doc"
  assert_contains "skill_tui_idle" "--for tui-idle" "$doc"
  assert_contains "skill_terminal_show" "orca terminal show --json" "$doc"
  assert_contains "skill_notify_planner" "ETAPA planner CONCLUÍDA" "$doc"
  assert_contains "skill_notify_executor" "ETAPA executor CONCLUÍDA" "$doc"
  assert_contains "skill_notify_reviewer" "ETAPA reviewer CONCLUÍDA" "$doc"
  assert_contains "skill_effort_requires_model" "--effort" "$doc"
  assert_contains "skill_effort_requires_model_rule" "exige \`--model\`" "$doc"
  assert_contains "skill_forbid_non_interactive_p" "\`-p\`" "$doc"
  assert_contains "skill_forbid_non_interactive_exec" "\`exec\`" "$doc"
  assert_contains "skill_forbid_non_interactive_run" "\`run\`" "$doc"

  assert_contains "skill_zero_allocation_question" "nunca pergunta ao usuário qual agente ou modelo" "$doc"
  assert_contains "skill_single_gate_passo2" "Passo 2" "$doc"

  assert_contains "skill_kind_research" "research" "$doc"
  assert_contains "skill_kind_code" "code" "$doc"
  assert_contains "skill_kind_review" "review" "$doc"
  assert_contains "skill_kind_command" "command" "$doc"
  assert_contains "skill_kind_docs" "docs" "$doc"
  assert_contains "skill_kind_scrap" "scrap" "$doc"
  assert_contains "skill_effort_light" "light" "$doc"
  assert_contains "skill_effort_standard" "standard" "$doc"
  assert_contains "skill_effort_deep" "deep" "$doc"
  assert_contains "skill_critical_threshold" "criticalThreshold" "$doc"
  assert_contains "skill_allow_opus" "allowOpusOnDeep" "$doc"
  assert_contains "skill_on_both_critical" "onBothCritical" "$doc"
  assert_contains "skill_mode_ask" "ask" "$doc"
  assert_contains "skill_mode_run_cheapest" "run-cheapest" "$doc"
  assert_contains "skill_mode_block" "block" "$doc"
  assert_contains "skill_fallback_keyword" "fallback" "$doc"
  assert_contains "skill_readonly_guard" "readOnly" "$doc"
  assert_contains "skill_unavailable_not_critical" "status: unavailable" "$doc"

  assert_contains "skill_curl_claude" "https://api.anthropic.com/api/oauth/usage" "$doc"
  assert_contains "skill_curl_codex" "https://chatgpt.com/backend-api/wham/usage" "$doc"
  assert_contains "skill_curl_antigravity" "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels" "$doc"
  assert_contains "skill_curl_cmd" "curl" "$doc"
  assert_contains "skill_curl_claude_creds" "\$HOME/.claude/.credentials.json" "$doc"
  assert_contains "skill_curl_codex_auth" "\$HOME/.codex/auth.json" "$doc"

  assert_contains "skill_audit_rule" "rule:" "$doc"
  assert_contains "skill_audit_role" "role:" "$doc"
  assert_contains "skill_audit_agent" "agent:" "$doc"
  assert_contains "skill_audit_model" "model:" "$doc"
  assert_contains "skill_audit_fallback" "fallback:" "$doc"
  assert_contains "skill_audit_review_section" "## Trilha de Auditoria de Roteamento" "$doc"
}

test_skill_no_forbidden_tools_paths_or_pii() {
  if [ ! -f "$SKILL_MD" ]; then
    printf 'FAIL: test_skill_no_forbidden_tools_paths_or_pii (missing: %s)\n' "$SKILL_MD" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local doc
  doc="$(cat "$SKILL_MD")"

  assert_not_contains "skill_no_python3" "python3" "$doc"
  assert_not_contains "skill_no_get_quotas_py" "get_quotas.py" "$doc"
  assert_not_contains "skill_no_jq" "jq " "$doc"
  assert_not_contains "skill_no_powershell" "powershell" "$doc"
  assert_not_contains "skill_no_pwsh" "pwsh" "$doc"
  assert_not_contains "skill_no_appdata" "%APPDATA%" "$doc"
  assert_not_contains "skill_no_temp" "%TEMP%" "$doc"
  assert_not_contains "skill_no_appdata_local" 'AppData\Local' "$doc"
  assert_not_contains "skill_no_env_userprofile" '$env:USERPROFILE' "$doc"
  assert_not_contains "skill_no_org_uuid" "organizationUuid" "$doc"
  if printf '%s\n' "$doc" | grep -E -q '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'; then
    printf 'FAIL: skill_no_email_pii (email pattern found in SKILL.md)\n' >&2
    FAIL=$((FAIL + 1))
  else
    printf 'PASS: skill_no_email_pii\n'
    PASS=$((PASS + 1))
  fi
}

test_skill_presets_integrity() {
  if [ ! -f "$SKILL_MD" ]; then
    printf 'FAIL: test_skill_presets_integrity (missing: %s)\n' "$SKILL_MD" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  local json_block
  json_block="$(awk '
    /^## Presets de Roteamento/ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec && /^```json/ { in_json=1; next }
    in_sec && in_json && /^```/ { in_json=0; exit }
    in_json { print }
  ' "$SKILL_MD")"

  if [ -z "$json_block" ]; then
    printf 'FAIL: test_skill_presets_integrity (empty json block)\n' >&2
    FAIL=$((FAIL + 1))
    return
  fi

  local check_out
  if check_out="$(printf '%s\n' "$json_block" | awk '
    function fail(msg) {
      printf "ERROR: %s\n", msg > "/dev/stderr"
      err = 1
    }
    function validate_preset(p,   r, k, fb, i, rn) {
      if (role_count[p] <= 0) {
        fail("preset " p " has no roles")
        return
      }
      if (rule_count[p] <= 0) {
        fail("preset " p " has no rules")
        return
      }
      for (i = 1; i <= rule_count[p]; i++) {
        rn = rule_roles[p, i]
        if (!((p SUBSEP rn) in role_exists)) {
          fail("preset " p " rule references missing role: " rn)
        }
      }
      for (i = 1; i <= role_count[p]; i++) {
        r = role_names[p, i]
        fb = role_fallback[p, r]
        if (fb != "" && fb != "null") {
          if (!((p SUBSEP fb) in role_exists)) {
            fail("preset " p " role " r " fallback missing: " fb)
          } else {
            if (fb == r) {
              fail("preset " p " role " r " fallback points to itself")
            }
            if (role_readonly[p, r] == "true" && role_readonly[p, fb] != "true") {
              fail("preset " p " readOnly role " r " fallback " fb " is not readOnly")
            }
          }
        }
        if (role_model[p, r] == "null" && role_effort[p, r] != "" && role_effort[p, r] != "null") {
          fail("preset " p " role " r " sets effort without model")
        }
      }
    }
    function on_token(type, val) {
      if (type == "{") {
        brace_bal++
        depth++
        ctype[depth] = "obj"
        ckey[depth] = pending_key
        pending_key = ""
        expect_val[depth] = 0
        if (depth == 2 && (ckey[2] == "economy" || ckey[2] == "balanced" || ckey[2] == "performance")) {
          cur_preset = ckey[2]
          has_preset[cur_preset] = 1
        } else if (cur_preset != "" && in_roles && depth == 4) {
          r_name = ""; r_fb = ""; r_ro = ""; r_model = ""; r_effort = ""
        } else if (cur_preset != "" && in_rules && depth == 4) {
          ru_role = ""
        }
        return
      }
      if (type == "}") {
        if (cur_preset != "" && in_roles && depth == 4 && r_name != "") {
          role_count[cur_preset]++
          role_names[cur_preset, role_count[cur_preset]] = r_name
          role_exists[cur_preset, r_name] = 1
          role_fallback[cur_preset, r_name] = (r_fb == "" ? "null" : r_fb)
          role_readonly[cur_preset, r_name] = (r_ro == "" ? "false" : r_ro)
          role_model[cur_preset, r_name] = (r_model == "" ? "null" : r_model)
          role_effort[cur_preset, r_name] = (r_effort == "" ? "null" : r_effort)
        } else if (cur_preset != "" && in_rules && depth == 4) {
          rule_count[cur_preset]++
          rule_roles[cur_preset, rule_count[cur_preset]] = ru_role
        } else if (depth == 2 && cur_preset != "") {
          validate_preset(cur_preset)
          cur_preset = ""
        }
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
        if (cur_preset != "" && depth == 3 && ckey[3] == "roles") in_roles = 1
        if (cur_preset != "" && depth == 3 && ckey[3] == "rules") in_rules = 1
        return
      }
      if (type == "]") {
        if (depth == 3 && in_roles) in_roles = 0
        if (depth == 3 && in_rules) in_rules = 0
        bracket_bal--
        if (bracket_bal < 0) fail("unbalanced ]")
        delete ctype[depth]; delete ckey[depth]; delete expect_val[depth]
        depth--
        pending_key = ""
        return
      }
      if (type == ":") { expect_val[depth] = 1; return }
      if (type == ",") { expect_val[depth] = 0; pending_key = ""; return }
      if (ctype[depth] == "obj" && !expect_val[depth] && type == "STR") {
        pending_key = val
        return
      }
      if (cur_preset != "" && ctype[depth] == "obj" && expect_val[depth]) {
        if (in_roles && depth == 4) {
          if (pending_key == "name") r_name = val
          else if (pending_key == "fallback") r_fb = val
          else if (pending_key == "readOnly") r_ro = val
          else if (pending_key == "model") r_model = val
          else if (pending_key == "effort") r_effort = val
        } else if (in_rules && depth == 4) {
          if (pending_key == "role") ru_role = val
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
      if (!has_preset["economy"] || !has_preset["balanced"] || !has_preset["performance"]) {
        fail("missing one of economy/balanced/performance presets")
      }
      if (err) exit 1
      print "PRESETS_OK"
    }
  ' 2>&1)"; then
    assert_eq "skill_presets_integrity" "PRESETS_OK" "$check_out"
  else
    printf 'FAIL: test_skill_presets_integrity (%s)\n' "$check_out" >&2
    FAIL=$((FAIL + 1))
  fi
}

test_script_exists_and_bash_syntax
test_no_forbidden_runtimes_in_script
test_installed_agents_extracted
test_claude_5h_and_weekly
test_codex_5h_and_weekly
test_antigravity_windows_and_buckets
test_unavailable_providers
test_no_pii_or_secrets
test_skill_frontmatter
test_skill_required_sections_and_contract
test_skill_no_forbidden_tools_paths_or_pii
test_skill_presets_integrity

printf 'Summary: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
