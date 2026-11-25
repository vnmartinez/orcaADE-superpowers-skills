# Plugin Multiagente (`orcaADE-superpowers-skills`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Empacotar as 4 skills do repositório `orcaADE-superpowers-skills` como um plugin/bundle multiagente versionado (`plugin/manifest.json` + `scripts/install-skills.sh` + `plugin/README.md`) instalável com um comando em todos os CLIs suportados pelo Orca ADE, com suíte TDD em bash puro e atualização retrocompatível do `README.md` raiz.

**Architecture:** As 4 pastas de skills na raiz permanecem como fonte única de verdade. Um manifesto declarativo (`plugin/manifest.json`) fixa versão SemVer, layout compatível com o `orca skills install` (`.agents/skills`, `.agents/.orca-superpowers-backups`, `.agents/.orca-superpowers-installed`), lista das 4 skills e mapa `agentPaths` dos 12 agentes com pasta própria (os demais 30 agentes do Orca 1.4.273 e quaisquer agentes futuros usam `.agents/skills`). Um instalador em bash puro (`scripts/install-skills.sh`) descobre agentes dinamicamente via `orca agent installed --worktree active --json` (com suporte a `--agent`, `--agents-file` e fallback `$HOME`) e executa instalação, atualização idempotente, `--dry-run`, `--force` com backup, `--local` e `--uninstall` sem nunca apagar skills de terceiros.

**Tech Stack:** Bash + utilitários POSIX do Git (`awk`, `sed`, `grep`, `tr`, `cut`, `cp`, `mv`, `rm`, `mkdir`, `ln`, `find`, `cksum`), JSON (manifesto + fixtures), Markdown, Orca CLI (`orca agent installed`).

**Spec:** `docs/superpowers/specs/2026-11-25-plugin-multiagente-design.md`

## Global Constraints

