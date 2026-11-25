#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$REPO_ROOT/plugin/manifest.json"
ORCA_BIN="${ORCA_BIN:-orca}"

FILTER_SKILLS=""
FILTER_AGENT=""
MODE_LOCAL=0
TARGET_DIR=""
DRY_RUN=0
FORCE=0
UNINSTALL=0
FORCE_COPY=0
AGENTS_FILE=""
LIST_ONLY=0

usage() {
  cat <<'EOF'
Usage: install-skills.sh [options]

Options:
  --skill <name>        Install/uninstall only the specified skill (repeatable)
  --agent <list|univ>   Comma-separated agent IDs or 'universal'
  --local               Install into current project ($PWD or --target-dir)
  --target-dir <dir>    Target project directory (with --local)
  --dry-run             Print planned actions without modifying any files
  --force               Backup and replace divergent unmanaged directories
  --uninstall           Remove managed skills without touching third-party skills
  --copy                Copy files instead of creating symlinks for agent paths
  --agents-file <path>  Read installed agents from JSON file (orca format)
  --list                List plugin metadata and bundled skills, then exit
  -h, --help            Show this help message and exit
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill)
      if [ "$#" -lt 2 ]; then
        printf 'Error: --skill requires a value\n' >&2
        usage >&2
        exit 2
      fi
      if [ -z "$FILTER_SKILLS" ]; then
        FILTER_SKILLS="$2"
      else
        FILTER_SKILLS="$FILTER_SKILLS
$2"
      fi
      shift 2
      ;;
    --agent)
      if [ "$#" -lt 2 ]; then
        printf 'Error: --agent requires a value\n' >&2
        usage >&2
        exit 2
      fi
      FILTER_AGENT="$2"
      shift 2
      ;;
    --local)
      MODE_LOCAL=1
      shift
      ;;
    --target-dir)
      if [ "$#" -lt 2 ]; then
        printf 'Error: --target-dir requires a value\n' >&2
        usage >&2
        exit 2
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --copy)
      FORCE_COPY=1
      shift
      ;;
    --agents-file)
      if [ "$#" -lt 2 ]; then
        printf 'Error: --agents-file requires a value\n' >&2
        usage >&2
        exit 2
      fi
      AGENTS_FILE="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

parse_manifest() {
  local mfile="$1"
  if [ ! -f "$mfile" ]; then
    printf 'Error: manifest not found: %s\n' "$mfile" >&2
    return 1
  fi
  awk '
    function fail(msg) {
      printf "Error: manifest parse: %s\n", msg > "/dev/stderr"
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
    }
  ' "$mfile"
}

