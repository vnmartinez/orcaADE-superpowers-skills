# `orca-superpowers-orchestration-auto` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar a skill `orca-superpowers-orchestration-auto` cross-platform (**Windows, macOS e Linux**) no padrão do repositório `orcaADE-superpowers-skills`, com coleta real de cotas em Python 3 (stdlib pura), motor determinístico de roteamento inspirado no Alethe, trilha de auditoria e atualização do `README.md` da raiz para os 5 destinos nos 3 SOs.

**Architecture:** Um único script Python 3 sem dependências externas (`orca-superpowers-orchestration-auto/scripts/get_quotas.py`) expõe parsers puros e coleta real de cota para `claude`, `codex`, `agy` (via keyring nativo por SO, degradando para não crítico quando ausente) e `opencode` em JSON normalizado. A skill (`SKILL.md` + `README.md`) documenta o protocolo portátil no Orca ADE (TUI obrigatória, zero perguntas de alocação, gate humano único no Passo 2, regras determinísticas, presets JSON e trilha de auditoria). Uma suíte TDD portátil (`tests/test_orchestration_auto.py`, `python3 -m unittest`) valida parsers offline, degradação por SO, integridade dos presets JSON, ausência de caminhos Windows-only e documentação de instalação nos 5 destinos.

**Tech Stack:** Markdown (skills Orca ADE), Python 3.10+ (stdlib pura: `urllib.request`, `json`, `pathlib`, `shutil`, `subprocess`, `ctypes`, `unittest`), JSON, Orca CLI.

**Spec:** `docs/superpowers/specs/2026-11-24-orca-superpowers-orchestration-auto-design.md`

## Global Constraints

- **Cross-platform obrigatório (Windows, macOS e Linux):** nenhum comando ou caminho de exemplo Windows-only na skill (`SKILL.md` / `README.md`). Usar `python3 <caminho>/scripts/get_quotas.py`, caminhos portáteis (`~/.claude`, `~/.codex`, `~/.gemini`, `$HOME`, `pathlib.Path.home()`), e resolução portátil de binários (`shutil.which` em Python; `command -v` / `Get-Command` quando documentado por SO).
- **Runtime único, zero dependências externas:** apenas Python 3 biblioteca padrão (`scripts/get_quotas.py` e `tests/test_orchestration_auto.py`). Não criar scripts paralelos `.ps1`/`.sh` duplicados.
- **Provedor sem leitura por SO não é crítico:** onde a leitura de credencial não existir ou falhar (ex.: `agy` em Linux sem `secret-tool`/Secret Service, ou `opencode` em qualquer SO), retornar `status != "ready"`, `rateLimited: false`, `used: null` e explicitar na skill que esse provedor nunca bloqueia nem aciona fallback.
- Frontmatter YAML de `SKILL.md` contém `name: orca-superpowers-orchestration-auto` e `description: Use when ...` em inglês; corpo de `SKILL.md` e `README.md` em português.
- Protocolo Orca ADE idêntico às demais skills: `--worktree active`, TUI interativa obrigatória (`--focus` + `wait --for tui-idle`), zero fallback para `-p`/`--print`/`exec`/`run`, `<ORQ_HANDLE>` via `orca terminal show --json` antes do Passo 1, conclusão somente por `ETAPA <planner|executor|reviewer> CONCLUÍDA`.
- **Nunca** perguntar ao usuário qual agente/modelo executa cada papel; gate humano único no Passo 2 (com `onAllCritical` / `onBothCritical` configurável em `run-cheapest` [default] | `ask` | `block`).
- **Invariante de segurança:** nenhum comando, script ou log pode imprimir tokens (`accessToken`, `access_token`, `refresh_token`, `Authorization`, `CLAUDE_OAUTH_TOKEN`).
- Modelos nos presets e exemplos restritos aos disponíveis: `gemini-4-neon-{low,medium,high,xhigh}`, `gemini-4-carbon-{low,medium,high}`, `gemini-4-argon-{low,medium,high}`, `gemini-4-hydrogen-{low,medium,high,xhigh}`, `gemini-pro-orchestrator[-neon|-argon]`, `gemini-3.8-flash-{low,medium,high}`, `claude-opus-5-5[-low|-medium|-high]`, `claude-sonnet-5-5[-low|-medium|-high]`, `haiku`, `gpt-oss-120b-medium`, `codex` (`null`/default `~/.codex/config.toml`).
- Instalação no `README.md` da raiz cobre os **5 destinos** (`~/.claude/skills`, `~/.gemini/config/plugins/superpowers/skills`, `~/.codex/skills`, `~/.agents/skills`, `~/.config/opencode/skills`) em **macOS/Linux (POSIX)** e **Windows (PowerShell)**.

