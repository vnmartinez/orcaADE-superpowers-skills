# `orca-superpowers-orchestration-auto` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar a skill `orca-superpowers-orchestration-auto` no padrão do repositório `orcaADE-superpowers-skills`, com coleta real de cotas em PowerShell 5.1+ (Windows-first), motor determinístico de roteamento inspirado no Alethe, trilha de auditoria e atualização do `README.md` da raiz para os 5 destinos de instalação.

**Architecture:** Um script PowerShell 5.1+ *dot-sourceable* (`orca-superpowers-orchestration-auto/scripts/get-quotas.ps1`) expõe parsers puros e coleta real de cota para `claude`, `codex`, `agy` e `opencode` em JSON normalizado. A skill (`SKILL.md` + `README.md`) documenta o protocolo completo no Orca ADE (TUI obrigatória, zero perguntas de alocação, gate humano único no Passo 2, regras determinísticas, presets JSON e trilha de auditoria). Uma suíte TDD única (`tests/Test-OrchestrationAuto.ps1`) valida os parsers offline, compatibilidade sintática com PS 5.1, integridade dos presets JSON e conformidade de todas as seções e destinos de instalação.

**Tech Stack:** Markdown (skills Orca ADE), Windows PowerShell 5.1+ (`powershell -NoProfile -ExecutionPolicy Bypass -File`), Win32 `advapi32.dll!CredRead` via `Add-Type`, JSON, Orca CLI.

**Spec:** `docs/superpowers/specs/2026-11-24-orca-superpowers-orchestration-auto-design.md`

## Global Constraints

- Compatibilidade obrigatória com **Windows PowerShell 5.1** (proibido `??`, `?:` ternário ou `ConvertFrom-Json -AsHashtable`; ler arquivos UTF-8 com `-Encoding UTF8`).
- Todo comando PowerShell documentado ou de teste roda com `powershell -NoProfile -ExecutionPolicy Bypass -File <caminho>`.
- Frontmatter YAML de `SKILL.md` contém `name: orca-superpowers-orchestration-auto` e `description: Use when ...` em inglês; corpo de `SKILL.md` e `README.md` em português.
- Protocolo Orca ADE idêntico às demais skills: `--worktree active`, TUI interativa obrigatória (`--focus` + `wait --for tui-idle`), zero fallback para `-p`/`--print`/`exec`/`run`, `<ORQ_HANDLE>` via `orca terminal show --json` antes do Passo 1, conclusão somente por `ETAPA <planner|executor|reviewer> CONCLUÍDA`.
- **Nunca** perguntar ao usuário qual agente/modelo executa cada papel; gate humano único no Passo 2 (com `onAllCritical` configurável em `run-cheapest` [default] | `ask` | `block`).
- **Invariante de segurança:** nenhum comando, script ou log pode imprimir tokens (`accessToken`, `access_token`, `refresh_token`, `Authorization`, `CLAUDE_OAUTH_TOKEN`).
- Modelos nos presets e exemplos restritos aos disponíveis na máquina: `gemini-4-neon-{low,medium,high,xhigh}`, `gemini-4-carbon-{low,medium,high}`, `gemini-4-argon-{low,medium,high}`, `gemini-4-hydrogen-{low,medium,high,xhigh}`, `gemini-pro-orchestrator[-neon|-argon]`, `gemini-3.8-flash-{low,medium,high}`, `claude-opus-5-5[-low|-medium|-high]`, `claude-sonnet-5-5[-low|-medium|-high]`, `haiku`, `gpt-oss-120b-medium`, `codex` (`null`/default `config.toml`).
- Loop de instalação no `README.md` da raiz cobre exatamente os **5 destinos**: `\.claude\skills`, `\.gemini\config\plugins\superpowers\skills`, `\.codex\skills`, `\.agents\skills`, `\.config\opencode\skills`.

## Review Focus