parse_agents_json() {
  awk '
    function emit_token(type, val) {
      if (type == "{") {
        depth++
        ctype[depth] = "obj"
        ckey[depth] = pending_key
        pending_key = ""
        expect_val[depth] = 0
        if (in_agents && depth == agents_arr_depth + 1) {
          cur_id = ""
        }
        return
      }
      if (type == "}") {
        if (in_agents && depth == agents_arr_depth + 1) {
          if (cur_id != "") {
            printf "%s\n", cur_id
          }
        }
        delete ctype[depth]; delete ckey[depth]; delete expect_val[depth]
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
      if (in_agents && depth == agents_arr_depth + 1 && ctype[depth] == "obj" && expect_val[depth]) {
        if (pending_key == "id" && type == "STR") {
          cur_id = val
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
          if (esc) { str = str ch; esc = 0 }
          else if (ch == "\\") { esc = 1 }
          else if (ch == "\"") { in_str = 0; emit_token("STR", str); str = "" }
          else { str = str ch }
          i++; continue
        }
        if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") { i++; continue }
        if (ch == "\"") { in_str = 1; esc = 0; str = ""; i++; continue }
        if (ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == ",") {
          emit_token(ch, ch); i++; continue
        }
        lit = ""
        while (i <= n) {
          ch = substr(txt, i, 1)
          if (ch == " " || ch == "\t" || ch == "\r" || ch == "\n" || ch == "," || ch == "}" || ch == "]") break
          lit = lit ch; i++
        }
        if (lit != "") emit_token("LIT", lit)
      }
    }
    BEGIN { depth = 0; in_agents = 0; agents_arr_depth = -1; in_str = 0 }
    { process_text($0 "\n") }
  '
}

MANIFEST_PARSED="$(parse_manifest "$MANIFEST_FILE")" || exit 1

PLUGIN_ID="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="META" && $2=="id" { print $3; exit }')"
PLUGIN_NAME="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="META" && $2=="name" { print $3; exit }')"
PLUGIN_VERSION="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="META" && $2=="version" { print $3; exit }')"
SHARED_DIR="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="LAYOUT" && $2=="sharedDir" { print $3; exit }')"
BACKUP_DIR="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="LAYOUT" && $2=="backupDir" { print $3; exit }')"
STATE_REL="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="LAYOUT" && $2=="stateFile" { print $3; exit }')"
ALL_SKILLS="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="SKILL" { print $2 }')"
ALL_AGENT_PATHS="$(printf '%s\n' "$MANIFEST_PARSED" | awk -F'|' '$1=="AGENT_PATH" { print $0 }')"

if [ -z "$PLUGIN_ID" ] || [ -z "$PLUGIN_VERSION" ] || [ -z "$SHARED_DIR" ] || [ -z "$BACKUP_DIR" ] || [ -z "$STATE_REL" ]; then
  printf 'Error: incomplete manifest metadata\n' >&2
  exit 1
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  printf '%s (%s) v%s\n' "$PLUGIN_ID" "$PLUGIN_NAME" "$PLUGIN_VERSION"
  printf '%s\n' "$ALL_SKILLS" | while IFS= read -r s; do
    [ -n "$s" ] && printf '  - %s\n' "$s"
  done
  exit 0
fi

# Validate requested skills
SELECTED_SKILLS=""
if [ -n "$FILTER_SKILLS" ]; then
  while IFS= read -r req; do
    [ -z "$req" ] && continue
    if ! printf '%s\n' "$ALL_SKILLS" | grep -F -x -q -- "$req"; then
      printf 'Error: unknown skill: %s\n' "$req" >&2
      exit 1
    fi
    if ! printf '%s\n' "$SELECTED_SKILLS" | grep -F -x -q -- "$req"; then
      SELECTED_SKILLS="${SELECTED_SKILLS:+$SELECTED_SKILLS
}$req"
    fi
  done <<EOF
$FILTER_SKILLS
EOF
else
  SELECTED_SKILLS="$ALL_SKILLS"
fi

if [ "$MODE_LOCAL" -eq 1 ]; then
  BASE_DIR="${TARGET_DIR:-$PWD}"
else
  BASE_DIR="$HOME"
fi
BASE_DIR="${BASE_DIR%/}"

resolve_target_agents() {
  local raw="" a out=""
  if [ -n "$FILTER_AGENT" ]; then
    raw="$(printf '%s\n' "$FILTER_AGENT" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  elif [ -n "$AGENTS_FILE" ]; then
    if [ ! -f "$AGENTS_FILE" ]; then
      printf 'Error: agents file not found: %s\n' "$AGENTS_FILE" >&2
      return 1
    fi
    raw="$(parse_agents_json < "$AGENTS_FILE")"
  elif command -v "$ORCA_BIN" >/dev/null 2>&1; then
    local orca_out
    orca_out="$("$ORCA_BIN" agent installed --worktree active --json 2>/dev/null || true)"
    if [ -n "$orca_out" ]; then
      raw="$(printf '%s\n' "$orca_out" | parse_agents_json)"
    fi
  fi

  if [ -z "$raw" ]; then
    raw="universal"
  fi

  while IFS= read -r a; do
    [ -z "$a" ] && continue
    if ! printf '%s\n' "$out" | grep -F -x -q -- "$a"; then
      out="${out:+$out
}$a"
    fi
  done <<EOF
$raw
EOF
  printf '%s\n' "$out"
}

dir_digest() {
  local d="$1"
  if [ ! -d "$d" ]; then
    return 1
  fi
  (
    cd "$d" || exit 1
    find . -type f -exec cksum {} + | LC_ALL=C sort
  ) | cksum | awk '{ print $1 "-" $2 }'
}