## Review Focus

- **Claude `seven_day_opus` nulo com `limits[]`:** quando `seven_day_opus` é `null`, `parse_claude_usage` deve preencher `windows["opus"]` a partir de `limits[]` (`kind == "weekly_scoped"`, `scope.surface is None`, `display_name == "Opus"`), ignorando limites com `scope.surface` preenchido (pinned in Task 1).
- **Codex plano somente semanal (Pro Lite):** quando `primary_window` traz janela > 1440 min (ex.: 604800 s) e `secondary_window` é nulo/curto, `parse_codex_usage` deve trocar para `windows["week"]` e manter `windows["5h"] == 0.0` (pinned in Task 1).
- **Antigravity cross-platform (User-Agent + keyring ausente em Linux/macOS):** `get_quotas.py` deve enviar `User-Agent` contendo `antigravity` (sem ele o endpoint responde HTTP 403), tentar refresh único via `agy models` em HTTP 401, e degradar graciosamente para `status: "no_auth"|"unavailable"` com `rateLimited: False`, `used: None` quando o keyring do SO não existir (ex.: Linux sem `secret-tool`), sem nunca imprimir tokens (pinned in Task 1).
- **Integridade de presets JSON, guarda `readOnly` e ausência de comandos/caminhos Windows-only:** em `SKILL.md`, todo `role` referenciado em `rules` deve existir em `roles`, nenhum papel `readOnly: true` pode apontar `fallback` para `readOnly: false` ou para si mesmo, e `SKILL.md`/`README.md` da skill não podem conter `%TEMP%`, `%APPDATA%`, `AppData\Local`, `$env:USERPROFILE` ou `powershell -NoProfile -ExecutionPolicy Bypass` (pinned in Task 2 e Task 3).
- **Portabilidade real da suíte de testes:** `tests/test_orchestration_auto.py` deve rodar exclusivamente com `python3 -m unittest` usando `pathlib.Path` e mocks offline, passando de forma idêntica em Windows, macOS e Linux sem nenhuma asserção dependente de SO (pinned in Task 1 e revalidado na Task 3).

---

### Task 1: Coletor de Cotas Cross-Platform (`scripts/get_quotas.py`) + Suíte Base TDD

**Files:**
- Create: `tests/test_orchestration_auto.py`
- Create: `orca-superpowers-orchestration-auto/scripts/get_quotas.py`

**Interfaces:**
- Produces (módulo Python 3 importável em `orca-superpowers-orchestration-auto/scripts/get_quotas.py` com guarda `if __name__ == "__main__":`):
  - `unavailable_fitness(status: str, reason: str) -> dict` — retorna `{"status": status, "reason": reason, "worst": None, "used": None, "resetsAt": None, "rateLimited": False, "windows": {}}`
  - `parse_claude_usage(body: dict) -> dict` — retorna `{"status": "ready", "worst": str, "used": int, "resetsAt": str | None, "rateLimited": False, "windows": dict[str, float]}`
  - `parse_codex_usage(body: dict) -> dict` — retorna `{"status": "ready", "plan": str, "worst": str, "used": int, "resetsAt": str | None, "rateLimited": bool, "windows": dict[str, float]}`
  - `parse_antigravity_usage(body: dict) -> dict` — retorna `{"status": "ready", "worst": str, "used": int, "resetsAt": str | None, "rateLimited": bool, "windows": dict[str, float], "buckets": list[dict]}`
  - `discover_antigravity_token(platform_name: str | None = None, runner=None) -> str | None` — lê `gemini:antigravity` via `ctypes` `CredReadW` (`win32`), `security find-generic-password -s gemini -a antigravity -w` (`darwin`) ou `secret-tool lookup service gemini username antigravity` (`linux`), retornando `None` se a ferramenta/entrada não existir.
  - `collect_all_quotas(skip_network: bool = False) -> dict` — retorna `{"collectedAt": ISO8601_UTC, "platform": sys.platform, "providers": {"claude": ..., "codex": ..., "agy": ..., "opencode": ...}}`
  - Execução direta (`python3 orca-superpowers-orchestration-auto/scripts/get_quotas.py`) imprime JSON UTF-8 válido em stdout e sai com código `0`.