- **Claude `seven_day_opus` nulo com `limits[]`:** quando `seven_day_opus` é `null`, `ConvertFrom-ClaudeUsage` deve preencher `windows.opus` a partir de `limits[]` (`kind == "weekly_scoped"`, `scope.surface == null`, `display_name == "Opus"`), ignorando limites com `scope.surface` preenchido (pinned in Task 1).
- **Codex plano somente semanal (Pro Lite):** quando `primary_window` traz janela > 1440 min (ex.: 604800 s) e `secondary_window` é nulo/curto, `ConvertFrom-CodexUsage` deve trocar para `windows.week` e manter `windows["5h"] = 0` (pinned in Task 1).
- **Antigravity sem `antigravity` no `User-Agent` ou sem credencial:** `get-quotas.ps1` deve enviar `User-Agent` contendo `antigravity` (sem ele o endpoint responde HTTP 403), tentar refresh único via `agy models` em HTTP 401 e degradar para `status: "no_auth"|"unavailable"` com `rateLimited: false`, `used: null`, nunca imprimindo tokens (pinned in Task 1).
- **Integridade de presets JSON e guarda `readOnly`:** em `SKILL.md`, todo `role` referenciado em `rules` deve existir em `roles`, e nenhum papel com `readOnly: true` pode apontar `fallback` para papel com `readOnly: false` ou para si mesmo (pinned in Task 2).
- **Compatibilidade sintática PowerShell 5.1:** tanto `get-quotas.ps1` quanto `Test-OrchestrationAuto.ps1` devem compilar com zero erros no parser AST do PowerShell 5.1 (`[System.Management.Automation.Language.Parser]::ParseFile`) e validar saída real de `get-quotas.ps1` sem vazar credenciais (pinned in Task 1 e revalidado na Task 3).

---

### Task 1: Coletor de Cotas Reexecutável (`scripts/get-quotas.ps1`) + Suíte Base TDD

**Files:**
- Create: `tests/Test-OrchestrationAuto.ps1`
- Create: `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1`

**Interfaces:**
- Produces (dot-sourceable em `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1` quando invocado com `. "<path>"`, sem rodar coleta de rede se `$MyInvocation.InvocationName -eq '.'`):
  - `New-UnavailableFitness([string]$Status, [string]$Reason) -> [ordered]@{ status; reason; worst=$null; used=$null; resetsAt=$null; rateLimited=$false; windows=@{} }`
  - `ConvertFrom-ClaudeUsage([psobject]$Body) -> [ordered]@{ status='ready'; worst; used; resetsAt; rateLimited=$false; windows }`
  - `ConvertFrom-CodexUsage([psobject]$Body) -> [ordered]@{ status='ready'; plan; worst; used; resetsAt; rateLimited; windows }`
  - `ConvertFrom-AntigravityUsage([psobject]$Body) -> [ordered]@{ status='ready'; worst; used; resetsAt; rateLimited; windows; buckets }`
  - `Get-AllProviderQuotas([switch]$SkipNetwork) -> [ordered]@{ collectedAt; providers=@{ claude; codex; agy; opencode } }`
  - Execução direta (`powershell -NoProfile -ExecutionPolicy Bypass -File orca-superpowers-orchestration-auto/scripts/get-quotas.ps1`) imprime JSON UTF-8 válido com `ConvertTo-Json -Depth 8` e exit code `0`.

- [ ] **Step 1: Escrever os testes unitários que falham em `tests/Test-OrchestrationAuto.ps1`**

Criar `tests/Test-OrchestrationAuto.ps1` com helpers `Assert-True`, `Assert-Equal` e o bloco de testes da Task 1 (sem depender de rede):
1. `Test-GetQuotasExistsAndParsesPs51`: verifica existência de `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1` e zero erros de parse no `[System.Management.Automation.Language.Parser]::ParseFile`.
2. `Test-ClaudeUsageLegacyAndScopedLimits`:
   - Caso A: `five_hour=15`, `seven_day=30`, `seven_day_opus=null`, `limits` contendo `weekly_scoped` `Opus` (40%, `surface: null`), `Fable` (25%, `surface: null`) e `Fable` (70%, `surface: { id: "cli" }`) → asserta `windows["5h"] -eq 15`, `windows["week"] -eq 30`, `windows["opus"] -eq 40`, `windows["fable"] -eq 25`, `worst -eq "opus"`, `used -eq 40`, `rateLimited -eq $false`.
   - Caso B: `seven_day_opus=12` e `limits[]` com `Opus=40` → asserta que `seven_day_opus` legado vence (`windows["opus"] -eq 12`).
