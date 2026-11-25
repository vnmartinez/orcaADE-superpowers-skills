#!/usr/bin/env bash
set -u

AGENTS_FILE=""
ACCOUNTS_FILE=""

usage() {
  printf 'Usage: %s [--agents-file <path>] [--accounts-file <path>]\n' "$0" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agents-file)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      AGENTS_FILE="$2"
      shift 2
      ;;
    --accounts-file)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      ACCOUNTS_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

parse_agents_json() {
  awk '
  function emit_token(type, val,   parent_t, pkey) {
    if (type == "{") {
      depth++
      ctype[depth] = "obj"
      ckey[depth] = pending_key
      pending_key = ""
      expect_val[depth] = 0
      if (in_agents && depth == agents_arr_depth + 1) {
        cur_id = ""
        cur_def = ""
      }
      return
    }
    if (type == "}") {
      if (in_agents && depth == agents_arr_depth + 1) {
        if (cur_id != "") {
          printf "INSTALLED|%s|%s\n", cur_id, cur_def
        }
      }
      delete ctype[depth]
      delete ckey[depth]
      delete expect_val[depth]
      depth--
      pending_key = ""
      return
    }
    if (type == "[") {
      depth++
      ctype[depth] = "arr"
      ckey[depth] = pending_key
      pending_key = ""
      expect_val[depth] = 0
      if (!in_agents && ckey[depth] == "agents" && (depth == 2 || (depth == 3 && ckey[2] == "result"))) {
        in_agents = 1
        agents_arr_depth = depth
      }
      return
    }
    if (type == "]") {
      if (in_agents && depth == agents_arr_depth) {
        in_agents = 0
        agents_arr_depth = -1
      }
      delete ctype[depth]
      delete ckey[depth]
      delete expect_val[depth]
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

    if (in_agents && depth == agents_arr_depth + 1 && ctype[depth] == "obj" && expect_val[depth]) {
      if (pending_key == "id" && type == "STR") {
        cur_id = val
      } else if (pending_key == "default" && type == "LIT") {
        cur_def = (val == "true" ? "default" : "")
      }
      expect_val[depth] = 0
      pending_key = ""
    }
  }

  function process_text(txt,   n, i, ch, esc, str, lit) {
    n = length(txt)
    i = 1
    while (i <= n) {
      ch = substr(txt, i, 1)
      if (in_str) {
        if (str_esc) {
          str = str ch
          str_esc = 0
        } else if (ch == "\\") {
          str_esc = 1
        } else if (ch == "\"") {
          in_str = 0
          emit_token("STR", str)
          str = ""
        } else {
          str = str ch
        }
        i++
        continue
      }
      if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") {
        i++
        continue
      }
      if (ch == "\"") {
        in_str = 1
        str_esc = 0
        str = ""
        i++
        continue
      }
      if (ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == ",") {
        emit_token(ch, ch)
        i++
        continue
      }
      lit = ""
      while (i <= n) {
        ch = substr(txt, i, 1)
        if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n" || ch == "," || ch == "}" || ch == "]") {
          break
        }
        lit = lit ch
        i++
      }
      if (lit != "") {
        emit_token("LIT", lit)
      }
    }
  }

  BEGIN {
    depth = 0
    in_agents = 0
    agents_arr_depth = -1
    in_str = 0
    str_esc = 0
    pending_key = ""
  }
  {
    process_text($0 "\n")
  }
  '
}

