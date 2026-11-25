# `orca-superpowers-orchestration-auto` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar a skill `orca-superpowers-orchestration-auto` em **bash puro (Git Bash no Windows, bash no macOS/Linux)** e **agent-agnostic** no repositório `orcaADE-superpowers-skills`, usando `orca agent installed` + `orca account list` (`result.rateLimits`) como fontes principais, `orca agent launch --surface terminal --focus` para abertura de agentes, roteamento determinístico inspirado no Alethe, trilha de auditoria e atualização do `README.md` raiz nos 5 destinos.

**Architecture:** Um script bash puro sem dependências externas (`orca-superpowers-orchestration-auto/scripts/get-quotas.sh`, usando apenas `awk`/`sed`/`grep`/`tr`/`cut`/`curl` que vêm com o Git) consulta `orca agent installed --worktree active --json` e `orca account list --json` (ou fixtures offline `--agents-file`/`--accounts-file`) e imprime registros normalizados `INSTALLED|...`, `QUOTA|...`, `BUCKET|...` sem PII, com fallback documentado via `curl` quando o Orca não estiver disponível. A skill (`SKILL.md` + `README.md`) documenta o ciclo completo, o motor determinístico agent-agnostic e os presets JSON. Uma suíte TDD em bash puro (`tests/test-orchestration-auto.sh` + fixtures em `tests/fixtures/`) valida cada comportamento com um assert explícito.

**Tech Stack:** Markdown (skills Orca ADE), Bash + utilitários POSIX do Git (`awk`, `sed`, `grep`, `tr`, `cut`, `curl`), Orca CLI (`orca agent installed`, `orca account list`, `orca agent launch`, `orca terminal`).

**Spec:** `docs/superpowers/specs/2026-11-24-orca-superpowers-orchestration-auto-design.md`

## Global Constraints