3. `Test-CodexUsageStandardAndProLiteSwap`:
   - Caso A (padrão): `primary_window` (`used_percent=12`, `limit_window_seconds=18000`, `reset_at=1700003600`), `secondary_window` (`used_percent=44.5`, `limit_window_seconds=604800`, `reset_at=1700475600`), `limit_reached=$true`, `plan_type="plus"` → asserta `windows["5h"] -eq 12`, `windows["week"] -eq 44.5`, `worst -eq "week"`, `used -eq 45`, `rateLimited -eq $true`, `plan -eq "plus"`.
   - Caso B (Pro Lite semanal em `primary_window`): `primary_window` (`used_percent=92`, `limit_window_seconds=604800`), `secondary_window=$null`, `limit_reached=$false` → asserta `windows["5h"] -eq 0`, `windows["week"] -eq 92`, `worst -eq "week"`, `used -eq 92`.
4. `Test-AntigravityUsageBucketsAndRateLimit`:
   - Caso A: 2 modelos Gemini com `remainingFraction=0.25` e mesmo `resetTime` + 1 Claude com `remainingFraction=0.8` → asserta `buckets.Count -eq 2`, `buckets[0].label -eq "Gemini"`, `buckets[0].usedPercent -eq 75`, `buckets[0].models.Count -eq 2`, `worst -eq "Gemini"`, `used -eq 75`, `windows["Gemini"] -eq 75`, `windows["short"] -eq 75`, `rateLimited -eq $false`.
   - Caso B: `remainingFraction=0.0005` → asserta `used -eq 100`, `rateLimited -eq $true`.
5. `Test-UnavailableProviderNeverCritical`: `New-UnavailableFitness -Status "unavailable" -Reason "no_quota_api"` → asserta `status -eq "unavailable"`, `rateLimited -eq $false`, `$null -eq $res.used`, `$res.windows.Count -eq 0`.
6. `Test-ScriptSecurityAndUserAgentContract`: verifica no texto-fonte de `get-quotas.ps1` que:
   - o header `User-Agent` da chamada Antigravity contém `antigravity`;
   - o endpoint `daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`, `api.anthropic.com/api/oauth/usage` e `chatgpt.com/backend-api/wham/usage` estão presentes;
   - `Get-AllProviderQuotas -SkipNetwork` retorna JSON válido com os 4 provedores (`claude`, `codex`, `agy`, `opencode`) e `opencode.status -eq "unavailable"`;
   - a saída JSON nunca contém `Bearer `, `access_token`, `accessToken` ou `refresh_token`.