- **Zero dependências externas (regra "quem tem Orca tem Git"):** usar exclusivamente `bash` e utilitários POSIX que acompanham o Git (`awk`, `sed`, `grep`, `tr`, `cut`, `cp`, `mv`, `rm`, `mkdir`, `ln`, `find`, `cksum`). **Proibido** usar `python`, `python3`, `node`, `jq`, `pwsh`, `powershell`, `bats` ou `cmd.exe` no instalador e nos testes.
- **POSIX `awk` portátil:** evitar extensões exclusivas do GNU `awk` (`gensub`, 3º argumento de `match`) para rodar identicamente em BSD `awk` (macOS) e GNU `awk` (Linux/Git Bash).
- **Cross-platform e terminação LF:** todos os scripts `.sh` devem usar LF (`\n`, sem CRLF) e passar em `bash -n`. Caminhos no instalador, manifesto e `plugin/README.md` sempre relativos ou com `$HOME`/`/` — nunca `%APPDATA%`, `%TEMP%`, `$env:USERPROFILE` ou `\`.
- **Fonte única de verdade e preservação das 4 skills:** não duplicar nem alterar `orca-superpowers-orchestrator/SKILL.md`, `orca-superpowers-orchestration-auto/SKILL.md`, `orca-superpowers-review-loop/SKILL.md`, `orca-superpowers-merge/SKILL.md`, seus `README.md` individuais nem `orca-superpowers-orchestration-auto/scripts/get-quotas.sh`.
- **Descoberta dinâmica (nunca fixa):** `scripts/install-skills.sh` nunca fixa uma lista fechada de 4 ou 5 CLIs; descobre via `--agent`, `--agents-file`, `orca agent installed --worktree active --json` ou fallback `$HOME`, tratando qualquer agente desconhecido via `.agents/skills`.
- **Zero PII e zero segredos:** fixtures, manifesto, recibo de estado (`.orca-superpowers-installed`) e logs nunca gravam e-mails, UUIDs pessoais, tokens ou caminhos absolutos do usuário (`C:\Users\...`).
- **Retrocompatibilidade:** `bash tests/test-orchestration-auto.sh` deve continuar passando 100% após todas as tarefas (incluindo os asserts sobre os 5 destinos manuais no `README.md` raiz).

## Review Focus

- **Conflito com cópia manual pré-existente e backup sem perda de dados:** uma pasta não gerenciada com arquivo extra em `.agents/skills/<skill>` ou `.claude/skills/<skill>` deve gerar `SKIP` na execução padrão (arquivo extra preservado) e ser movida inteira para `.agents/.orca-superpowers-backups/<timestamp>/<rel_path>` sob `--force` (pinned in Task 3).
- **Isolamento absoluto de skills de terceiros:** skills fora de `plugin/manifest.json` (ex.: `third-party-skill` em `.agents/skills/` e `.claude/skills/`) jamais podem ser tocadas, movidas ou removidas em `install`, `--force` ou `--uninstall` (pinned in Task 3).
- **Agente futuro não mapeado e modo `--local` sem poluir o projeto:** um agente inédito (`future-cli`) retornado em `agents[].id` deve ser atendido via `.agents/skills` sem erro; e `--local` num projeto que só possui `.claude/` não deve criar `.cursor/`, `.kiro/` nem `.gemini/` (pinned in Task 2 e Task 3).
- **Fallback automático de symlink para cópia (Windows sem Developer Mode / `--copy`) e `--dry-run` estritamente read-only:** `--copy` (e fallback quando `ln -s` não cria symlink real) deve manter idempotência (`KEEP` na 2ª rodada) e reversibilidade no `--uninstall`; `--dry-run` não pode criar diretórios nem gravar arquivo de estado (pinned in Task 2 e Task 3).
- **Cópia recursiva completa de skills com subdiretórios (`scripts/get-quotas.sh`) e preservação da suíte anterior:** instalar `orca-superpowers-orchestration-auto` deve copiar `scripts/get-quotas.sh` intacto e executável por `bash`, e atualizar o `README.md` raiz deve manter `bash tests/test-orchestration-auto.sh` 100% verde (pinned in Task 2 e Task 4).

---

### Task 1: Manifesto Declarativo (`plugin/manifest.json`), Fixture Sem PII e Suíte Base TDD

**Files:**
- Create: `tests/fixtures/plugin-agents-minimal.json`
- Create: `tests/test-plugin-installer.sh`
- Create: `plugin/manifest.json`

**Interfaces:**
- Produces (`plugin/manifest.json`):
  - `manifestVersion`: `1`
  - `id`: `"superpowers-skills"`, `name`: `"Orca Superpowers Skills"`, `version`: `"1.0.0"`, `repository`, `license`: `"MIT"`
  - `layout`: `{ "sharedDir": ".agents/skills", "backupDir": ".agents/.orca-superpowers-backups", "stateFile": ".agents/.orca-superpowers-installed" }`
  - `skills`: `["orca-superpowers-orchestrator", "orca-superpowers-orchestration-auto", "orca-superpowers-review-loop", "orca-superpowers-merge"]`
  - `agentPaths`: os 12 agentes com pasta própria do Orca 1.4.273 (`claude`, `antigravity`, `cursor`, `droid`, `continue`, `trae`, `grok`, `aug`, `zcode`, `codebuddy`, `kiro`, `openclaude`), cada um com `{ "global": "<rel>", "local": "<rel>" }`.
- Produces (`tests/fixtures/plugin-agents-minimal.json`):
  - JSON no formato de `orca agent installed --worktree active --json` contendo `claude` (`default: true`), `codex`, `antigravity` e `future-cli` (zero PII).

- [x] **Step 1: Criar fixture `tests/fixtures/plugin-agents-minimal.json` e os testes iniciais (RED) em `tests/test-plugin-installer.sh`**

1. Criar `tests/fixtures/plugin-agents-minimal.json` sem PII com 4 entradas em `result.agents[]`: `claude` (`default: true`), `codex`, `antigravity` e `future-cli`.
2. Criar `tests/test-plugin-installer.sh` em bash puro (LF `\n`, helpers `assert_eq`, `assert_contains`, `assert_not_contains`, `assert_exists`, `assert_not_exists`, contadores `PASS`/`FAIL`, `exit 1` se `FAIL > 0`) contendo os testes da Task 1:
   - `test_manifest_exists_and_valid_json`: valida que `plugin/manifest.json` existe, tem chaves/colchetes balanceados em POSIX `awk`, contém `manifestVersion: 1`, `id: "superpowers-skills"`, `version` no formato SemVer (`[0-9]+\.[0-9]+\.[0-9]+`), `layout.sharedDir == ".agents/skills"`, `layout.backupDir == ".agents/.orca-superpowers-backups"` e `layout.stateFile == ".agents/.orca-superpowers-installed"`.
   - `test_manifest_skills_match_repo_root`: valida que todas as 4 skills listadas em `plugin/manifest.json` existem na raiz do repositório com `SKILL.md` (`orca-superpowers-orchestrator`, `orca-superpowers-orchestration-auto`, `orca-superpowers-review-loop`, `orca-superpowers-merge`).
   - `test_manifest_agent_paths_complete`: valida que os 12 agentes com pasta própria (`claude`, `antigravity`, `cursor`, `droid`, `continue`, `trae`, `grok`, `aug`, `zcode`, `codebuddy`, `kiro`, `openclaude`) possuem `global` e `local` preenchidos, com `antigravity.global == ".gemini/config/skills"` e `antigravity.local == ".agents/skills"`.
   - `test_manifest_and_fixture_no_pii_or_windows_paths`: asserta ausência de `@`, `organizationUuid`, `C:\Users`, `%APPDATA%`, `%TEMP%`, `$env:USERPROFILE` e `\` em `plugin/manifest.json` e `tests/fixtures/plugin-agents-minimal.json`.

- [x] **Step 2: Rodar a suíte e confirmar que falha (RED)**

Run: `bash tests/test-plugin-installer.sh`
Expected: FAIL indicando que `plugin/manifest.json` ainda não existe.

- [x] **Step 3: Criar `plugin/manifest.json`**

Escrever `plugin/manifest.json` com o esquema exato da Seção 4 da spec (`docs/superpowers/specs/2026-11-25-plugin-multiagente-design.md`).

- [x] **Step 4: Rodar os testes da Task 1 e confirmar que passam (GREEN)**

Run: `bash tests/test-plugin-installer.sh`
Expected: todos os testes da Task 1 PASS (`FAIL=0`).

- [x] **Step 5: Commit atômico da Task 1**

```bash
git add plugin/manifest.json tests/fixtures/plugin-agents-minimal.json tests/test-plugin-installer.sh
git commit -m "feat: adiciona manifesto do plugin multiagente, fixture e testes base"
```

---

### Task 2: Instalador Core (`scripts/install-skills.sh`) — Descoberta Dinâmica, Layout Orca, `--dry-run`, `--list`, `--agent`, `--skill` e Idempotência

**Files:**
- Modify: `tests/test-plugin-installer.sh` (adicionar testes do instalador core e smoke tests em `HOME` temporário)
- Create: `scripts/install-skills.sh`

**Interfaces:**
- Consumes: `plugin/manifest.json` (lido dinamicamente em POSIX `awk`), pastas `<repo>/<skill>` na raiz do repo, `orca agent installed --worktree active --json` (ou `--agents-file <path>`).
- Produces (`scripts/install-skills.sh`, LF `\n`, executável via `bash scripts/install-skills.sh`):
  - Flags: `--skill <name>` (repetível), `--agent <csv|universal>`, `--local`, `--target-dir <dir>`, `--dry-run`, `--force`, `--uninstall`, `--copy`, `--agents-file <path>`, `--list`, `-h|--help`.
  - Funções internas modulares: `parse_manifest`, `parse_agents_json`, `resolve_target_agents`, `dir_digest`, `read_state`, `write_state`, `materialize_target`, `install_flow`.
  - Contrato stdout:
    - `PLUGIN|<id>|<version>|<global|local>|<apply|dry-run>|agents:<csv|universal>`
    - `ACTION|<INSTALL|UPDATE|LINK|COPY|KEEP|SKIP|BACKUP|REMOVE>|<skill>|<rel_path>|<detail>`
    - `SUMMARY|installed=<n>|updated=<n>|linked=<n>|copied=<n>|kept=<n>|skipped=<n>|backed_up=<n>|removed=<n>`
  - Exit codes: `0` ok, `1` erro operacional (skill desconhecida, manifesto/agents-file ausente), `2` argumento CLI inválido.

- [ ] **Step 1: Adicionar testes do instalador core em `tests/test-plugin-installer.sh` (RED)**

Adicionar e invocar os seguintes testes (todos usando `mktemp -d` + `trap` de limpeza para isolamento total):
1. `test_installer_exists_syntax_lf_and_no_forbidden_runtimes`: `scripts/install-skills.sh` existe, passa em `bash -n`, contém apenas LF (`\n`), não contém `python`, `python3`, `node`, `jq`, `pwsh`, `powershell`, `cmd.exe`, `%APPDATA%`, `%TEMP%` nem `$env:USERPROFILE`.
2. `test_installer_list_and_help`: `--list` retorna `0` e imprime `superpowers-skills`, `1.0.0` e as 4 skills; `--help` retorna `0` e documenta `--dry-run`, `--force`, `--uninstall`, `--local`, `--agent`, `--skill`; argumento inválido `--nao-existe` retorna exit `2`; `--skill nao-existe` retorna exit `1`.
3. `test_installer_dry_run_is_read_only`: rodando `HOME="$tmp" bash scripts/install-skills.sh --agents-file tests/fixtures/plugin-agents-minimal.json --dry-run`, saída contém `PLUGIN|superpowers-skills|1.0.0|global|dry-run|agents:claude,codex,antigravity,future-cli`, `ACTION|INSTALL|orca-superpowers-orchestrator|.agents/skills/orca-superpowers-orchestrator|`, `ACTION|LINK|orca-superpowers-orchestrator|.claude/skills/orca-superpowers-orchestrator|` (ou `COPY` sob `--copy`), `ACTION|LINK|orca-superpowers-orchestrator|.gemini/config/skills/orca-superpowers-orchestrator|`, e **nenhum** arquivo ou diretório é criado em `$tmp` (`find "$tmp" -mindepth 1` vazio).
4. `test_installer_global_smoke_dynamic_and_subdirectories`: rodando `HOME="$tmp" bash scripts/install-skills.sh --agents-file tests/fixtures/plugin-agents-minimal.json`, exit `0`; as 4 skills existem em `$tmp/.agents/skills/<skill>/SKILL.md`; `orca-superpowers-orchestration-auto/scripts/get-quotas.sh` existe e passa em `bash -n`; destinos de `claude` (`$tmp/.claude/skills/<skill>/SKILL.md`) e `antigravity` (`$tmp/.gemini/config/skills/<skill>/SKILL.md`) existem; `codex` e `future-cli` não causam erro nem criam pastas indevidas; `$tmp/.agents/.orca-superpowers-installed` existe e não contém `$tmp` nem `@`.
5. `test_installer_idempotent_second_run`: rodando uma segunda vez no mesmo `$tmp`, exit `0`, saída contém `SUMMARY|installed=0|updated=0|linked=0|copied=0|kept=12|skipped=0|backed_up=0|removed=0` (4 canônicos + 4 `claude` + 4 `antigravity` = 12 `KEEP`).
6. `test_installer_universal_and_skill_filter`: rodando com `--agent universal --skill orca-superpowers-merge`, instala apenas `$tmp/.agents/skills/orca-superpowers-merge` e não cria `.claude` nem `.gemini` nem as outras 3 skills.
7. `test_installer_copy_mode_idempotent`: rodando com `--copy --agents-file tests/fixtures/plugin-agents-minimal.json`, destinos em `.claude/skills` são diretórios reais (não symlinks) registrados como `copy` no estado, e a 2ª execução com `--copy` produz `kept=12` e `copied=0`.

- [ ] **Step 2: Rodar a suíte e confirmar que falha (RED)**

Run: `bash tests/test-plugin-installer.sh`
Expected: FAIL indicando que `scripts/install-skills.sh` ainda não existe.

- [ ] **Step 3: Implementar `scripts/install-skills.sh` (fluxo core de instalação)**

Implementar `scripts/install-skills.sh` em bash puro + POSIX `awk` (LF `\n`):
- Parse de CLI (`--skill`, `--agent`, `--local`, `--target-dir`, `--dry-run`, `--force`, `--uninstall`, `--copy`, `--agents-file`, `--list`, `-h|--help`).
- `parse_manifest`: POSIX `awk` lê `plugin/manifest.json` emitindo `META|id|...`, `META|version|...`, `LAYOUT|sharedDir|...`, `LAYOUT|backupDir|...`, `LAYOUT|stateFile|...`, `SKILL|<name>` e `AGENT_PATH|<agent>|<global>|<local>`.
- `parse_agents_json`: POSIX `awk` (mesmo padrão validado em `get-quotas.sh`) extrai `agents[].id` de `orca agent installed --worktree active --json` ou `--agents-file`.
- `resolve_target_agents`: aplica precedência `--agent` → `--agents-file` → `orca agent installed` → fallback detectando pastas-pai em `$BASE_DIR`. Deduplica agentes mantendo ordem determinística.
- `dir_digest`: lista arquivos regulares relativos ordenados (`LC_ALL=C`), aplica `cksum` por arquivo + caminho relativo e reduz com `cksum`.
- `materialize_target`: cria cópia canônica (`cp -R`) ou link de agente (`MSYS=winsymlinks:nativestrict ln -s` verificando `[ -L "$dest" ]`, com fallback automático para `cp -R` quando o SO não suporta symlink nativo ou quando `--copy` estiver ativo).
- Leitura e escrita atômica de `$STATE_FILE` com caminhos exclusivamente relativos a `$BASE_DIR`.
- Emissão exata das linhas `PLUGIN|...`, `ACTION|...` e `SUMMARY|...`.

- [ ] **Step 4: Rodar os testes da Task 2 e confirmar que passam (GREEN)**

Run: `bash tests/test-plugin-installer.sh`
Expected: todos os testes das Tasks 1 e 2 PASS (`FAIL=0`).

- [ ] **Step 5: Commit atômico da Task 2**

```bash
git add scripts/install-skills.sh tests/test-plugin-installer.sh
git commit -m "feat: adiciona instalador bash multiagente com descoberta dinamica e dry-run"
```

---

### Task 3: Conflitos, Backup (`--force`), Atualização In-Place, Modo `--local` e `--uninstall` Reversível

**Files:**
- Modify: `tests/test-plugin-installer.sh` (adicionar testes de conflito/backup, atualização de versão, `--local`, `--uninstall` e proteção de skills de terceiros)
- Modify: `scripts/install-skills.sh` (implementar/completar `backup_path`, `update` in-place, regras de `--local` e `uninstall_flow`)

**Interfaces:**
- Consumes: `parse_manifest`, `resolve_target_agents`, `dir_digest`, `read_state`, `write_state` de `scripts/install-skills.sh` (Task 2).
- Produces:
  - `backup_path <base> <rel_path> <timestamp>`: move `<base>/<rel_path>` inteiro para `<base>/<backupDir>/<timestamp>/<rel_path>`, emitindo `ACTION|BACKUP|<skill>|<rel_path>|<backup_rel_path>`.
  - `uninstall_flow`: remove destinos gerenciados (links/cópias e canônico) respeitando `--skill`, `--agent`, `--dry-run` e `--force`, sem nunca tocar skills de terceiros nem cópias manuais não gerenciadas (salvo com `--force`, fazendo backup primeiro).
  - Modo `--local`: só cria links em `agentPaths.<agent>.local` quando `local != sharedDir` **e** o diretório-pai do agente (ex.: `<proj>/.claude`) já existir no projeto.

- [ ] **Step 1: Adicionar testes de conflito, backup, update, `--local` e `--uninstall` em `tests/test-plugin-installer.sh` (RED)**

Adicionar e invocar:
1. `test_installer_conflict_skip_and_force_backup`:
   - Pré-criar em `$tmp/.agents/skills/orca-superpowers-merge/` um `SKILL.md` customizado + `extra-user-note.txt`.
   - Pré-criar em `$tmp/.claude/skills/orca-superpowers-merge/` uma cópia divergente com `claude-custom.txt`.
   - Rodar sem `--force`: exit `0`, saída contém `ACTION|SKIP|orca-superpowers-merge|.agents/skills/orca-superpowers-merge|` e `ACTION|SKIP|orca-superpowers-merge|.claude/skills/orca-superpowers-merge|`; ambos os arquivos extras continuam intactos no lugar original.
   - Rodar com `--force`: exit `0`, saída contém `ACTION|BACKUP|orca-superpowers-merge|.agents/skills/orca-superpowers-merge|` e `ACTION|BACKUP|orca-superpowers-merge|.claude/skills/orca-superpowers-merge|`; ambos os arquivos extras existem dentro de `$tmp/.agents/.orca-superpowers-backups/`; e os destinos finais agora têm o conteúdo canônico do repo.
2. `test_installer_inplace_update_when_managed_version_changes`:
   - Instalar normalmente em `$tmp`.
   - Simular instalação de versão antiga alterando no `$tmp/.agents/.orca-superpowers-installed` a versão de `1.0.0` para `0.9.0` e o digest para `0-0`.
   - Rodar novamente **sem `--force`**: exit `0`, saída contém `ACTION|UPDATE|orca-superpowers-merge|.agents/skills/orca-superpowers-merge|`, `backed_up=0`, e o estado volta para `1.0.0`.
3. `test_installer_local_mode_respects_existing_agent_dirs`:
   - Criar projeto temporário `$proj` contendo apenas `$proj/.claude` (sem `.cursor`, `.kiro`, `.gemini`).
   - Rodar `bash scripts/install-skills.sh --local --target-dir "$proj" --agents-file tests/fixtures/plugin-agents-minimal.json` (e repetir com `--agent claude,cursor,kiro,antigravity,codex`).
   - Assertar que `$proj/.agents/skills/<skill>/SKILL.md` e `$proj/.claude/skills/<skill>/SKILL.md` existem, enquanto `$proj/.cursor`, `$proj/.kiro` e `$proj/.gemini` **não** foram criados.
4. `test_installer_uninstall_reversibility_and_third_party_isolation`:
   - Instalar em `$tmp` com `--agents-file tests/fixtures/plugin-agents-minimal.json` (testar também cenário com `--copy`).
   - Criar skills de terceiro `$tmp/.agents/skills/third-party-skill/SKILL.md` e `$tmp/.claude/skills/third-party-skill/SKILL.md`.
   - Rodar `--uninstall --dry-run`: imprime `ACTION|REMOVE|...` mas não apaga nada.
   - Rodar `--uninstall`: exit `0`, remove as 4 skills de `.agents/skills`, `.claude/skills` e `.gemini/config/skills`, remove ou limpa `.orca-superpowers-installed`, e **mantém intactos** `$tmp/.agents/skills/third-party-skill/SKILL.md` e `$tmp/.claude/skills/third-party-skill/SKILL.md`.
5. `test_installer_uninstall_preserves_unmanaged_copy_unless_forced`:
   - Sem instalar via plugin, criar cópia manual `$tmp/.agents/skills/orca-superpowers-merge/manual.txt`.
   - Rodar `--uninstall`: emite `ACTION|SKIP|orca-superpowers-merge|.agents/skills/orca-superpowers-merge|` e preserva `manual.txt`.
   - Rodar `--uninstall --force`: faz `BACKUP` para `.agents/.orca-superpowers-backups/` (preservando `manual.txt` no backup) e remove o diretório original.
6. `test_installer_fallback_without_orca_detects_home_dirs`:
   - Criar `$tmp/.claude` e `$tmp/.cursor` (sem `--agents-file` e com `PATH` contendo diretório mínimo sem `orca`, ou com flag/env que simule ausência do `orca`, ex.: `ORCA_BIN=/nonexistent`).
   - Rodar `HOME="$tmp" ORCA_BIN=/nonexistent bash scripts/install-skills.sh`: instala `.agents/skills`, `.claude/skills` e `.cursor/skills` sem criar `.kiro` ou `.gemini`.

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `bash tests/test-plugin-installer.sh`
Expected: FAIL nos testes novos de `--force` backup, `--local`, `--uninstall` e fallback sem `orca`.

- [ ] **Step 3: Implementar backup, update in-place, modo `--local`, `ORCA_BIN` fallback e `--uninstall` em `scripts/install-skills.sh`**

Implementar em `scripts/install-skills.sh` mantendo POSIX puro (LF `\n`):
- Suporte a `ORCA_BIN="${ORCA_BIN:-orca}"` para descoberta limpa e testável sem depender de `PATH` mutado.
- `backup_path`: gera timestamp `YYYYMMDD-HHMMSS` (com sufixo incremental se já existir no mesmo segundo), cria pasta pai no backup e move o diretório/link original com `mv`, imprimindo `ACTION|BACKUP|...`.
- Fluxo de `UPDATE` in-place para entradas presentes em `$STATE_FILE` cujo `version` ou `digest` divirja da fonte.
- Regra `--local`: resolve `agentPaths.<agent>.local`; se igual a `sharedDir`, ignora (coberto pelo canônico); senão verifica `[ -d "$BASE_DIR/$(dirname "$agent_rel_dir")" ]` antes de criar link/cópia.
- `uninstall_flow`: valida propriedade via `$STATE_FILE` ou symlink apontando para `$SHARED_DIR/<skill>`; respeita `--dry-run`, `--skill`, `--agent` e `--force`; reescreve `$STATE_FILE` mantendo apenas entradas restantes (ou remove o arquivo se vazio).

- [ ] **Step 4: Rodar a suíte completa do instalador e confirmar que tudo passa (GREEN)**

Run: `bash tests/test-plugin-installer.sh`
Expected: todos os testes das Tasks 1, 2 e 3 PASS (`FAIL=0`).

- [ ] **Step 5: Commit atômico da Task 3**

```bash
git add scripts/install-skills.sh tests/test-plugin-installer.sh
git commit -m "feat: adiciona backup com force, modo local, update in-place e uninstall seguro"
```

---

### Task 4: Documentação (`plugin/README.md` + `README.md` Raiz) e Verificação Completa

**Files:**
- Modify: `tests/test-plugin-installer.sh` (adicionar asserts de `plugin/README.md`, `README.md` raiz e integridade inalterada das 4 skills)
- Create: `plugin/README.md`
- Modify: `README.md` (seção `## Instalação`)