- **Zero dependências externas (regra "quem tem Orca tem Git"):** usar exclusivamente `bash`, `awk`, `sed`, `grep`, `tr`, `cut` e `curl`. **Proibido** usar `python`, `python3`, `node`, `jq`, `pwsh`, `powershell` ou `bats` dentro da skill, do coletor ou dos testes.
- **Cross-platform (Windows via Git Bash, macOS, Linux):** invocação `bash <caminho>/scripts/get-quotas.sh` (com nota `"C:\Program Files\Git\bin\bash.exe" ...` apenas quando `bash` não estiver no `PATH` no Windows). Caminhos de credenciais no fallback `curl` sempre com `$HOME`/`~`, nunca `%APPDATA%`, `%TEMP%` nem `\`.
- **POSIX `awk` portátil:** evitar extensões exclusivas do GNU `awk` (`gensub`, 3º argumento de `match`) para rodar de forma idêntica no BSD `awk` do macOS e no GNU `awk` do Linux/Git Bash.
- **Agent-agnostic:** `orca agent installed --worktree active --json` define os agentes reais disponíveis em tempo de execução; nunca fixar 4 CLIs nem inventar `id` de agente ou de modelo.
- **Abertura de agente via `orca agent launch`:** `orca agent launch --agent <id> --worktree active [--model <id> [--effort <level>]] --surface terminal --focus --json`, respeitando que `--effort` exige `--model` (quando `model: null`, omitir ambos) e mantendo o contrato duro (`--focus` + `orca terminal wait --for tui-idle` + `orca terminal send`, sem `-p`/`--print`/`exec`/`run`).
- **Cotas principais via `orca account list --json`:** `result.rateLimits` é a fonte primária; `status: unavailable` ou agente sem entrada = **não crítico** (nunca segura trabalho). Endpoints diretos via `curl` são apenas fallback documentado.
- **Zero PII e zero segredos:** fixtures, exemplos, saída do script e relatórios nunca contêm e-mails, `organizationUuid`, caminhos `home` de conta nem tokens (`Bearer `, `access_token`, `accessToken`, `refresh_token`).
- **Ciclo e gate:** Planner → gate humano único (Passo 2) → Executor → Reviewer → Consolidação; nunca perguntar agente/modelo ao humano; `onBothCritical: run-cheapest | ask | block`.
- **Frontmatter e idioma:** `name: orca-superpowers-orchestration-auto` e `description: Use when ...` em inglês; corpo de `SKILL.md` e `README.md` em português.
- **Instalação no `README.md` raiz:** cobrir as 4 skills e os **5 destinos** (`~/.claude/skills`, `~/.gemini/config/plugins/superpowers/skills`, `~/.codex/skills`, `~/.agents/skills`, `~/.config/opencode/skills`).

## Review Focus

- **Parser JSON em POSIX `awk` sem `jq`:** `orca account list --json` tem objetos aninhados (`rateLimits.<provider>.session`, `weekly`, `buckets[]`) e objetos irmãos com chaves parecidas (`accounts[]`, `rateLimitResetCredits.credits[]`); o parser precisa rastrear profundidade/contexto de chaves para não confundir `status: "available"` de `credits[]` nem `buckets[].usedPercent` com `session.usedPercent`/`weekly.usedPercent` (pinned in Task 1).
- **Antigravity com múltiplos `buckets[]` e `status: unavailable` em outros provedores:** o script precisa extrair separadamente os 4 buckets (`Gemini Models` 300m/10080m e `Claude and GPT models` 300m/10080m) e preservar `QUOTA|<provider>|unavailable|-|-|-|-|-` sem erro quando `session` e `weekly` forem `null` (pinned in Task 1).
- **Regra `--effort` exige `--model` e fallback para agente não instalado:** `SKILL.md` deve garantir que papéis com `model: null` omitam `--model` e `--effort` no `orca agent launch`, e que se um papel ou seu `fallback` apontar para um agente ausente de `orca agent installed`, o resolvedor escolha o próximo agente instalado compatível registrando na auditoria (pinned in Task 2).
- **Integridade dos presets JSON, guarda `readOnly` e bloqueio de ferramentas proibidas:** todo `role` referenciado nas regras dos 3 presets (`economy`, `balanced`, `performance`) deve existir em `roles`, nenhum papel `readOnly: true` pode apontar `fallback` para `readOnly: false` ou para si mesmo, e `SKILL.md`/`README.md` da skill não podem citar `python`, `jq`, `powershell`, `%APPDATA%` nem PII (pinned in Task 2 e Task 3).
- **Portabilidade real em Git Bash (Windows), macOS e Linux:** todos os scripts `.sh` passam em `bash -n`, usam terminação LF (`\n`, sem CRLF quebrando `bash`) e todos os testes rodam offline com fixtures em `tests/fixtures/` sem depender de rede nem de contas locais (pinned in Task 1 e revalidado na Task 3).

---

### Task 1: Fixtures Sem PII + Coletor Bash Puro (`scripts/get-quotas.sh`) + Suíte Base TDD

**Files:**
- Create: `tests/fixtures/agent-installed.json`
- Create: `tests/fixtures/account-list.json`
- Create: `tests/test-orchestration-auto.sh`
- Create: `orca-superpowers-orchestration-auto/scripts/get-quotas.sh`

**Interfaces:**
- Produces (`orca-superpowers-orchestration-auto/scripts/get-quotas.sh`, executável via `bash orca-superpowers-orchestration-auto/scripts/get-quotas.sh [--agents-file <path>] [--accounts-file <path>]`):
  - Sem flags: chama `orca agent installed --worktree active --json` e `orca account list --json`; se `orca` não estiver no `PATH` ou falhar, aciona fallback direto `curl` para Claude (`$HOME/.claude/.credentials.json`) e Codex (`${CODEX_HOME:-$HOME/.codex}/auth.json`) emitindo `SOURCE|direct-curl`.
  - Com `--agents-file` / `--accounts-file`: lê os arquivos locais (modo offline/testes) e emite `SOURCE|orca`.
  - Contrato de saída stdout (uma linha por registro, zero PII, zero tokens):
    - `SOURCE|<orca|direct-curl>`
    - `INSTALLED|<agent_id>|<default|>`
    - `QUOTA|<provider>|<ok|unavailable>|<session_5h_pct|->|<weekly_pct|->|<worst_window|->|<worst_pct|->|<planType|->`
    - `BUCKET|<provider>|<group>|<windowMinutes>|<usedPercent>`

- [ ] **Step 1: Criar fixtures sem PII e os testes que falham em `tests/test-orchestration-auto.sh`**

1. Criar `tests/fixtures/agent-installed.json` reproduzindo a estrutura real de `orca agent installed --worktree active --json` com 6 agentes: `claude` (`"default": true`), `codex`, `opencode`, `opencode2`, `antigravity`, `copilot`.
2. Criar `tests/fixtures/account-list.json` reproduzindo a estrutura real de `orca account list --json` **sem qualquer PII** (sem e-mail, `organizationUuid`, `organizationName`, `home` ou `providerAccountId`), contendo `result.rateLimits` com:
   - `claude`: `status: "ok"`, `planType: "pro"`, `session.usedPercent: 5` (`windowMinutes: 300`), `weekly.usedPercent: 66` (`windowMinutes: 10080`).
   - `codex`: `status: "ok"`, `planType: "plus"`, `session.usedPercent: 0` (`windowMinutes: 300`), `weekly.usedPercent: 74` (`windowMinutes: 10080`), incluindo um array `rateLimitResetCredits.credits` com `"status": "available"` para provar que o parser não confunde `status` aninhado!
   - `antigravity`: `status: "ok"`, `session.usedPercent: 12` (`windowMinutes: 300`), `weekly.usedPercent: 6` (`windowMinutes: 10080`), `buckets[]` com os 4 itens (`Gemini Models` 10080m=6 e 300m=12; `Claude and GPT models` 10080m=0 e 300m=0).
   - `gemini`, `kimi`, `opencodeGo`: `session: null`, `weekly: null`, `status: "unavailable"`, `error: "..."`.
3. Criar `tests/test-orchestration-auto.sh` em bash puro (helpers `assert_eq`, `assert_contains`, `assert_not_contains`, contador `PASS`/`FAIL`, `exit 1` se `FAIL > 0`) com um assert por comportamento:
   - `test_script_exists_and_bash_syntax`: `orca-superpowers-orchestration-auto/scripts/get-quotas.sh` existe e passa em `bash -n`.
   - `test_no_forbidden_runtimes_in_script`: `get-quotas.sh` não invoca `python`, `python3`, `node`, `jq`, `pwsh` ou `powershell`.
   - `test_installed_agents_extracted`: rodando `bash scripts/get-quotas.sh --agents-file tests/fixtures/agent-installed.json --accounts-file tests/fixtures/account-list.json`, asserta presença exata de `INSTALLED|claude|default`, `INSTALLED|codex|`, `INSTALLED|opencode|`, `INSTALLED|opencode2|`, `INSTALLED|antigravity|`, `INSTALLED|copilot|`.
   - `test_claude_5h_and_weekly`: asserta `QUOTA|claude|ok|5|66|weekly|66|pro`.
   - `test_codex_5h_and_weekly`: asserta `QUOTA|codex|ok|0|74|weekly|74|plus` (e não corrompido por `credits[].status`).
   - `test_antigravity_windows_and_buckets`: asserta `QUOTA|antigravity|ok|12|6|session|12|-` e as 4 linhas `BUCKET|antigravity|Gemini Models|10080|6`, `BUCKET|antigravity|Gemini Models|300|12`, `BUCKET|antigravity|Claude and GPT models|10080|0`, `BUCKET|antigravity|Claude and GPT models|300|0`.
   - `test_unavailable_providers`: asserta `QUOTA|gemini|unavailable|-|-|-|-|-`, `QUOTA|kimi|unavailable|-|-|-|-|-`, `QUOTA|opencodeGo|unavailable|-|-|-|-|-`.
   - `test_no_pii_or_secrets`: asserta que nem as fixtures nem a saída do script contêm `@`, `organizationUuid`, `Bearer `, `access_token`, `accessToken`, `refresh_token` ou `C:\Users`.

- [ ] **Step 2: Rodar a suíte e confirmar que falha (RED)**

Run: `bash tests/test-orchestration-auto.sh` (ou `"C:\Program Files\Git\bin\bash.exe" tests/test-orchestration-auto.sh`)
Expected: FAIL indicando que `orca-superpowers-orchestration-auto/scripts/get-quotas.sh` não existe.

- [ ] **Step 3: Implementar `orca-superpowers-orchestration-auto/scripts/get-quotas.sh`**

Implementar em **bash puro + POSIX `awk`/`sed`/`grep`/`tr`/`cut`/`curl`** (sem `jq`/`python`/`node`/`pwsh`, gravado com LF `\n`):
- Parse de argumentos `--agents-file <path>` e `--accounts-file <path>`.
- **Extração de agentes instalados (`parse_agents_json`):** POSIX `awk` percorre o array `"agents"` rastreando profundidade de `{}` e extrai `"id"` e `"default"` de cada item → emite `INSTALLED|<id>|<default|>`.
- **Extração de cotas (`parse_rate_limits_json`):** POSIX `awk` tokeniza o JSON e rastreia a pilha de chaves/objetos dentro de `"rateLimits"`:
  - Em profundidade relativa 1 (`rateLimits.<provider>`): captura `status` e `planType` (ignorando `status` em níveis mais fundos como `rateLimitResetCredits.credits[]`!).
  - Em profundidade relativa 2 (`session` / `weekly`): captura `usedPercent`.
  - Em array `buckets[]`: captura `group`, `windowMinutes` e `usedPercent` de cada objeto e emite `BUCKET|<provider>|<group>|<windowMinutes>|<usedPercent>`.
  - Ao fechar cada `<provider>`: se `status == "ok"`, calcula `worst_window` (`session` se `session_pct >= weekly_pct`, senão `weekly`) e `worst_pct`, emitindo `QUOTA|<provider>|ok|<session|->|<weekly|->|<worst_window>|<worst_pct>|<planType|->`; se `status != "ok"`, emite `QUOTA|<provider>|unavailable|-|-|-|-|-`.
- **Fallback direto com `curl` (`collect_direct_curl`):** acionado apenas quando não há `--accounts-file` e `orca` está ausente ou `orca account list --json` falha: emite `SOURCE|direct-curl`, tenta Claude (`$CLAUDE_OAUTH_TOKEN` ou `$HOME/.claude/.credentials.json` → `curl` em `https://api.anthropic.com/api/oauth/usage`) e Codex (`${CODEX_HOME:-$HOME/.codex}/auth.json` → `curl` em `https://chatgpt.com/backend-api/wham/usage`), e emite `unavailable` para os demais provedores — nunca imprimindo tokens.