parse_rate_limits_json() {
  awk '
  function flush_provider(   s_out, w_out, p_out, w_win, w_pct, i) {
    if (!p_has_status) {
      return
    }
    if (p_status == "ok") {
      s_out = (p_sess == "" ? "-" : p_sess)
      w_out = (p_wk == "" ? "-" : p_wk)
      p_out = (p_plan == "" ? "-" : p_plan)
      if (p_sess != "" && p_wk != "") {
        if ((p_sess + 0) >= (p_wk + 0)) {
          w_win = "session"
          w_pct = p_sess
        } else {
          w_win = "weekly"
          w_pct = p_wk
        }
      } else if (p_sess != "") {
        w_win = "session"
        w_pct = p_sess
      } else if (p_wk != "") {
        w_win = "weekly"
        w_pct = p_wk
      } else {
        w_win = "-"
        w_pct = "-"
      }
      printf "QUOTA|%s|ok|%s|%s|%s|%s|%s\n", prov, s_out, w_out, w_win, w_pct, p_out
      for (i = 1; i <= bucket_count; i++) {
        printf "%s\n", buckets[i]
      }
    } else {
      printf "QUOTA|%s|unavailable|-|-|-|-|-\n", prov
    }
  }

  function emit_token(type, val,   i) {
    if (type == "{") {
      depth++
      ctype[depth] = "obj"
      ckey[depth] = pending_key
      pending_key = ""
      expect_val[depth] = 0

      if (!in_rl && ckey[depth] == "rateLimits" && (depth == 2 || (depth == 3 && ckey[2] == "result"))) {
        in_rl = 1
        rl_depth = depth
        prov = ""
        return
      }

      if (in_rl && depth == rl_depth + 1 && ckey[depth] != "") {
        prov = ckey[depth]
        p_status = ""
        p_plan = ""
        p_sess = ""
        p_wk = ""
        p_has_status = 0
        bucket_count = 0
        return
      }

      if (in_rl && prov != "" && in_buckets && depth == buckets_depth + 1) {
        b_group = ""
        b_win = ""
        b_pct = ""
      }
      return
    }

    if (type == "}") {
      if (in_rl && prov != "" && in_buckets && depth == buckets_depth + 1) {
        if (b_group != "" && b_win != "" && b_pct != "") {
          bucket_count++
          buckets[bucket_count] = "BUCKET|" prov "|" b_group "|" b_win "|" b_pct
        }
      }
      if (in_rl && prov != "" && depth == rl_depth + 1) {
        flush_provider()
        prov = ""
        bucket_count = 0
      }
      if (in_rl && depth == rl_depth) {
        in_rl = 0
        rl_depth = -1
      }
      delete ctype[depth]
      delete ckey[depth]
      delete expect_val[depth]
      depth--
      pending_key = ""
      return
    }

    if (type == "[") {
      depth++
      ctype[depth] = "arr"
      ckey[depth] = pending_key
      pending_key = ""
      expect_val[depth] = 0
      if (in_rl && prov != "" && depth == rl_depth + 2 && ckey[depth] == "buckets") {
        in_buckets = 1
        buckets_depth = depth
      }
      return
    }

    if (type == "]") {
      if (in_buckets && depth == buckets_depth) {
        in_buckets = 0
        buckets_depth = -1
      }
      delete ctype[depth]
      delete ckey[depth]
      delete expect_val[depth]
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

    if (in_rl && prov != "" && ctype[depth] == "obj" && expect_val[depth]) {
      if (depth == rl_depth + 1) {
        if (pending_key == "status" && type == "STR") {
          p_status = val
          p_has_status = 1
        } else if (pending_key == "planType" && type == "STR") {
          p_plan = val
        }
      } else if (depth == rl_depth + 2) {
        if (ckey[depth] == "session" && pending_key == "usedPercent" && type == "LIT" && val != "null") {
          p_sess = val
        } else if (ckey[depth] == "weekly" && pending_key == "usedPercent" && type == "LIT" && val != "null") {
          p_wk = val
        }
      } else if (in_buckets && depth == buckets_depth + 1) {
        if (pending_key == "group" && type == "STR") {
          b_group = val
        } else if (pending_key == "windowMinutes" && type == "LIT" && val != "null") {
          b_win = val
        } else if (pending_key == "usedPercent" && type == "LIT" && val != "null") {
          b_pct = val
        }
      }
      expect_val[depth] = 0
      pending_key = ""
    }
  }

  function process_text(txt,   n, i, ch, str, lit) {
    n = length(txt)
    i = 1
    while (i <= n) {
      ch = substr(txt, i, 1)
      if (in_str) {
        if (str_esc) {
          str = str ch
          str_esc = 0
        } else if (ch == "\\") {
          str_esc = 1
        } else if (ch == "\"") {
          in_str = 0
          emit_token("STR", str)
          str = ""
        } else {
          str = str ch
        }
        i++
        continue
      }
      if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") {
        i++
        continue
      }
      if (ch == "\"") {
        in_str = 1
        str_esc = 0
        str = ""
        i++
        continue
      }
      if (ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == ",") {
        emit_token(ch, ch)
        i++
        continue
      }
      lit = ""
      while (i <= n) {
        ch = substr(txt, i, 1)
        if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n" || ch == "," || ch == "}" || ch == "]") {
          break
        }
        lit = lit ch
        i++
      }
      if (lit != "") {
        emit_token("LIT", lit)
      }
    }
  }

  BEGIN {
    depth = 0
    in_rl = 0
    rl_depth = -1
    in_buckets = 0
    buckets_depth = -1
    prov = ""
    in_str = 0
    str_esc = 0
    pending_key = ""
  }
  {
    process_text($0 "\n")
  }
  '
}