- [ ] **Step 1: Escrever os testes unitários que falham em `tests/test_orchestration_auto.py`**

Criar `tests/test_orchestration_auto.py` usando `unittest` + `importlib.util` (carregando `get_quotas.py` via `pathlib.Path(__file__).resolve().parents[1]`) com os casos offline:
1. `test_get_quotas_exists_and_compiles`: verifica existência de `orca-superpowers-orchestration-auto/scripts/get_quotas.py` e compilação limpa via `compile(source, path, "exec")`.
2. `test_claude_usage_legacy_and_scoped_limits`:
   - Caso A: `five_hour=15.0`, `seven_day=30.0`, `seven_day_opus=None`, `limits` contendo `weekly_scoped` `Opus` (40%, `surface: None`), `Fable` (25%, `surface: None`) e `Fable` (70%, `surface: {"id": "cli"}`) → asserta `windows["5h"] == 15.0`, `windows["week"] == 30.0`, `windows["opus"] == 40.0`, `windows["fable"] == 25.0`, `worst == "opus"`, `used == 40`, `rateLimited is False`.
   - Caso B: `seven_day_opus={"utilization": 12.0, "resets_at": "2026-09-24T01:59:59Z"}` e `limits` com `Opus=40` → asserta `windows["opus"] == 12.0`.
3. `test_codex_usage_standard_and_pro_lite_swap`:
   - Caso A (padrão): `primary_window` (`used_percent=12`, `limit_window_seconds=18000`, `reset_at=1700003600`), `secondary_window` (`used_percent=44.5`, `limit_window_seconds=604800`, `reset_at=1700475600`), `limit_reached=True`, `plan_type="plus"` → asserta `windows["5h"] == 12.0`, `windows["week"] == 44.5`, `worst == "week"`, `used == 44` ou `45` (usar `int(round(44.5))` ou `math.floor(x + 0.5)` documentado de forma consistente!), `rateLimited is True`, `plan == "plus"`.
   - Caso B (Pro Lite semanal em `primary_window`): `primary_window` (`used_percent=92`, `limit_window_seconds=604800`), `secondary_window=None`, `limit_reached=False` → asserta `windows["5h"] == 0.0`, `windows["week"] == 92.0`, `worst == "week"`, `used == 92`.
4. `test_antigravity_usage_buckets_and_rate_limit`:
   - Caso A: 2 modelos Gemini com `remainingFraction=0.25` e mesmo `resetTime` + 1 Claude com `remainingFraction=0.8` → asserta `len(buckets) == 2`, `buckets[0]["label"] == "Gemini"`, `buckets[0]["usedPercent"] == 75.0`, `len(buckets[0]["models"]) == 2`, `worst == "Gemini"`, `used == 75`, `windows["Gemini"] == 75.0`, `windows["short"] == 75.0`, `rateLimited is False`.
   - Caso B: `remainingFraction=0.0005` → asserta `used == 100`, `rateLimited is True`.
5. `test_unavailable_and_missing_keyring_never_critical`:
   - `unavailable_fitness("unavailable", "no_quota_api")` → asserta `status == "unavailable"`, `rateLimited is False`, `used is None`, `windows == {}`.
   - `discover_antigravity_token(platform_name="linux", runner=lambda *a, **kw: (_ for _ in ()).throw(FileNotFoundError()))` → retorna `None` sem lançar exceção.
   - `discover_antigravity_token(platform_name="darwin", runner=lambda *a, **kw: SimpleNamespace(returncode=44, stdout=""))` → retorna `None` sem lançar exceção.
   - `discover_antigravity_token(platform_name="darwin", runner=lambda *a, **kw: SimpleNamespace(returncode=0, stdout='{"token":{"access_token":"tok-test"}}'))` → retorna `"tok-test"`.
6. `test_script_security_endpoints_and_skip_network`:
   - Verifica no texto-fonte de `get_quotas.py`: presença das 3 URLs (`https://api.anthropic.com/api/oauth/usage`, `https://chatgpt.com/backend-api/wham/usage`, `https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`), `antigravity` no `User-Agent`, `Path.home()`, `shutil.which`.
   - `collect_all_quotas(skip_network=True)` retorna JSON válido com os 4 provedores (`claude`, `codex`, `agy`, `opencode`), `opencode["status"] == "unavailable"`, e a string JSON serializada nunca contém `Bearer `, `access_token`, `accessToken` ou `refresh_token`.