- [ ] **Step 4: Rodar os testes offline + smoke test real com Orca (GREEN)**

Run:
```bash
bash tests/test-orchestration-auto.sh
bash orca-superpowers-orchestration-auto/scripts/get-quotas.sh
```
Expected: todos os testes da Task 1 PASS; smoke test real imprime `SOURCE|orca`, os agentes instalados reais da máquina (`INSTALLED|...`), `QUOTA|...` e `BUCKET|antigravity|...`, com zero PII e zero tokens.

- [ ] **Step 5: Commit atômico da Task 1**

```bash
git add orca-superpowers-orchestration-auto/scripts/get-quotas.sh tests/fixtures/agent-installed.json tests/fixtures/account-list.json tests/test-orchestration-auto.sh
git commit -m "feat: adiciona coletor bash puro de cotas Orca, fixtures sem PII e testes"
```

---

### Task 2: Skill Principal (`orca-superpowers-orchestration-auto/SKILL.md`)

**Files:**
- Modify: `tests/test-orchestration-auto.sh` (adicionar asserts estruturais, agent-agnostic, portabilidade bash e integridade de presets JSON)
- Create: `orca-superpowers-orchestration-auto/SKILL.md`

**Interfaces:**
- Consumes: `orca-superpowers-orchestration-auto/scripts/get-quotas.sh` (invocação `bash <caminho-da-skill>/scripts/get-quotas.sh` e formato `INSTALLED|...`/`QUOTA|...`/`BUCKET|...`).
- Produces: `orca-superpowers-orchestration-auto/SKILL.md` com frontmatter YAML (`name: orca-superpowers-orchestration-auto`), protocolo agent-agnostic completo, presets JSON válidos (`economy`, `balanced`, `performance`), fallback `curl` documentado e trilha de auditoria.