**Interfaces:**
- Consumes: `plugin/manifest.json` e CLI de `scripts/install-skills.sh` (Tasks 1–3).
- Produces:
  - `plugin/README.md`: guia completo do plugin multiagente (comando único, todas as flags, tabela dos destinos globais e locais do Orca, fallback Windows Git Bash, atualização, rollback via backup e próximos passos de publicação).
  - `README.md` (raiz): seção `## Instalação` com comando único (`bash scripts/install-skills.sh`), opções rápidas (`--dry-run`, `--local`, `--force`, `--uninstall`) e link para `[plugin/README.md](plugin/README.md)`, seguida de `### Instalação manual (alternativa)` preservando intactos os blocos bash e PowerShell dos 5 destinos.

- [ ] **Step 1: Adicionar asserts de documentação e verificação final em `tests/test-plugin-installer.sh` (RED)**

Adicionar e invocar:
1. `test_plugin_readme`: valida existência de `plugin/README.md` e presença de `bash scripts/install-skills.sh`, `--dry-run`, `--force`, `--uninstall`, `--local`, `--agent universal`, `.agents/skills`, `.claude/skills`, `.gemini/config/skills`, `.agents/.orca-superpowers-backups`, `plugin/manifest.json`, além de ausência de `python3`, `jq`, `powershell`, `%APPDATA%` e e-mail PII.
2. `test_root_readme_plugin_installer_and_manual_fallback`: valida em `README.md` raiz a presença do comando único `bash scripts/install-skills.sh`, link `[plugin/README.md](plugin/README.md)`, `--dry-run`, `--uninstall`, e preservação dos 5 destinos manuais (bash + PowerShell).