- [ ] **Step 2: Rodar a suíte e confirmar que falha (RED)**

Run: `python3 -m unittest tests/test_orchestration_auto.py -v`
Expected: FAIL indicando que `orca-superpowers-orchestration-auto/scripts/get_quotas.py` não existe.

- [ ] **Step 3: Implementar `orca-superpowers-orchestration-auto/scripts/get_quotas.py`**

Implementar em Python 3 stdlib pura com as funções da seção `Interfaces` conforme Spec §5:
- **Claude:** lê `os.environ.get("CLAUDE_OAUTH_TOKEN")` → `Path.home() / ".claude" / ".credentials.json"` (3 tentativas × 80 ms, `claudeAiOauth.accessToken`) → macOS `security find-generic-password -s "Claude Code-credentials" -w` → `GET https://api.anthropic.com/api/oauth/usage` com `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20` (timeout 10 s) → `parse_claude_usage`.
- **Codex:** lê `(Path(os.environ["CODEX_HOME"]) if os.environ.get("CODEX_HOME") else Path.home() / ".codex") / "auth.json"` (`tokens.access_token`, opcional `tokens.account_id`) → `GET https://chatgpt.com/backend-api/wham/usage` com `Authorization`, `User-Agent: orca-quota-check/1.0` e opcional `ChatGPT-Account-Id` (timeout 10 s) → `parse_codex_usage` (incluindo swap `by_duration` quando `primary.window_minutes > 1440` e `secondary.window_minutes <= 1440`).
- **Antigravity (`agy`):** verifica `shutil.which("agy")` (ausente → `no_cli`), chama `discover_antigravity_token()` (`win32`: `ctypes.windll.advapi32.CredReadW("gemini:antigravity", 1, 0, ...)`; `darwin`: `security find-generic-password -s gemini -a antigravity -w`; `linux`: `secret-tool lookup service gemini username antigravity`; ausente → `no_auth`), envia `POST https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` com body `b"{}"`, `Content-Type: application/json` e `User-Agent: orca-quota-check/1.0 antigravity-usage`; em HTTP 401 roda `subprocess.run([agy_path, "models"], timeout=12, stdout=DEVNULL, stderr=DEVNULL)` uma única vez, relê o token e repete o `POST` uma vez → `parse_antigravity_usage`.
- **OpenCode:** sempre `unavailable_fitness("unavailable", "no_quota_api")`.
- **Arredondamento determinístico:** usar `int(math.floor(val + 0.5))` em `used` (alinha com `.round()` do Rust/JS e evita round-half-to-even).
- **Tratamento de erro seguro:** todo `except` devolve `unavailable_fitness` com categoria limpa (`no_auth`, `http_<code>`, `timeout`, `unavailable`, `parse_error`), nunca expondo tokens nem headers.

- [ ] **Step 4: Rodar os testes unitários + smoke test real (GREEN)**

Run:
```bash
python3 -m unittest tests/test_orchestration_auto.py -v
python3 orca-superpowers-orchestration-auto/scripts/get_quotas.py
```
Expected: todos os testes da Task 1 PASS; execução direta imprime JSON válido com `collectedAt`, `platform` e os 4 provedores (`claude`, `codex`, `agy`, `opencode`), sem nenhum token na saída.

- [ ] **Step 5: Commit atômico da Task 1**

```bash
git add orca-superpowers-orchestration-auto/scripts/get_quotas.py tests/test_orchestration_auto.py
git commit -m "feat: adiciona coletor Python cross-platform de cotas reais e testes unitarios"
```

---

### Task 2: Skill Principal (`orca-superpowers-orchestration-auto/SKILL.md`)

**Files:**
- Modify: `tests/test_orchestration_auto.py` (adicionar bloco de validações estruturais, determinísticas, cross-platform e de presets JSON)
- Create: `orca-superpowers-orchestration-auto/SKILL.md`