- [ ] **Step 1: Adicionar asserts de `SKILL.md` em `tests/test-orchestration-auto.sh`**

Estender `tests/test-orchestration-auto.sh` com os seguintes testes (bash + POSIX `awk`/`grep`):
1. `test_skill_frontmatter`: `orca-superpowers-orchestration-auto/SKILL.md` existe, começa com `---`, contém `name: orca-superpowers-orchestration-auto` e `description: Use when `.
2. `test_skill_required_sections_and_contract`: asserta presença de:
   - Seções: `## Overview`, `## Descoberta Dinâmica de Agentes`, `## Quando Usar`, `## Medição Real de Cotas`, `## Motor Determinístico de Roteamento`, `## Presets de Roteamento`, `## Protocolo Operacional`, `## Trilha de Auditoria`, `## Comandos Úteis`, `## Red Flags`.
   - Agent-agnostic e Orca CLI: `orca agent installed --worktree active --json`, `orca account list --json`, `result.rateLimits`, `orca agent launch --agent`, `--surface terminal`, `--focus`, `--for tui-idle`, `orca terminal show --json`, `ETAPA planner CONCLUÍDA`, `ETAPA executor CONCLUÍDA`, `ETAPA reviewer CONCLUÍDA`, regra de que `--effort` exige `--model`, e proibição explícita de `-p`/`exec`/`run`.
   - Zero pergunta de alocação + gate humano único no Passo 2.
   - Roteamento Alethe: os 6 `kind` (`research`, `code`, `review`, `command`, `docs`, `scrap`), os 3 `effortClass` (`light`, `standard`, `deep`), `criticalThreshold`, `allowOpusOnDeep`, `onBothCritical`, `ask`, `run-cheapest`, `block`, `fallback`, guarda `readOnly`, regra de fallback para próximo agente instalado quando o fallback configurado não está instalado, e regra de que `status: unavailable` nunca é crítico.
   - Fallback direto com `curl`: `https://api.anthropic.com/api/oauth/usage`, `https://chatgpt.com/backend-api/wham/usage`, `https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`, `curl`, `$HOME/.claude/.credentials.json`, `$HOME/.codex/auth.json`.
   - Trilha de auditoria: `rule:`, `role:`, `agent:`, `model:`, `fallback:`, cotas lidas e seção `## Trilha de Auditoria de Roteamento` no relatório de review.