extract_json_string_field() {
  local key="$1"
  awk -v k="$key" '
  function scan(txt,   n, i, ch, str, collecting, cur_key, exp_val, is_key) {
    n = length(txt)
    i = 1
    while (i <= n) {
      ch = substr(txt, i, 1)
      if (in_str) {
        if (esc) {
          str = str ch
          esc = 0
        } else if (ch == "\\") {
          esc = 1
        } else if (ch == "\"") {
          in_str = 0
          if (exp_val && cur_key == k) {
            print str
            found = 1
            return
          }
          if (!exp_val) {
            cur_key = str
          }
          exp_val = 0
          str = ""
        } else {
          str = str ch
        }
        i++
        continue
      }
      if (ch == "\"") {
        in_str = 1
        esc = 0
        str = ""
      } else if (ch == ":") {
        exp_val = 1
      } else if (ch == "," || ch == "{" || ch == "}") {
        exp_val = 0
      }
      i++
    }
  }
  BEGIN { in_str = 0; esc = 0; found = 0; exp_val = 0; cur_key = "" }
  !found { scan($0 "\n") }
  '
}

collect_direct_curl() {
  printf 'SOURCE|direct-curl\n'

  local claude_token=""
  if [ -n "${CLAUDE_OAUTH_TOKEN:-}" ]; then
    claude_token="$CLAUDE_OAUTH_TOKEN"
  elif [ -f "$HOME/.claude/.credentials.json" ]; then
    claude_token="$(extract_json_string_field "accessToken" < "$HOME/.claude/.credentials.json")"
  fi

  local claude_line="QUOTA|claude|unavailable|-|-|-|-|-"
  if [ -n "$claude_token" ] && command -v curl >/dev/null 2>&1; then
    local claude_resp
    if claude_resp="$(curl -sfS --max-time 10 \
      -H "Authorization: Bearer $claude_token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)"; then
      local parsed_claude
      parsed_claude="$(printf '%s' "$claude_resp" | awk '
        BEGIN { s=""; w="" }
        {
          if (match($0, /"five_hour"[^}]*"utilization"[[:space:]]*:[[:space:]]*[0-9.]+/)) {
            seg = substr($0, RSTART, RLENGTH)
            sub(/.*"utilization"[[:space:]]*:[[:space:]]*/, "", seg)
            s = seg
          }
          if (match($0, /"seven_day"[^}]*"utilization"[[:space:]]*:[[:space:]]*[0-9.]+/)) {
            seg = substr($0, RSTART, RLENGTH)
            sub(/.*"utilization"[[:space:]]*:[[:space:]]*/, "", seg)
            w = seg
          }
        }
        END {
          if (s != "" || w != "") {
            so = (s == "" ? "-" : sprintf("%d", s + 0.5))
            wo = (w == "" ? "-" : sprintf("%d", w + 0.5))
            if (s != "" && w != "") {
              if ((s + 0) >= (w + 0)) { ww = "session"; wp = so } else { ww = "weekly"; wp = wo }
            } else if (s != "") { ww = "session"; wp = so } else { ww = "weekly"; wp = wo }
            printf "QUOTA|claude|ok|%s|%s|%s|%s|-\n", so, wo, ww, wp
          }
        }')"
      if [ -n "$parsed_claude" ]; then
        claude_line="$parsed_claude"
      fi
    fi
  fi
  printf '%s\n' "$claude_line"

  local codex_auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
  local codex_token=""
  local codex_acc=""
  if [ -f "$codex_auth" ]; then
    codex_token="$(extract_json_string_field "access_token" < "$codex_auth")"
    codex_acc="$(extract_json_string_field "account_id" < "$codex_auth")"
  fi

  local codex_line="QUOTA|codex|unavailable|-|-|-|-|-"
  if [ -n "$codex_token" ] && command -v curl >/dev/null 2>&1; then
    local codex_resp
    if [ -n "$codex_acc" ]; then
      codex_resp="$(curl -sfS --max-time 10 \
        -H "Authorization: Bearer $codex_token" \
        -H "User-Agent: orca-quota-check/1.0" \
        -H "ChatGPT-Account-Id: $codex_acc" \
        "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null || true)"
    else
      codex_resp="$(curl -sfS --max-time 10 \
        -H "Authorization: Bearer $codex_token" \
        -H "User-Agent: orca-quota-check/1.0" \
        "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null || true)"
    fi
    if [ -n "$codex_resp" ]; then
      local parsed_codex
      parsed_codex="$(printf '%s' "$codex_resp" | awk '
        BEGIN { p=""; ps=""; s=""; ss="" }
        {
          if (match($0, /"primary_window"[^}]*"used_percent"[[:space:]]*:[[:space:]]*[0-9.]+/)) {
            seg = substr($0, RSTART, RLENGTH)
            sub(/.*"used_percent"[[:space:]]*:[[:space:]]*/, "", seg)
            p = seg
          }
          if (match($0, /"primary_window"[^}]*"limit_window_seconds"[[:space:]]*:[[:space:]]*[0-9]+/)) {
            seg = substr($0, RSTART, RLENGTH)
            sub(/.*"limit_window_seconds"[[:space:]]*:[[:space:]]*/, "", seg)
            ps = seg
          }
          if (match($0, /"secondary_window"[^}]*"used_percent"[[:space:]]*:[[:space:]]*[0-9.]+/)) {
            seg = substr($0, RSTART, RLENGTH)
            sub(/.*"used_percent"[[:space:]]*:[[:space:]]*/, "", seg)
            s = seg
          }
          if (match($0, /"secondary_window"[^}]*"limit_window_seconds"[[:space:]]*:[[:space:]]*[0-9]+/)) {
            seg = substr($0, RSTART, RLENGTH)
            sub(/.*"limit_window_seconds"[[:space:]]*:[[:space:]]*/, "", seg)
            ss = seg
          }
        }
        END {
          if (p != "" || s != "") {
            if (ps != "" && (ps + 0) > 86400) {
              tmp = p; p = s; s = tmp
            }
            so = (p == "" ? "-" : sprintf("%d", p + 0.5))
            wo = (s == "" ? "-" : sprintf("%d", s + 0.5))
            if (p != "" && s != "") {
              if ((p + 0) >= (s + 0)) { ww = "session"; wp = so } else { ww = "weekly"; wp = wo }
            } else if (p != "") { ww = "session"; wp = so } else { ww = "weekly"; wp = wo }
            printf "QUOTA|codex|ok|%s|%s|%s|%s|-\n", so, wo, ww, wp
          }
        }')"
      if [ -n "$parsed_codex" ]; then
        codex_line="$parsed_codex"
      fi
    fi
  fi
  printf '%s\n' "$codex_line"
  printf 'QUOTA|antigravity|unavailable|-|-|-|-|-\n'
  printf 'QUOTA|gemini|unavailable|-|-|-|-|-\n'
  printf 'QUOTA|kimi|unavailable|-|-|-|-|-\n'
  printf 'QUOTA|opencodeGo|unavailable|-|-|-|-|-\n'
}