- [ ] **Step 2: Rodar a suíte e confirmar que falha (RED)**

Run: `bash tests/test-plugin-installer.sh`
Expected: FAIL indicando ausência de `plugin/README.md` e de `bash scripts/install-skills.sh` no `README.md` raiz.

- [ ] **Step 3: Criar `plugin/README.md` e atualizar `README.md` raiz**

1. Criar `plugin/README.md` em português, objetivo e completo, cobrindo:
   - Comando único de instalação (`bash scripts/install-skills.sh`, rodando no terminal macOS/Linux ou no Git Bash no Windows, sem caminhos com `\`).
   - Como o plugin descobre os agentes (`orca agent installed --worktree active --json` + mapa `plugin/manifest.json`).
   - Tabela de destinos (pasta canônica compartilhada `.agents/skills` atendendo 30 agentes como `codex`, `opencode`, `opencode2`, `copilot`, `gemini`, `kimi` etc., + os 12 agentes com pasta própria: `claude`, `antigravity`, `cursor`, `droid`, `continue`, `trae`, `grok`, `aug`, `zcode`, `codebuddy`, `kiro`, `openclaude`).
   - Referência das flags (`--dry-run`, `--agent`, `--skill`, `--local`, `--target-dir`, `--force`, `--uninstall`, `--copy`, `--list`).
   - Como atualizar (`git pull && bash scripts/install-skills.sh`) e onde ficam os backups (`.agents/.orca-superpowers-backups`).
   - Próximos passos (publicação de release/catálogo remoto fora de escopo atual).
2. Atualizar `README.md` raiz (`## Instalação`):
   - Colocar o **Instalador multiagente (Recomendado — 1 comando)** no topo da seção `## Instalação` com `bash scripts/install-skills.sh`, exemplos de `--dry-run`, `--local`, `--force`, `--uninstall` e link `[plugin/README.md](plugin/README.md)`.
   - Mover os blocos atuais (`macOS / Linux / Git Bash` e `Windows PowerShell`) para `### Instalação manual (alternativa)` preservando exatamente os 5 destinos sem alterar nenhuma string testada por `tests/test-orchestration-auto.sh`.

- [ ] **Step 4: Rodar ambas as suítes + smoke test real com `--dry-run` no Orca (GREEN)**

Run:
```bash
bash tests/test-plugin-installer.sh
bash tests/test-orchestration-auto.sh
bash scripts/install-skills.sh --dry-run
```
Expected:
- `tests/test-plugin-installer.sh`: `FAIL=0`.
- `tests/test-orchestration-auto.sh`: `FAIL=0`.
- `bash scripts/install-skills.sh --dry-run`: exit `0`, detecta os agentes reais desta máquina via `orca agent installed` e imprime o plano sem alterar nenhum arquivo no `$HOME`.
- `git diff --name-only` não toca nenhum `*/SKILL.md` nem `*/README.md` das 4 skills existentes.

- [ ] **Step 5: Commit atômico da Task 4**

```bash
git add plugin/README.md README.md tests/test-plugin-installer.sh
git commit -m "docs: adiciona README do plugin multiagente e atualiza instalacao na raiz"
```