**Interfaces:**
- Consumes: `orca-superpowers-orchestration-auto/scripts/get_quotas.py` (comando `python3 <caminho-da-skill>/scripts/get_quotas.py` e contrato JSON documentados na skill).
- Produces: `orca-superpowers-orchestration-auto/SKILL.md` com frontmatter YAML (`name: orca-superpowers-orchestration-auto`), todas as seções operacionais portáteis (Windows, macOS e Linux) e bloco ` ```json ` parseável dos 3 presets (`economy`, `balanced`, `performance`).

- [ ] **Step 1: Adicionar testes de verificação de `SKILL.md` em `tests/test_orchestration_auto.py`**

Estender `tests/test_orchestration_auto.py` com os seguintes testes:
1. `test_skill_frontmatter`: `orca-superpowers-orchestration-auto/SKILL.md` existe, começa com `---`, contém `name: orca-superpowers-orchestration-auto` e `description: Use when `.
2. `test_skill_required_sections_and_contract`: asserta presença (case-insensitive, UTF-8) de:
   - Seções: `## Overview`, `## Agentes Suportados`, `## Quando Usar`, `## Medição Real de Cotas`, `## Motor Determinístico de Roteamento`, `## Presets de Roteamento`, `## Protocolo Operacional`, `## Trilha de Auditoria`, `## Comandos Úteis`, `## Red Flags`.
   - Contrato Orca TUI: `--worktree active`, `--focus`, `--for tui-idle`, `orca terminal show --json`, `ETAPA planner CONCLUÍDA`, `ETAPA executor CONCLUÍDA`, `ETAPA reviewer CONCLUÍDA`, proibição explícita de `-p`/`exec`/`run`.
   - Zero pergunta de alocação + gate único no Passo 2.
   - Roteamento Alethe: os 6 `kind` (`research`, `code`, `review`, `command`, `docs`, `scrap`), os 3 `effortClass` (`light`, `standard`, `deep`), `criticalThreshold`, `allowOpusOnDeep`, `onAllCritical`, `onBothCritical`, `ask`, `run-cheapest`, `block`, `fallback`, guarda `readOnly`, regra de que provedor sem leitura não é crítico.
   - Fontes de cota e cross-platform: menciona `https://api.anthropic.com/api/oauth/usage`, `five_hour`, `seven_day`, `seven_day_opus`, `https://chatgpt.com/backend-api/wham/usage`, `used_percent`, `rate_limited`, `https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`, `gemini:antigravity`, `antigravity` no `User-Agent`, `get_quotas.py`, `python3`, `~/.claude`, `~/.codex`, `~/.gemini`, **Windows**, **macOS**, **Linux**, explicitação de que onde o keyring/SO não fornecer leitura o provedor não tem leitura e não é crítico, e `opencode` sem leitura de cota.
   - Trilha de auditoria: menciona `rule:`, `fallback:`, cotas lidas e inclusão da seção `## Trilha de Auditoria de Roteamento` no relatório de review.
3. `test_skill_no_windows_only_paths_or_commands`: asserta que `SKILL.md` **NÃO** contém `%TEMP%`, `%APPDATA%`, `AppData\\Local`, `$env:USERPROFILE` nem `powershell -NoProfile -ExecutionPolicy Bypass`.
4. `test_skill_json_blocks_and_preset_integrity`: extrai todos os blocos ` ```json ... ``` ` de `SKILL.md` e verifica:
   - Todos passam em `json.loads` sem erro.
   - Existe bloco contendo os 3 presets (`economy`, `balanced`, `performance`).
   - Em cada preset:
     - `len(roles) >= 3` e `len(rules) >= 3`.
     - Todo `rule["role"]` existe na lista `roles` do mesmo preset.
     - Todo `role.get("fallback")` (quando não nulo) existe em `roles`, tem `fallback != role["name"]`, e se `role["readOnly"] is True`, o papel de fallback também tem `readOnly is True`.
     - Todo `role["agent"]` pertence a `{"claude", "codex", "agy", "opencode"}`.
     - Todo `role["model"]` não nulo pertence à lista de modelos permitidos pela Spec §4.
     - Todo `rule["kinds"]` usa somente `{"research", "code", "review", "command", "docs", "scrap"}` e todo `rule["efforts"]` usa somente `{"light", "standard", "deep"}`.

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `python3 -m unittest tests/test_orchestration_auto.py -v`
Expected: FAIL indicando que `orca-superpowers-orchestration-auto/SKILL.md` não existe (enquanto testes da Task 1 continuam PASS).