- [ ] **Step 2: Rodar a suíte e confirmar que falha (RED)**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-OrchestrationAuto.ps1`
Expected: FAIL indicando que `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1` não existe.

- [ ] **Step 3: Implementar `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1`**

Implementar em PowerShell 5.1 puro (sem `??`, `?:`, `-AsHashtable`) com as funções da seção `Interfaces` e as 3 coletas reais conforme Spec §5:
- **Claude:** lê `$env:CLAUDE_OAUTH_TOKEN` ou `$env:USERPROFILE\.claude\.credentials.json` (`claudeAiOauth.accessToken`, 3 tentativas × 80 ms) → `GET https://api.anthropic.com/api/oauth/usage` com `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20` (timeout 10 s) → `ConvertFrom-ClaudeUsage`.
- **Codex:** lê `$env:CODEX_HOME\auth.json` ou `$env:USERPROFILE\.codex\auth.json` (`tokens.access_token`, opcional `tokens.account_id`) → `GET https://chatgpt.com/backend-api/wham/usage` com `Authorization`, `User-Agent: orca-quota-check/1.0` e opcional `ChatGPT-Account-Id` (timeout 10 s) → `ConvertFrom-CodexUsage` (incluindo swap `by_duration` para janela > 1440 min).
- **Antigravity (`agy`):** verifica `Get-Command agy` (senão `no_cli`), lê Windows Credential Manager alvo literal `"gemini:antigravity"` via `advapi32.dll!CredRead` (`CRED_TYPE_GENERIC = 1`) em C# `Add-Type` (guarded por `if (-not ("OrcaWinCred" -as [type]))`), extrai `token.access_token`, envia `POST https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` com body `{}` e `User-Agent: orca-quota-check/1.0 antigravity-usage`; em HTTP 401 executa `agy models` (timeout 12 s) uma vez, relê a credencial e repete o `POST` uma vez → `ConvertFrom-AntigravityUsage`.
- **OpenCode:** sempre `New-UnavailableFitness -Status "unavailable" -Reason "no_quota_api"`.
- **Tratamento de erro seguro:** todo `catch` converte para `New-UnavailableFitness` usando apenas categoria (`no_auth`, `http_<codigo>`, `unavailable`, `parse_error`), nunca expondo `$token` nem `$_.Exception` com headers.
- **Guarda de execução direta:** só chama `Get-AllProviderQuotas | ConvertTo-Json -Depth 8` quando `$MyInvocation.InvocationName -ne '.'`.

- [ ] **Step 4: Rodar os testes unitários + smoke test real na máquina (GREEN)**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-OrchestrationAuto.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File orca-superpowers-orchestration-auto/scripts/get-quotas.ps1 | ConvertFrom-Json | ConvertTo-Json -Depth 4
```
Expected: todos os testes da Task 1 PASS; smoke test imprime JSON válido com os 4 provedores (`claude`, `codex`, `agy`, `opencode`), sem nenhum token na saída.

- [ ] **Step 5: Commit atômico da Task 1**

```bash
git add orca-superpowers-orchestration-auto/scripts/get-quotas.ps1 tests/Test-OrchestrationAuto.ps1
git commit -m "feat: adiciona coletor PowerShell de cotas reais e testes unitarios"
```

---

### Task 2: Skill Principal (`orca-superpowers-orchestration-auto/SKILL.md`)

**Files:**
- Modify: `tests/Test-OrchestrationAuto.ps1` (adicionar bloco de validações estruturais, determinísticas e de presets JSON)
- Create: `orca-superpowers-orchestration-auto/SKILL.md`

**Interfaces:**
- Consumes: `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1` (caminho e contrato JSON de saída documentados na skill).
- Produces: `orca-superpowers-orchestration-auto/SKILL.md` com frontmatter YAML (`name: orca-superpowers-orchestration-auto`), todas as seções operacionais e blocos ` ```json ` parseáveis dos 3 presets (`economy`, `balanced`, `performance`).

- [ ] **Step 1: Adicionar testes de verificação de `SKILL.md` em `tests/Test-OrchestrationAuto.ps1`**