3. `test_skill_no_forbidden_tools_paths_or_pii`: asserta que `SKILL.md` **NÃO** contém `python3`, `get_quotas.py`, `jq `, `powershell`, `pwsh`, `%APPDATA%`, `%TEMP%`, `AppData\\Local`, `$env:USERPROFILE`, `organizationUuid` ou e-mail (`@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`).
4. `test_skill_presets_integrity`: usando POSIX `awk` sobre o bloco ` ```json ` de `## Presets de Roteamento` em `SKILL.md`, asserta:
   - Presença dos 3 presets (`"economy"`, `"balanced"`, `"performance"`).
   - Chaves `{}` e colchetes `[]` estritamente balanceados.
   - Todo `"role"` usado em `"rules"` existe na lista `"roles"` do mesmo preset.
   - Todo `"fallback"` não nulo em `"roles"` existe em `"roles"`, difere de `"name"`, e se o papel tem `"readOnly": true`, o papel de fallback também tem `"readOnly": true`.
   - Nenhum papel com `"model": null` define `"effort"` não nulo (respeitando `--effort` exige `--model` do `orca agent launch`).

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `bash tests/test-orchestration-auto.sh`
Expected: FAIL indicando que `orca-superpowers-orchestration-auto/SKILL.md` não existe (enquanto testes da Task 1 continuam PASS).

- [ ] **Step 3: Criar `orca-superpowers-orchestration-auto/SKILL.md`**