- [ ] **Step 3: Criar `orca-superpowers-orchestration-auto/SKILL.md`**

Redigir `orca-superpowers-orchestration-auto/SKILL.md` em português (frontmatter em inglês), seguindo fielmente o tom, diagramas ASCII, tabelas e clareza de `orca-superpowers-orchestrator/SKILL.md`, cobrindo integralmente as Seções 3, 4, 5, 6 e 7 da Spec revisada (cross-platform Windows/macOS/Linux):
- Frontmatter YAML (`name: orca-superpowers-orchestration-auto`, `description: Use when ...`).
- `## Overview` + diagrama ASCII do ciclo completo (Passo 0 automático com coleta de cotas → Planner → Passo 2 Gate humano único → Executor → Reviewer → Consolidação + Trilha de Auditoria).
- `## Agentes Suportados e Matriz de Invocação` (tabela dos 4 CLIs com flags reais `--model`, `--effort`, `-m`, `-c model_reasoning_effort=...`, modelos reais, descoberta portátil de binários via `command -v` em macOS/Linux e `Get-Command` em Windows, e padrão `create --focus` → `wait --for tui-idle` → `send`).
- `## Quando Usar` / `### Quando NÃO Usar` (contrastando explicitamente com `orca-superpowers-orchestrator` manual).
- `## Medição Real de Cotas (Windows, macOS e Linux)`:
  - Invocação única portátil: `python3 <caminho-da-skill>/scripts/get_quotas.py`.
  - Matriz de suporte por SO (Windows / macOS / Linux) para `claude`, `codex`, `agy` e `opencode`.
  - Documentação de cada fonte com caminhos portáteis (`~/.claude/.credentials.json`, `$CODEX_HOME/auth.json` ou `~/.codex/auth.json`, `~/.gemini`), endpoints exatos, header `antigravity` obrigatório no `User-Agent`, refresh via `agy models` em 401, e regra explícita de que onde um SO não disponibilizar leitura (ex.: `agy` em Linux sem `secret-tool`/Secret Service, ou `opencode` em qualquer SO) o provedor **não tem leitura e nunca é crítico**, mais invariante de segurança (nunca imprimir tokens).
- `## Motor Determinístico de Roteamento`:
  - `kind` (`research | code | review | command | docs | scrap`) e `effortClass` (`light | standard | deep`) + heurística objetiva + mapeamento das 3 etapas.
  - Modelo `Role`, `QuotaGate`, `RoutingRule`, `RoutingSettings` (`preset: "balanced"`, `criticalThreshold: 80`, `allowOpusOnDeep: true`, `onAllCritical` / `onBothCritical`: `"run-cheapest" | "ask" | "block"`).
  - Algoritmo determinístico em 4 etapas: avaliação top-down → fallback de 1 nível por cota com guarda `readOnly` → independência de vendor no Reviewer → política `onAllCritical` quando todos os provedores medidos (`status == "ready"`) são críticos.
- `## Presets de Roteamento`: bloco ` ```json ` único e válido contendo `economy`, `balanced` (default) e `performance` conforme Spec §6.4.
- `## Protocolo Operacional do Orquestrador`: Passos 0 a 5 completos (Passo 0 sem perguntar agente/modelo, Passo 2 único gate humano, revalidação de cota nos Passos 3 e 4, templates de prompt com aviso `ETAPA <papel> CONCLUÍDA` e bloco de auditoria injetado no Reviewer).
- `## Trilha de Auditoria`: formato padronizado de tabela e exemplos concretos (`rule:bal-deep-opus`, `fallback: builder → codex-builder por cota`, cotas lidas).
- `## Comandos Úteis do Orca ADE` (portáteis).
- `## Red Flags - Erros Críticos`.

- [ ] **Step 4: Rodar a suíte e confirmar tudo verde (GREEN)**

Run: `python3 -m unittest tests/test_orchestration_auto.py -v`
Expected: PASS em todos os testes das Tasks 1 e 2.

- [ ] **Step 5: Commit atômico da Task 2**

```bash
git add orca-superpowers-orchestration-auto/SKILL.md tests/test_orchestration_auto.py
git commit -m "feat: adiciona SKILL.md cross-platform da skill orca-superpowers-orchestration-auto"
```

---

### Task 3: `README.md` da Skill Nova + Atualização Cross-Platform do `README.md` da Raiz (5 Destinos)