Estender `tests/Test-OrchestrationAuto.ps1` com os seguintes testes:
1. `Test-SkillFrontmatter`: `orca-superpowers-orchestration-auto/SKILL.md` existe, começa com `---`, contém `name: orca-superpowers-orchestration-auto` e `description: Use when `.
2. `Test-SkillRequiredSectionsAndContract`: asserta presença (regex case-insensitive sobre conteúdo UTF-8) de:
   - Títulos/seções: `## Overview`, `## Agentes Suportados`, `## Quando Usar`, `## Medição Real de Cotas`, `## Motor Determinístico de Roteamento`, `## Presets de Roteamento`, `## Protocolo Operacional`, `## Trilha de Auditoria`, `## Comandos Úteis`, `## Red Flags`.
   - Contrato Orca TUI: `--worktree active`, `--focus`, `--for tui-idle`, `orca terminal show --json`, `ETAPA <planner|executor|reviewer> CONCLUÍDA` (ou padrão `ETAPA planner CONCLUÍDA` / `executor` / `reviewer`), proibição explícita de `-p`/`exec`/`run`.
   - Zero pergunta de alocação + gate único: contém proibição explícita de perguntar agente/modelo ao usuário e gate obrigatório no Passo 2 (`Passo 2`).
   - Roteamento Alethe: contém todos os 6 `kind` (`research`, `code`, `review`, `command`, `docs`, `scrap`), os 3 `effortClass` (`light`, `standard`, `deep`), `criticalThreshold`, `allowOpusOnDeep`, `onAllCritical`, `ask`, `run-cheapest`, `block`, `fallback` (um nível), guarda `readOnly`, e regra de que provedor sem leitura não é crítico.
   - Fontes de cota: menciona `https://api.anthropic.com/api/oauth/usage`, `five_hour`, `seven_day`, `seven_day_opus`, `https://chatgpt.com/backend-api/wham/usage`, `used_percent`, `rate_limited`, `https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`, `gemini:antigravity`, `antigravity` no `User-Agent`, `get-quotas.ps1`, `-NoProfile -ExecutionPolicy Bypass -File`, e `opencode` sem leitura de cota.
   - Trilha de auditoria: menciona registro de `rule:`, `fallback:`, cotas lidas e inclusão da seção `## Trilha de Auditoria de Roteamento` no relatório de review.
3. `Test-SkillJsonBlocksAndPresetIntegrity`: extrai todos os blocos ` ```json ... ``` ` de `SKILL.md` e verifica:
   - Todos passam em `ConvertFrom-Json` sem erro.
   - Existe bloco contendo os 3 presets (`economy`, `balanced`, `performance`).
   - Em cada preset:
     - `roles.Count -ge 3` e `rules.Count -ge 3`.
     - Todo `rule.role` existe na lista `roles` do mesmo preset.
     - Todo `role.fallback` (quando não nulo) existe em `roles`, tem `fallback -ne role.name`, e se `role.readOnly -eq $true`, o papel de fallback também tem `readOnly -eq $true`.
     - Todo `role.agent` pertence a `@('claude','codex','agy','opencode')`.
     - Todo `role.model` não nulo pertence à lista de modelos reais permitidos pela Spec §4 (`gemini-4-neon-*`, `gemini-4-carbon-*`, `gemini-4-argon-*`, `gemini-4-hydrogen-*`, `gemini-pro-orchestrator*`, `gemini-3.8-flash-*`, `claude-opus-5-5*`, `claude-sonnet-5-5*`, `haiku`, `gpt-oss-120b-medium`).
     - Todo `rule.kinds` só usa valores de `@('research','code','review','command','docs','scrap')` e todo `rule.efforts` só usa valores de `@('light','standard','deep')`.

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-OrchestrationAuto.ps1`
Expected: FAIL indicando que `orca-superpowers-orchestration-auto/SKILL.md` não existe (enquanto testes da Task 1 continuam PASS).

- [ ] **Step 3: Criar `orca-superpowers-orchestration-auto/SKILL.md`**

Redigir `orca-superpowers-orchestration-auto/SKILL.md` em português (frontmatter em inglês), seguindo fielmente o tom, diagramas ASCII, tabelas e clareza de `orca-superpowers-orchestrator/SKILL.md`, cobrindo integralmente as Seções 3, 4, 5, 6 e 7 da Spec:
- Frontmatter YAML (`name: orca-superpowers-orchestration-auto`, `description: Use when ...`).
- `## Overview` + diagrama ASCII do ciclo completo (Passo 0 automático com coleta de cotas → Planner → Passo 2 Gate humano único → Executor → Reviewer → Consolidação + Trilha de Auditoria).
- `## Agentes Suportados e Matriz de Invocação` (tabela dos 4 CLIs com flags reais verificadas `--model`, `--effort`, `-m`, `-c model_reasoning_effort=...`, modelos reais da máquina e padrão `create --focus` → `wait --for tui-idle` → `send`).
- `## Quando Usar` / `### Quando NÃO Usar` (contrastando explicitamente com `orca-superpowers-orchestrator` manual).
- `## Medição Real de Cotas (Windows-first)`:
  - Invocação direta de `powershell -NoProfile -ExecutionPolicy Bypass -File "<CAMINHO_DA_SKILL>\scripts\get-quotas.ps1"`.
  - Documentação reexecutável por provedor: Claude (`GET https://api.anthropic.com/api/oauth/usage`, `five_hour`/`seven_day`/`seven_day_opus`/`limits[]`), Codex (`GET https://chatgpt.com/backend-api/wham/usage`, `primary`/`secondary` + swap `by_duration` + `rate_limited` + nota de fallback `codex app-server`), Antigravity (`POST https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`, Windows Credential Manager `gemini:antigravity`, `User-Agent` contendo `antigravity`, refresh via `agy models` em 401), e tabela explícita de provedores sem leitura (`opencode`, `no_auth`, `no_cli`, `unavailable`) + invariante de segurança (nunca imprimir tokens).