Redigir `orca-superpowers-orchestration-auto/SKILL.md` em português (frontmatter em inglês), cobrindo integralmente as Seções 3, 4, 5, 6 e 7 da Spec revisada:
- Frontmatter YAML (`name: orca-superpowers-orchestration-auto`, `description: Use when ...`).
- `## Overview` + diagrama ASCII do ciclo completo (Passo 0 automático via `get-quotas.sh` → `orca agent launch` Planner → Passo 2 Gate humano único → Executor → Reviewer → Consolidação + Trilha de Auditoria).
- `## Descoberta Dinâmica de Agentes e Modelos`:
  - `orca agent installed --worktree active --json` como fonte de verdade (nunca fixar 4 CLIs; agente instalado sem papel fica fora; nunca inventar `id` de agente ou modelo).
  - Decisão justificada em uma linha por `orca agent launch --agent <id> --worktree active [--model <id> [--effort <level>]] --surface terminal --focus --json` + regra "`--effort` exige `--model`" + `orca terminal create` como alternativa.
  - Descoberta por agente (`agy models` para `antigravity`, listando os modelos reais verificados na máquina; `model: null` para agentes sem lista explícita).
- `## Quando Usar` / `### Quando NÃO Usar`.
- `## Medição Real de Cotas`:
  - Invocação em macOS/Linux/Git Bash (`bash <caminho-da-skill>/scripts/get-quotas.sh`) e nota de caminho do Git Bash no Windows (`"C:\Program Files\Git\bin\bash.exe" ...`) quando `bash` não estiver no `PATH`.
  - Fonte principal: `orca account list --json` → `result.rateLimits` (chaves `claude`, `codex`, `antigravity` com `buckets[]`, `gemini`, `kimi`, `grok`, `cursor`, `muse`, `minimax`, `zcode`, `opencodeGo`, `inactiveClaudeAccounts[]`/`inactiveCodexAccounts[]`, `status: unavailable` = não crítico).
  - Fallback documentado via `curl` com `$HOME` (Claude `/api/oauth/usage`, Codex `/wham/usage`, Antigravity `fetchAvailableModels` com `User-Agent` contendo `antigravity` e degradação explícita quando o SO não expõe keyring em bash puro).
  - Invariante de privacidade e segurança (zero PII, zero tokens).
- `## Motor Determinístico de Roteamento`:
  - `kind` (6 valores), `effortClass` (3 valores) + heurística objetiva + mapeamento das 3 etapas.
  - `Role` (por `id` do Orca), `QuotaGate`, `RoutingRule`, `RoutingSettings` (`preset: "balanced"`, `criticalThreshold: 80`, `allowOpusOnDeep: true`, `onBothCritical: "run-cheapest" | "ask" | "block"`).
  - Algoritmo determinístico em 4 etapas: avaliação top-down filtrada por `INSTALLED_AGENTS` → fallback de 1 nível por cota (e fallback para próximo agente instalado quando o fallback configurado não está instalado, com guarda `readOnly`) → independência de vendor no Reviewer → `onBothCritical`.
- `## Presets de Roteamento`: bloco ` ```json ` único com `economy`, `balanced` (default) e `performance` usando `claude`, `codex` (`model: null, effort: null`) e `antigravity` (modelos reais de `agy models`), respeitando guarda `readOnly`.
- `## Protocolo Operacional do Orquestrador`: Passos 0 a 5 completos (Passo 0 sem perguntar agente/modelo, Passo 2 gate humano único, revalidação de cota nos Passos 3 e 4, templates de prompt com `ETAPA <papel> CONCLUÍDA` e bloco `## Trilha de Auditoria de Roteamento` injetado no Reviewer).
- `## Trilha de Auditoria`: formato padronizado (`rule:<id>`, `role:<papel>`, `agent:<id>`, `model:<id>`, `fallback:<de→para> por cota`, agentes instalados e cotas lidas, sem PII).
- `## Comandos Úteis do Orca ADE`.
- `## Red Flags - Erros Críticos`.

- [ ] **Step 4: Rodar a suíte e confirmar tudo verde (GREEN)**

Run: `bash tests/test-orchestration-auto.sh`
Expected: PASS em todos os testes das Tasks 1 e 2.

- [ ] **Step 5: Commit atômico da Task 2**

```bash
git add orca-superpowers-orchestration-auto/SKILL.md tests/test-orchestration-auto.sh
git commit -m "feat: adiciona SKILL.md agent-agnostic e bash/Git Bash da skill orchestration-auto"
```

---

### Task 3: `README.md` da Skill Nova + Atualização do `README.md` da Raiz (5 Destinos)