**Files:**
- Modify: `tests/test_orchestration_auto.py` (adicionar bloco de validações de ambos os `README.md`)
- Create: `orca-superpowers-orchestration-auto/README.md`
- Modify: `README.md:5-26`

**Interfaces:**
- Consumes: `orca-superpowers-orchestration-auto/SKILL.md` e `orca-superpowers-orchestration-auto/scripts/get_quotas.py`.
- Produces: documentação de entrada da skill (portátil) e índice/instalador raiz atualizado para as 4 skills e 5 destinos em **macOS/Linux (POSIX)** e **Windows (PowerShell)**.

- [ ] **Step 1: Adicionar testes de `README.md` (skill e raiz) em `tests/test_orchestration_auto.py`**

Estender `tests/test_orchestration_auto.py` com:
1. `test_skill_readme`: verifica existência de `orca-superpowers-orchestration-auto/README.md`, referência a `[SKILL.md](SKILL.md)` e `scripts/get_quotas.py`, seções `## Conteúdo`, `## Visão Geral`, `## Garantias`, menção a Windows/macOS/Linux, escolha automática sem perguntar, TUI obrigatória, gate único no Passo 2, e ausência de `%TEMP%`, `%APPDATA%`, `AppData\\Local`, `$env:USERPROFILE` ou `powershell -NoProfile -ExecutionPolicy Bypass`.
2. `test_root_readme_updated_cross_platform`: lê `README.md` na raiz e asserta:
   - Linha na tabela `## Skills` com `[orca-superpowers-orchestration-auto](orca-superpowers-orchestration-auto/SKILL.md)`.
   - Bloco de instalação **macOS / Linux** (POSIX) contendo as 4 skills e os **5 destinos**:
     - `$HOME/.claude/skills/$skill`
     - `$HOME/.gemini/config/plugins/superpowers/skills/$skill`
     - `$HOME/.codex/skills/$skill`
     - `$HOME/.agents/skills/$skill`
     - `$HOME/.config/opencode/skills/$skill`
   - Bloco de instalação **Windows (PowerShell)** contendo as 4 skills e os **5 destinos** (`$env:USERPROFILE\.claude\skills\$skill`, `\.gemini\config\plugins\superpowers\skills\$skill`, `\.codex\skills\$skill`, `\.agents\skills\$skill`, `\.config\opencode\skills\$skill`).
3. `test_all_python_files_compile`: valida sintaxe via `compile()` em todos os `.py` sob `orca-superpowers-orchestration-auto/` e `tests/`.

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `python3 -m unittest tests/test_orchestration_auto.py -v`
Expected: FAIL nos 2 novos testes de README (enquanto Tasks 1 e 2 continuam PASS).

- [ ] **Step 3: Criar `orca-superpowers-orchestration-auto/README.md` e atualizar `README.md` da raiz**

- Criar `orca-superpowers-orchestration-auto/README.md` no estilo conciso de `orca-superpowers-review-loop/README.md` e `orca-superpowers-merge/README.md` (`# Skill Orquestração Automática (Orca Superpowers Orchestration Auto)`, `## Conteúdo` listando `SKILL.md` e `scripts/get_quotas.py`, `## Visão Geral` com Passos 0–5, `## Garantias` incluindo compatibilidade Windows/macOS/Linux).
- Atualizar `README.md` da raiz:
  - Inserir a linha de `orca-superpowers-orchestration-auto` na tabela `## Skills`.
  - Em `## Instalação`, disponibilizar o loop das 4 skills para os **5 destinos** em duas subseções: **macOS / Linux (bash/zsh)** usando `$HOME/...` e **Windows (PowerShell)** usando `$env:USERPROFILE\...`.

- [ ] **Step 4: Rodar verificação completa (GREEN)**

Run:
```bash
python3 -m unittest tests/test_orchestration_auto.py -v
python3 orca-superpowers-orchestration-auto/scripts/get_quotas.py
git status -sb
```
Expected: 100% dos testes PASS (exit code 0), `get_quotas.py` devolve JSON válido sem segredos, e apenas os arquivos esperados estão criados/modificados.

- [ ] **Step 5: Commit atômico da Task 3**

```bash
git add orca-superpowers-orchestration-auto/README.md README.md tests/test_orchestration_auto.py
git commit -m "docs: adiciona README da skill orchestration-auto e atualiza instalacao nos 5 destinos"
```