read_state() {
  local sf="$1"
  if [ -f "$sf" ]; then
    cat "$sf"
  fi
}

write_state() {
  local sf="$1"
  local content="$2"
  local dir tmp_f
  dir="$(dirname "$sf")"
  mkdir -p "$dir"
  tmp_f="$sf.tmp.$$"
  {
    printf '# orca-superpowers-skills state v1\n'
    if [ -n "$content" ]; then
      printf '%s\n' "$content" | awk 'NF && $0 !~ /^#/'
    fi
  } > "$tmp_f"
  mv "$tmp_f" "$sf"
}

state_get_entry() {
  local state_data="$1"
  local kind="$2"
  local skill="$3"
  local rel_path="$4"
  printf '%s\n' "$state_data" | awk -F'|' -v k="$kind" -v s="$skill" -v r="$rel_path" '
    k == "CANONICAL" && $1 == "CANONICAL" && $2 == s && $3 == r { print $0; exit }
    k == "TARGET" && $1 == "TARGET" && $3 == s && $4 == r { print $0; exit }
  '
}

state_upsert_line() {
  local state_data="$1"
  local new_line="$2"
  local k s r
  k="$(printf '%s\n' "$new_line" | awk -F'|' '{ print $1 }')"
  if [ "$k" = "CANONICAL" ]; then
    s="$(printf '%s\n' "$new_line" | awk -F'|' '{ print $2 }')"
    r="$(printf '%s\n' "$new_line" | awk -F'|' '{ print $3 }')"
  else
    s="$(printf '%s\n' "$new_line" | awk -F'|' '{ print $3 }')"
    r="$(printf '%s\n' "$new_line" | awk -F'|' '{ print $4 }')"
  fi
  local filtered
  filtered="$(printf '%s\n' "$state_data" | awk -F'|' -v k="$k" -v s="$s" -v r="$r" '
    /^#/ || NF == 0 { next }
    k == "CANONICAL" && $1 == "CANONICAL" && $2 == s && $3 == r { next }
    k == "TARGET" && $1 == "TARGET" && $3 == s && $4 == r { next }
    { print $0 }
  ')"
  if [ -n "$filtered" ]; then
    printf '%s\n%s\n' "$filtered" "$new_line"
  else
    printf '%s\n' "$new_line"
  fi
}

agent_rel_path() {
  local ag="$1"
  local mode="$2"
  printf '%s\n' "$ALL_AGENT_PATHS" | awk -F'|' -v a="$ag" -v m="$mode" '
    $2 == a { print (m == "local" ? $4 : $3); exit }
  '
}

materialize_target() {
  local canonical_abs="$1"
  local dest_abs="$2"
  local want_copy="$3"
  mkdir -p "$(dirname "$dest_abs")"
  rm -rf "$dest_abs"
  if [ "$want_copy" -eq 0 ]; then
    MSYS=winsymlinks:nativestrict ln -s "$canonical_abs" "$dest_abs" 2>/dev/null || true
    if [ -L "$dest_abs" ]; then
      printf 'link\n'
      return 0
    fi
    rm -rf "$dest_abs"
  fi
  cp -R "$canonical_abs" "$dest_abs"
  printf 'copy\n'
}

install_flow() {
  local agents_list agents_csv mode_str dry_str
  agents_list="$(resolve_target_agents)" || exit 1
  agents_csv="$(printf '%s\n' "$agents_list" | awk 'NF { out = (out ? out "," $0 : $0) } END { print out }')"

  if [ "$MODE_LOCAL" -eq 1 ]; then
    mode_str="local"
  else
    mode_str="global"
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    dry_str="dry-run"
  else
    dry_str="apply"
  fi

  printf 'PLUGIN|%s|%s|%s|%s|agents:%s\n' "$PLUGIN_ID" "$PLUGIN_VERSION" "$mode_str" "$dry_str" "$agents_csv"

  local state_abs="$BASE_DIR/$STATE_REL"
  local state_data
  state_data="$(read_state "$state_abs")"

  # Build unique dedicated target pairs: agent|rel_dir
  local target_pairs="" seen_dirs="" ag rel_dir
  while IFS= read -r ag; do
    [ -z "$ag" ] && continue
    [ "$ag" = "universal" ] && continue
    rel_dir="$(agent_rel_path "$ag" "$mode_str")"
    [ -z "$rel_dir" ] && continue
    [ "$rel_dir" = "$SHARED_DIR" ] && continue
    if ! printf '%s\n' "$seen_dirs" | grep -F -x -q -- "$rel_dir"; then
      seen_dirs="${seen_dirs:+$seen_dirs
}$rel_dir"
      target_pairs="${target_pairs:+$target_pairs
}$ag|$rel_dir"
    fi
  done <<EOF