main() {
  local agents_json=""
  local accounts_json=""

  if [ -n "$AGENTS_FILE" ]; then
    if [ ! -f "$AGENTS_FILE" ]; then
      printf 'Agents file not found: %s\n' "$AGENTS_FILE" >&2
      exit 1
    fi
    agents_json="$(cat "$AGENTS_FILE")"
  elif command -v orca >/dev/null 2>&1; then
    agents_json="$(orca agent installed --worktree active --json 2>/dev/null || true)"
  fi

  if [ -n "$ACCOUNTS_FILE" ]; then
    if [ ! -f "$ACCOUNTS_FILE" ]; then
      printf 'Accounts file not found: %s\n' "$ACCOUNTS_FILE" >&2
      exit 1
    fi
    printf 'SOURCE|orca\n'
    if [ -n "$agents_json" ]; then
      printf '%s\n' "$agents_json" | parse_agents_json
    fi
    parse_rate_limits_json < "$ACCOUNTS_FILE"
    return 0
  fi

  if command -v orca >/dev/null 2>&1; then
    accounts_json="$(orca account list --json 2>/dev/null || true)"
    if [ -n "$accounts_json" ]; then
      printf 'SOURCE|orca\n'
      if [ -n "$agents_json" ]; then
        printf '%s\n' "$agents_json" | parse_agents_json
      fi
      printf '%s\n' "$accounts_json" | parse_rate_limits_json
      return 0
    fi
  fi

  if [ -n "$agents_json" ]; then
    collect_direct_curl_with_agents "$agents_json"
    return 0
  fi

  collect_direct_curl
}

collect_direct_curl_with_agents() {
  local agents_json="$1"
  local out
  out="$(collect_direct_curl)"
  printf '%s\n' "$out" | sed -n '1p'
  printf '%s\n' "$agents_json" | parse_agents_json
  printf '%s\n' "$out" | sed -n '2,$p'
}

main