- `## Motor Determinístico de Roteamento`:
  - `kind` (`research | code | review | command | docs | scrap`) e `effortClass` (`light | standard | deep`) + tabela de heurística objetiva + mapeamento das 3 etapas.
  - Modelo `Role`, `QuotaGate`, `RoutingRule`, `RoutingSettings` (`preset: "balanced"`, `criticalThreshold: 80`, `allowOpusOnDeep: true`, `onAllCritical: "run-cheapest" | "ask" | "block"`).
  - Algoritmo determinístico em 4 etapas: avaliação de regras de cima para baixo (primeira habilitada que casar vence; janela sem leitura passa) → fallback de 1 nível por cota com guarda `readOnly` → independência de vendor no Reviewer → política `onAllCritical` quando todos os provedores medidos (`status == "ready"`) são críticos.
- `## Presets de Roteamento`: bloco ` ```json ` único e válido contendo `economy`, `balanced` (default) e `performance` conforme Spec §6.4 (todos com modelos reais e guarda `readOnly` satisfeita).
- `## Protocolo Operacional do Orquestrador`:
  - Passo 0 (resolver `<ORQ_HANDLE>`, rodar `get-quotas.ps1`, classificar e resolver papéis **sem perguntar ao usuário**).
  - Passo 1 (Planner + template de prompt + aviso `ETAPA planner CONCLUÍDA`).
  - Passo 2 (Gate obrigatório de aprovação humana do plano — única pergunta do fluxo normal — exibindo resumo + trilha prevista).
  - Passo 3 (Executor: revalidar cotas, abrir TUI, template `executing-plans` + TDD + checkboxes `[x]` + aviso `ETAPA executor CONCLUÍDA`).
  - Passo 4 (Reviewer: revalidar cotas, aplicar independência de vendor, abrir TUI, template `requesting-code-review` + `verification-before-completion` + injeção do bloco `## Trilha de Auditoria de Roteamento` para persistência no relatório).
  - Passo 5 (Consolidação + exibição da trilha de auditoria final).
- `## Trilha de Auditoria`: formato padronizado de tabela e exemplos concretos (`rule:bal-deep-opus`, `fallback: builder → codex-builder por cota`, cotas lidas).
- `## Comandos Úteis do Orca ADE` (Windows/PowerShell).
- `## Red Flags - Erros Críticos` (incluindo: nunca perguntar agente/modelo, nunca codificar no orquestrador, nunca pular Passo 2, TUI obrigatória sem `-p`/`exec`/`run`, nunca tratar provedor sem leitura como crítico, nunca elevar `readOnly` via fallback, nunca expor tokens).