**Files:**
- Modify: `tests/test-orchestration-auto.sh` (adicionar asserts dos dois `README.md`)
- Create: `orca-superpowers-orchestration-auto/README.md`
- Modify: `README.md:5-26`

**Interfaces:**
- Consumes: `orca-superpowers-orchestration-auto/SKILL.md` e `orca-superpowers-orchestration-auto/scripts/get-quotas.sh`.
- Produces: documentação concisa da skill (sem Python/PowerShell/jq) e índice/instalador raiz atualizado para as 4 skills nos **5 destinos** em macOS/Linux/Git Bash (`$HOME/...`) e alternativa PowerShell.

- [ ] **Step 1: Adicionar asserts de `README.md` (skill e raiz) em `tests/test-orchestration-auto.sh`**

Estender `tests/test-orchestration-auto.sh` com:
1. `test_skill_readme`: verifica existência de `orca-superpowers-orchestration-auto/README.md`, links para `[SKILL.md](SKILL.md)` e `scripts/get-quotas.sh`, seções `## Conteúdo`, `## Visão Geral`, `## Garantias`, menção a agent-agnostic (`orca agent installed` / `orca account list`), bash/Git Bash (Windows/macOS/Linux), escolha automática sem perguntar, TUI obrigatória, gate único no Passo 2, e ausência de `python3`, `jq`, `powershell`, `%APPDATA%` ou PII.
2. `test_root_readme_5_destinations`: lê `README.md` da raiz e asserta:
   - Linha na tabela `## Skills` com `[orca-superpowers-orchestration-auto](orca-superpowers-orchestration-auto/SKILL.md)`.
   - Bloco de instalação **macOS / Linux / Git Bash** contendo as 4 skills e os **5 destinos**:
     - `$HOME/.claude/skills/$skill`
     - `$HOME/.gemini/config/plugins/superpowers/skills/$skill`
     - `$HOME/.codex/skills/$skill`
     - `$HOME/.agents/skills/$skill`
     - `$HOME/.config/opencode/skills/$skill`
   - Bloco alternativo Windows PowerShell também atualizado com as 4 skills e os **5 destinos** (`\.claude\skills`, `\.gemini\config\plugins\superpowers\skills`, `\.codex\skills`, `\.agents\skills`, `\.config\opencode\skills`).
3. `test_all_sh_scripts_lf_and_syntax`: verifica `bash -n` e ausência de CRLF (`\r`) em `orca-superpowers-orchestration-auto/scripts/get-quotas.sh` e `tests/test-orchestration-auto.sh`.

- [ ] **Step 2: Rodar a suíte e confirmar que os novos testes falham (RED)**

Run: `bash tests/test-orchestration-auto.sh`
Expected: FAIL nos novos testes de README (enquanto Tasks 1 e 2 continuam PASS).

- [ ] **Step 3: Criar `orca-superpowers-orchestration-auto/README.md` e atualizar `README.md` da raiz**

- Criar `orca-superpowers-orchestration-auto/README.md` no estilo conciso das 3 skills existentes (`# Skill Orquestração Automática (Orca Superpowers Orchestration Auto)`, `## Conteúdo`, `## Visão Geral`, `## Garantias`).
- Atualizar `README.md` da raiz:
  - Adicionar `orca-superpowers-orchestration-auto` à tabela `## Skills`.
  - Em `## Instalação`, colocar como caminho principal o loop **bash / Git Bash (macOS, Linux e Windows)** com as 4 skills nos **5 destinos** `$HOME/...`, e manter abaixo a opção alternativa em PowerShell atualizada para as 4 skills e os **5 destinos**.

- [ ] **Step 4: Rodar verificação completa (GREEN)**

Run:
```bash
bash tests/test-orchestration-auto.sh
bash orca-superpowers-orchestration-auto/scripts/get-quotas.sh
git status -sb
```
Expected: 100% dos testes PASS (exit code 0), `get-quotas.sh` retorna dados reais sem PII/tokens, e apenas os arquivos esperados estão criados/modificados.

- [ ] **Step 5: Commit atômico da Task 3**

```bash
git add orca-superpowers-orchestration-auto/README.md README.md tests/test-orchestration-auto.sh
git commit -m "docs: adiciona README da skill orchestration-auto e atualiza instalacao nos 5 destinos"
```