$agents_list
EOF

  local c_installed=0 c_updated=0 c_linked=0 c_copied=0 c_kept=0 c_skipped=0 c_backed_up=0 c_removed=0
  local skill src_dir src_digest canon_rel canon_abs entry cur_digest st_ver st_dig

  while IFS= read -r skill; do
    [ -z "$skill" ] && continue
    src_dir="$REPO_ROOT/$skill"
    if [ ! -d "$src_dir" ]; then
      printf 'Error: skill source directory missing: %s\n' "$src_dir" >&2
      exit 1
    fi
    src_digest="$(dir_digest "$src_dir")"
    canon_rel="$SHARED_DIR/$skill"
    canon_abs="$BASE_DIR/$canon_rel"

    if [ ! -e "$canon_abs" ] && [ ! -L "$canon_abs" ]; then
      printf 'ACTION|INSTALL|%s|%s|\n' "$skill" "$canon_rel"
      c_installed=$((c_installed + 1))
      if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$(dirname "$canon_abs")"
        cp -R "$src_dir" "$canon_abs"
        state_data="$(state_upsert_line "$state_data" "CANONICAL|$skill|$canon_rel|$PLUGIN_VERSION|$src_digest")"
      fi
    else
      entry="$(state_get_entry "$state_data" "CANONICAL" "$skill" "$canon_rel")"
      cur_digest="$(dir_digest "$canon_abs" 2>/dev/null || true)"
      if [ -n "$entry" ]; then
        st_ver="$(printf '%s\n' "$entry" | awk -F'|' '{ print $4 }')"
        st_dig="$(printf '%s\n' "$entry" | awk -F'|' '{ print $5 }')"
        if [ "$st_ver" = "$PLUGIN_VERSION" ] && [ "$cur_digest" = "$src_digest" ] && [ "$st_dig" = "$src_digest" ]; then
          printf 'ACTION|KEEP|%s|%s|up-to-date\n' "$skill" "$canon_rel"
          c_kept=$((c_kept + 1))
        else
          printf 'ACTION|UPDATE|%s|%s|\n' "$skill" "$canon_rel"
          c_updated=$((c_updated + 1))
          if [ "$DRY_RUN" -eq 0 ]; then
            rm -rf "$canon_abs"
            mkdir -p "$(dirname "$canon_abs")"
            cp -R "$src_dir" "$canon_abs"
            state_data="$(state_upsert_line "$state_data" "CANONICAL|$skill|$canon_rel|$PLUGIN_VERSION|$src_digest")"
          fi
        fi
      else
        if [ "$cur_digest" = "$src_digest" ]; then
          printf 'ACTION|KEEP|%s|%s|adopted\n' "$skill" "$canon_rel"
          c_kept=$((c_kept + 1))
          if [ "$DRY_RUN" -eq 0 ]; then
            state_data="$(state_upsert_line "$state_data" "CANONICAL|$skill|$canon_rel|$PLUGIN_VERSION|$src_digest")"
          fi
        else
          printf 'ACTION|SKIP|%s|%s|unmanaged-conflict\n' "$skill" "$canon_rel"
          printf 'Warning: unmanaged copy exists at %s (use --force to backup and replace)\n' "$canon_rel" >&2
          c_skipped=$((c_skipped + 1))
        fi
      fi
    fi

    # Dedicated agent targets
    while IFS= read -r pair; do
      [ -z "$pair" ] && continue
      local t_agent t_dir dest_rel dest_abs mat_mode
      t_agent="$(printf '%s\n' "$pair" | awk -F'|' '{ print $1 }')"
      t_dir="$(printf '%s\n' "$pair" | awk -F'|' '{ print $2 }')"
      dest_rel="$t_dir/$skill"
      dest_abs="$BASE_DIR/$dest_rel"

      if [ ! -e "$dest_abs" ] && [ ! -L "$dest_abs" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          if [ "$FORCE_COPY" -eq 1 ]; then
            printf 'ACTION|COPY|%s|%s|\n' "$skill" "$dest_rel"
            c_copied=$((c_copied + 1))
          else
            printf 'ACTION|LINK|%s|%s|\n' "$skill" "$dest_rel"
            c_linked=$((c_linked + 1))
          fi
        else
          mat_mode="$(materialize_target "$canon_abs" "$dest_abs" "$FORCE_COPY")"
          if [ "$mat_mode" = "link" ]; then
            printf 'ACTION|LINK|%s|%s|\n' "$skill" "$dest_rel"
            c_linked=$((c_linked + 1))
          else
            printf 'ACTION|COPY|%s|%s|\n' "$skill" "$dest_rel"
            c_copied=$((c_copied + 1))
          fi
          state_data="$(state_upsert_line "$state_data" "TARGET|$t_agent|$skill|$dest_rel|$mat_mode|$PLUGIN_VERSION|$src_digest")"
        fi
      else
        entry="$(state_get_entry "$state_data" "TARGET" "$skill" "$dest_rel")"
        cur_digest="$(dir_digest "$dest_abs" 2>/dev/null || true)"
        if [ -n "$entry" ]; then
          local st_mode
          st_mode="$(printf '%s\n' "$entry" | awk -F'|' '{ print $5 }')"
          st_ver="$(printf '%s\n' "$entry" | awk -F'|' '{ print $6 }')"
          st_dig="$(printf '%s\n' "$entry" | awk -F'|' '{ print $7 }')"
          if [ "$st_ver" = "$PLUGIN_VERSION" ] && [ "$cur_digest" = "$src_digest" ] && [ "$st_dig" = "$src_digest" ] && { [ "$FORCE_COPY" -eq 0 ] || [ "$st_mode" = "copy" ]; }; then
            printf 'ACTION|KEEP|%s|%s|up-to-date\n' "$skill" "$dest_rel"
            c_kept=$((c_kept + 1))
          else
            printf 'ACTION|UPDATE|%s|%s|\n' "$skill" "$dest_rel"
            c_updated=$((c_updated + 1))
            if [ "$DRY_RUN" -eq 0 ]; then
              mat_mode="$(materialize_target "$canon_abs" "$dest_abs" "$FORCE_COPY")"
              state_data="$(state_upsert_line "$state_data" "TARGET|$t_agent|$skill|$dest_rel|$mat_mode|$PLUGIN_VERSION|$src_digest")"
            fi
          fi
        else
          if [ "$cur_digest" = "$src_digest" ]; then
            printf 'ACTION|KEEP|%s|%s|adopted\n' "$skill" "$dest_rel"
            c_kept=$((c_kept + 1))
            if [ "$DRY_RUN" -eq 0 ]; then
              local det_mode="copy"
              [ -L "$dest_abs" ] && det_mode="link"
              state_data="$(state_upsert_line "$state_data" "TARGET|$t_agent|$skill|$dest_rel|$det_mode|$PLUGIN_VERSION|$src_digest")"
            fi
          else
            printf 'ACTION|SKIP|%s|%s|unmanaged-conflict\n' "$skill" "$dest_rel"
            printf 'Warning: unmanaged copy exists at %s (use --force to backup and replace)\n' "$dest_rel" >&2
            c_skipped=$((c_skipped + 1))
          fi
        fi
      fi
    done <<EOF
$target_pairs
EOF
  done <<EOF
$SELECTED_SKILLS
EOF

  if [ "$DRY_RUN" -eq 0 ]; then
    write_state "$state_abs" "$state_data"
  fi

  printf 'SUMMARY|installed=%d|updated=%d|linked=%d|copied=%d|kept=%d|skipped=%d|backed_up=%d|removed=%d\n' \
    "$c_installed" "$c_updated" "$c_linked" "$c_copied" "$c_kept" "$c_skipped" "$c_backed_up" "$c_removed"
}

install_flow
exit 0