- [ ] **Step 4: Rodar a suíte e confirmar tudo verde (GREEN)**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-OrchestrationAuto.ps1`
Expected: PASS em todos os testes das Tasks 1 e 2.

- [ ] **Step 5: Commit atômico da Task 2**

```bash
git add orca-superpowers-orchestration-auto/SKILL.md tests/Test-OrchestrationAuto.ps1
git commit -m "feat: adiciona SKILL.md da skill orca-superpowers-orchestration-auto"
```

---

### Task 3: `README.md` da Skill Nova + Atualização do `README.md` da Raiz (5 Destinos)

**Files:**
- Modify: `tests/Test-OrchestrationAuto.ps1` (adicionar bloco de validações de ambos os `README.md`)
- Create: `orca-superpowers-orchestration-auto/README.md`
- Modify: `README.md:5-26`

**Interfaces:**
- Consumes: `orca-superpowers-orchestration-auto/SKILL.md` e `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1`.
- Produces: documentação de entrada da skill e índice/instalador raiz atualizado para as 4 skills e 5 destinos.

- [ ] **Step 1: Adicionar testes de `README.md` (skill e raiz) em `tests/Test-OrchestrationAuto.ps1`**

Estender `tests/Test-OrchestrationAuto.ps1` com:
1. `Test-SkillReadme`: verifica existência de `orca-superpowers-orchestration-auto/README.md`, referência a `[SKILL.md](SKILL.md)` e `scripts/get-quotas.ps1`, seções `## Conteúdo`, `## Visão Geral`, `## Garantias` e menção a escolha automática sem perguntar + TUI obrigatória + gate único no Passo 2.
2. `Test-RootReadmeUpdated`: lê `README.md` na raiz e asserta:
   - Linha na tabela `## Skills` com `[orca-superpowers-orchestration-auto](orca-superpowers-orchestration-auto/SKILL.md)`.
   - `$skills` contém todas as 4 skills (`orca-superpowers-orchestrator`, `orca-superpowers-orchestration-auto`, `orca-superpowers-review-loop`, `orca-superpowers-merge`).
   - Loop de instalação contém exatamente os **5 destinos**:
     - `$env:USERPROFILE\.claude\skills\$skill`
     - `$env:USERPROFILE\.gemini\config\plugins\superpowers\skills\$skill`
     - `$env:USERPROFILE\.codex\skills\$skill`
     - `$env:USERPROFILE\.agents\skills\$skill`
     - `$env:USERPROFILE\.config\opencode\skills\$skill`
3. `Test-AllPs1ParseInPs51`: valida AST sem erros em todos os `.ps1` sob `orca-superpowers-orchestration-auto/` e `tests/`.

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-OrchestrationAuto.ps1`
Expected: FAIL nos 2 novos testes de README (enquanto Tasks 1 e 2 continuam PASS).

- [ ] **Step 3: Criar `orca-superpowers-orchestration-auto/README.md` e atualizar `README.md` da raiz**

- Criar `orca-superpowers-orchestration-auto/README.md` no mesmo estilo conciso de `orca-superpowers-review-loop/README.md` e `orca-superpowers-merge/README.md` (`# Skill Orquestração Automática (Orca Superpowers Orchestration Auto)`, `## Conteúdo` listando `SKILL.md` e `scripts/get-quotas.ps1`, `## Visão Geral` com Passos 0–5, `## Garantias`).
- Atualizar `README.md` da raiz:
  - Inserir a linha de `orca-superpowers-orchestration-auto` na tabela `## Skills`.
  - Atualizar `$skills` para incluir `"orca-superpowers-orchestration-auto"`.
  - Adicionar a 5ª linha de cópia no `foreach`: `Copy-Item -Recurse -Force $skill "$env:USERPROFILE\.config\opencode\skills\$skill"`.

- [ ] **Step 4: Rodar verificação completa (GREEN)**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-OrchestrationAuto.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File orca-superpowers-orchestration-auto/scripts/get-quotas.ps1
git status -sb
```
Expected: 100% dos testes PASS (exit code 0), `get-quotas.ps1` devolve JSON válido sem segredos, e apenas os arquivos esperados estão modificados/criados.

- [ ] **Step 5: Commit atômico da Task 3**

```bash
git add orca-superpowers-orchestration-auto/README.md README.md tests/Test-OrchestrationAuto.ps1
git commit -m "docs: adiciona README da skill orchestration-auto e atualiza instalacao nos 5 destinos"
```
