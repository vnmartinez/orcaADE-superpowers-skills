# Especificação Técnica — `orca-superpowers-orchestration-auto`

**Data:** 2026-11-25 (Revisão 3 — bash/Git Bash + agent-agnostic)
**Repositório:** `orcaADE-superpowers-skills`
**Branch:** `main`
**Status:** Proposta revisada (aguardando gate humano via orquestrador)

---

## 1. Objetivo e Escopo

Criar a skill **`orca-superpowers-orchestration-auto`** no repositório `orcaADE-superpowers-skills`, **cross-platform (Windows via Git Bash, macOS e Linux)** e **agent-agnostic**, seguindo o padrão estrutural e operacional das skills existentes (`orca-superpowers-orchestrator`, `orca-superpowers-review-loop`, `orca-superpowers-merge`).

A skill entrega o mesmo ciclo ponta a ponta do `orca-superpowers-orchestrator` (**Planner → Gate humano do plano → Executor → Reviewer → Consolidação**) no mesmo worktree ativo do Orca ADE (`--worktree active`) com **TUI interativa obrigatória**, mas substitui a alocação manual e a lista fixa de CLIs por:

- **Descoberta dinâmica de agentes instalados:** `orca agent installed --worktree active --json` é a fonte de verdade em tempo de execução — a skill nunca fixa 4 CLIs nem inventa agentes.
- **Zero perguntas de alocação:** o orquestrador nunca pergunta ao usuário qual agente ou modelo executa Planner, Executor ou Reviewer.
- **Único gate humano no fluxo normal:** aprovação do plano gerado pelo Planner (Passo 2). A única exceção configurável é `onBothCritical: "ask"` quando todos os provedores com leitura válida ultrapassam o limiar crítico.
- **Medição real de cota cross-platform e agent-agnostic:** `orca account list --json` (`result.rateLimits`) é a fonte principal (já normalizada pelo Orca para todos os provedores conectados, com janelas de 5h, semanal e buckets do Antigravity), com fallback documentado via `curl` para endpoints diretos quando o Orca não estiver disponível.
- **Trilha de auditoria completa:** toda decisão registra `preset`, `kind`, `effortClass`, agentes instalados, snapshot das cotas lidas, regra vencedora (`rule:<id>`), papel escolhido (`role:<papel>`), `agent:<id>`, `model:<id>`, eventuais fallbacks (`fallback:<de→para> por cota` ou por agente não instalado) e independência de vendor no Reviewer.

> **Escolha de runtime único (zero dependências externas):** o coletor de cotas e a suíte de testes usam **bash puro** + utilitários POSIX que acompanham o Git (`awk`, `sed`, `grep`, `tr`, `cut`, `curl`), porque **quem tem Orca tem Git** (Git Bash no Windows, bash nativo no macOS/Linux) — sem exigir `python`, `node`, `jq`, `pwsh`, PowerShell ou `bats`.

### Fora de Escopo

- Alterar o comportamento da skill manual `orca-superpowers-orchestrator`.
- Exigir qualquer runtime adicional além do Git + Orca CLI.
- Implementar malha de review reprovado ou merge automatizado (continuam delegados a `orca-superpowers-review-loop` e `orca-superpowers-merge`).

---

## 2. Estrutura de Arquivos

| Caminho | Responsabilidade |
|---|---|
| `orca-superpowers-orchestration-auto/SKILL.md` | Definição completa da skill (frontmatter YAML `name`/`description` em inglês no padrão da família; protocolo operacional em português, descoberta dinâmica via Orca, presets JSON, algoritmo determinístico de roteamento, leitura de cotas via `orca account list` + fallback `curl`, templates de prompt e Red Flags) |
| `orca-superpowers-orchestration-auto/README.md` | Resumo da skill no padrão das 3 skills existentes (`Conteúdo`, `Visão Geral`, `Garantias`) |
| `orca-superpowers-orchestration-auto/scripts/get-quotas.sh` | Script **bash puro** (`awk`/`sed`/`grep`/`tr`/`cut`, sem `jq`/`python`/`node`/`pwsh`) que consulta `orca agent installed --worktree active --json` e `orca account list --json` (ou fixtures `--agents-file`/`--accounts-file` para testes), extrai agentes instalados, janelas 5h/semanal, buckets e status `unavailable` sem PII; com fallback `curl` quando o Orca não estiver disponível |
| `tests/fixtures/agent-installed.json` | Fixture sem PII baseada na saída real de `orca agent installed --worktree active --json` |
| `tests/fixtures/account-list.json` | Fixture sem PII baseada na saída real de `orca account list --json` (janelas 5h/semanal de `claude` e `codex`, `antigravity` com `buckets[]`, e provedores `unavailable`) |
| `tests/test-orchestration-auto.sh` | Suíte TDD em **bash puro** (sem `bats`, `jq`, `python` ou PowerShell): valida sintaxe, extração sobre fixtures (um assert por comportamento), ausência de PII/segredos, contrato de `SKILL.md`, integridade dos presets, `README.md` da skill e `README.md` raiz nos 5 destinos |
| `README.md` (raiz) | Adicionar `orca-superpowers-orchestration-auto` à tabela `## Skills` e atualizar o bloco de instalação cobrindo as 4 skills e os **5 destinos** em macOS/Linux/Git Bash (`$HOME/...`) e alternativa PowerShell |

---

## 3. Contrato Operacional no Orca ADE e Decisão de Abertura de Agente

### Decisão de comando de abertura de agente

- **Caminho principal:** `orca agent launch --agent <id> --worktree active [--model <id> [--effort <level>]] --surface terminal --focus --json` — escolhido em uma linha por ser **nativamente agent-agnostic** (recebe qualquer `id` retornado por `orca agent installed`), eliminar mapeamento hardcoded de flags por CLI e manter o mesmo contrato de TUI interativa do repositório.
- **Regra do Orca CLI para `--effort`:** `--effort` exige `--model`. Quando o papel usar `model: null` (default do agente), omitir **ambos** `--model` e `--effort`.
- **Alternativa documentada:** `orca terminal create --worktree active --title "<titulo>" --focus --command "<CLI>" --json` permanece documentado apenas se o usuário precisar passar flags específicas de CLI não expostas pelo `orca agent launch`.

### Contrato duro (idêntico às demais skills da família)

1. **Papel estrito do Orquestrador:** atua apenas como hub supervisor, coletor de cota e despachante. Nunca escreve código de produção, especificações, planos nem executa a suíte de testes do projeto-alvo.
2. **Worktree único:** todos os despachos usam `--worktree active`. Nunca criar worktrees separados por etapa.
3. **TUI interativa 100% obrigatória:**
   ```bash
   orca agent launch --agent <id> --worktree active [--model <model> [--effort <effort>]] --surface terminal --focus --json
   orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
   # satisfied: false -> repetir wait UMA vez com timeout maior (ex.: 180000); ainda false -> PARAR e avisar o usuário
   orca terminal send --terminal <handle> --text "<PROMPT>" --enter --json
   ```
   **Proibido** qualquer fallback para modo não-interativo (`-p`, `--print`, `exec`, `run`).
4. **Identificação prévia do orquestrador (`<ORQ_HANDLE>`):** executar `orca terminal show --json` antes do Passo 1. Se falhar, interromper e avisar o usuário.
5. **Prova exclusiva de conclusão:** cada agente despachado só encerra após enviar ao `<ORQ_HANDLE>`:
   ```text
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA <planner|executor|reviewer> CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: <caminho-ou->" --enter --json
   ```
   Ausência de aviso nunca conta como conclusão; sem aviso em 10 minutos, ler o terminal do agente (`orca terminal read --terminal <handle> --limit 50 --json`) antes de decidir.
6. **Envio seguro de prompts longos:** evitar aspas duplas não escapadas dentro de `--text`; para prompts longos, gravar em `${TMPDIR:-/tmp}/orca-prompt-<etapa>.md` e enviar instrução curta sem aspas internas no `--text`.

---

## 4. Descoberta Dinâmica de Agentes e Modelos (Agent-Agnostic)

### 4.1 Agentes instalados (fonte de verdade)

Em tempo de execução (Passo 0), o orquestrador descobre os agentes disponíveis rodando `bash <caminho-da-skill>/scripts/get-quotas.sh`, que consulta:

```bash
orca agent installed --worktree active --json
```

Exemplo real (sem PII): `claude` (default), `codex`, `opencode`, `opencode2`, `antigravity`, `copilot`.

Regras rígidas de portabilidade entre agentes:
- Nunca fixar uma lista fechada de 4 CLIs.
- Cada `id` retornado por `orca agent installed` é um candidato válido para `orca agent launch --agent <id>`.
- Agente listado em preset mas **ausente** de `orca agent installed` não pode ser despachado; o resolvedor tenta o `fallback` ou o próximo agente instalado compatível.
- Agente instalado que nenhum papel referencia simplesmente fica fora do roteamento (sem erro).
- Nunca inventar `id` de agente nem `id` de modelo.

### 4.2 Descoberta de modelos por agente

O Orca não possui um comando único de listagem de modelos para todos os agentes; a descoberta é por agente quando o CLI expõe listagem:

- **Antigravity (`antigravity`):** `agy models` — modelos reais verificados nesta máquina (usados nos exemplos/presets):
  - `gemini-4-neon-{low,medium,high,xhigh}`
  - `gemini-4-carbon-{low,medium,high}`
  - `gemini-4-argon-{low,medium,high}`
  - `gemini-4-hydrogen-{low,medium,high,xhigh}`
  - `gemini-pro-orchestrator`, `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator-argon`
  - `gemini-3.8-flash-{low,medium,high}`
  - `claude-opus-5-5-{low,medium,high}`, `claude-sonnet-5-5-{low,medium,high}`, `gpt-oss-120b-medium`
- **Claude (`claude`):** aliases/modelos configurados (ex.: `claude-sonnet-5-5`, `claude-opus-5-5`, `haiku`, ou `null` para default).
- **Codex (`codex`), OpenCode (`opencode`, `opencode2`), Copilot (`copilot`) e demais agentes sem lista explícita:** usar `model: null` (default configurado no agente, omitindo `--model` e `--effort` no `orca agent launch`).

---

## 5. Medição Real de Cotas (Bash / Git Bash)

### 5.1 Invocação por SO

- **macOS / Linux / Windows (Git Bash no `PATH`):**
  ```bash
  bash <caminho-da-skill>/scripts/get-quotas.sh
  ```
- **Windows (quando `bash` não estiver no `PATH`):**
  ```text
  "C:\Program Files\Git\bin\bash.exe" <caminho-da-skill>/scripts/get-quotas.sh
  ```

### 5.2 Fonte Principal: `orca account list --json` (`result.rateLimits`)

Cross-platform, agent-agnostic e já normalizada pelo Orca ADE. O comando retorna:
- `accounts[]` e `activeAccountId` por agente configurado (contas conectadas);
- `result.rateLimits.<provider>` com `{ provider, session{usedPercent, windowMinutes, resetsAt, resetDescription}, weekly{...}, monthly, status: "ok"|"unavailable", error, planType }`;
- `result.rateLimits.antigravity.buckets[]` com grupos (`Gemini Models`, `Claude and GPT models`), `windowName`, `usedPercent`, `windowMinutes` (`300` = 5h, `10080` = semanal) e `resetsAt`;
- `inactiveClaudeAccounts[]` / `inactiveCodexAccounts[]` (quando houver contas secundárias configuradas com `rateLimits` próprios).

Chaves observadas em `result.rateLimits`: `claude`, `codex`, `antigravity`, `gemini`, `kimi`, `grok`, `cursor`, `muse`, `minimax`, `zcode`, `opencodeGo` (e qualquer novo provedor que o Orca passar a expor — o parser lê dinamicamente todas as chaves sob `rateLimits`).

Mapeamento de `agent.id` ↔ chave em `rateLimits`:
- Match exato primeiro (`claude` ↔ `claude`, `codex` ↔ `codex`, `antigravity` ↔ `antigravity`, `gemini` ↔ `gemini`, `kimi` ↔ `kimi`, `cursor` ↔ `cursor`, etc.).
- Alias conhecido: `opencode` / `opencode2` ↔ `opencodeGo`.
- Agente instalado sem entrada em `rateLimits` (ex.: `copilot`) ou com `status: "unavailable"` → **sem leitura → nunca é crítico**.

### 5.3 Formato de Saída de `scripts/get-quotas.sh` (Parseável sem `jq` e Sem PII)

O script usa exclusivamente `awk`, `sed`, `grep`, `tr` e `cut` (compatível com BSD `awk` no macOS e GNU `awk` no Linux/Git Bash) e **descarta todos os campos pessoais** (`email`, `organizationUuid`, `organizationName`, `home`, `providerAccountId`). Saída normalizada por linha:

```text
SOURCE|orca
INSTALLED|claude|default
INSTALLED|codex|
INSTALLED|opencode|
INSTALLED|opencode2|
INSTALLED|antigravity|
INSTALLED|copilot|
QUOTA|claude|ok|5|66|weekly|66|pro
QUOTA|codex|ok|0|74|weekly|74|plus
QUOTA|antigravity|ok|12|6|session|12|-
BUCKET|antigravity|Gemini Models|10080|6
BUCKET|antigravity|Gemini Models|300|12
BUCKET|antigravity|Claude and GPT models|10080|0
BUCKET|antigravity|Claude and GPT models|300|0
QUOTA|gemini|unavailable|-|-|-|-|-
QUOTA|kimi|unavailable|-|-|-|-|-
QUOTA|opencodeGo|unavailable|-|-|-|-|-
```

Legenda dos campos de `QUOTA`: `QUOTA|<provider>|<status>|<session_pct_5h>|<weekly_pct>|<worst_window>|<worst_pct>|<planType>`.
Legenda de `BUCKET`: `BUCKET|<provider>|<group>|<windowMinutes>|<usedPercent>`.

Flags opcionais de teste offline no script:
- `--agents-file <caminho.json>`: lê a saída de `orca agent installed` de arquivo (fixture).
- `--accounts-file <caminho.json>`: lê a saída de `orca account list` de arquivo (fixture).

### 5.4 Fallback Documentado via `curl` (Quando o Orca Não Estiver Disponível)

Quando `orca` não estiver no `PATH` ou `orca account list --json` falhar (sem `--accounts-file`), a skill documenta (e o script pode acionar com `SOURCE|direct-curl`) o fallback direto com `curl` + caminhos `$HOME` portáteis (nunca `%APPDATA%` nem `\`):

- **Claude:** token de `$CLAUDE_OAUTH_TOKEN` ou `$HOME/.claude/.credentials.json` (`claudeAiOauth.accessToken`) →
  `curl -sfS --max-time 10 -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" "https://api.anthropic.com/api/oauth/usage"` (`five_hour`, `seven_day`, `seven_day_opus`).
- **Codex:** token e opcional `account_id` de `${CODEX_HOME:-$HOME/.codex}/auth.json` (`tokens.access_token`, `tokens.account_id`) →
  `curl -sfS --max-time 10 -H "Authorization: Bearer $TOKEN" -H "User-Agent: orca-quota-check/1.0" [-H "ChatGPT-Account-Id: $ACC"] "https://chatgpt.com/backend-api/wham/usage"` (`primary_window` / `secondary_window`, `used_percent`, `limit_reached`; swap de janela quando `primary` > 1440 min).
- **Antigravity:** `POST https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` com body `{}` e `User-Agent` contendo `antigravity` (lendo `token.access_token` do keyring do SO: `security` no macOS, `secret-tool` no Linux; no Windows sem Orca não há leitura direta em bash puro → degrada para `status: unavailable` = não crítico).
- **Demais provedores sem leitura direta:** `QUOTA|<provider>|unavailable|-|-|-|-|-` (**nunca críticos**).

### 5.5 Invariante de Segurança e Privacidade (Zero PII / Zero Tokens)

`get-quotas.sh`, fixtures, exemplos na skill e trilha de auditoria **jamais** incluem e-mails, `organizationUuid`, caminhos `home` de conta ou tokens (`accessToken`, `access_token`, `refresh_token`, `Authorization`, `CLAUDE_OAUTH_TOKEN`).

---

## 6. Motor Determinístico de Roteamento

Inspirado em `orchestrator_core.rs`, `routingPresets.ts` e `agentFitness.ts` do Alethe, estendido para ser **agent-agnostic** sobre `INSTALLED_AGENTS` e `QUOTA`/`BUCKET` do Orca.

### 6.1 Modelo de Dados

- **`kind`** (6 valores fixos): `research | code | review | command | docs | scrap`
- **`effortClass`** (3 valores fixos): `light | standard | deep`
- **`Role`** (baseado em `agent` = `id` do Orca):
  ```json
  {
    "name": "builder",
    "agent": "claude",
    "model": "claude-sonnet-5-5",
    "effort": "medium",
    "readOnly": false,
    "timeoutSeconds": null,
    "fallback": "codex-builder",
    "orchestrator": null
  }
  ```
- **`QuotaGate`**:
  ```json
  { "agent": "claude", "window": "week", "below": 75 }
  ```
  Mapeamento de `window`:
  - `"short"` → `session` (5h)
  - `"week"` → `weekly` (7d)
  - `"opus"` → janela Opus do `claude` (no Orca `fableWeekly`/fallback `weekly`; no `curl` direto `seven_day_opus`); em outros provedores mapeia para `weekly`
  - Nome de grupo de bucket (ex.: `"Gemini Models"`, `"Claude and GPT models"` no `antigravity`) → maior `usedPercent` entre os buckets daquele grupo
- **`RoutingRule`**: `{ id, enabled, kinds[], efforts[], gates[], role }`
- **`RoutingSettings`**:
  - `preset`: `"economy" | "balanced" | "performance" | "custom"` (padrão: **`"balanced"`**)
  - `criticalThreshold`: `0..100` (padrão: **`80`**)
  - `allowOpusOnDeep`: booleano (padrão: **`true`**)
  - `onBothCritical`: `"run-cheapest" | "ask" | "block"` (padrão na skill auto: **`"run-cheapest"`**, mantendo o gate do plano como única pergunta no fluxo padrão; configurável para `"ask"` ou `"block"`)

### 6.2 Classificação da Tarefa e Mapeamento para o Ciclo de 3 Etapas

| `effortClass` | Critério objetivo |
|---|---|
| `light` | Ajuste localizado em 1–2 arquivos, correção pontual, documentação simples ou tarefa mecânica sem mudança arquitetural |
| `standard` | Nova feature ou refatoração localizada em múltiplos arquivos/módulos com TDD, seguindo padrões existentes do repo |
| `deep` | Decisão arquitetural, novo protocolo/motor, concorrência, segurança, migração crítica ou mudança transversal em vários subsistemas |

Mapeamento das etapas do ciclo:
1. **Planner:** `kind = "docs"` (se puramente documental) ou `kind = "research"` (padrão) + `effortClass` da tarefa.
2. **Executor:** `kind = "docs"` (se entrega documental) ou `kind = "code"` (padrão; `"command"` para automação CLI pura) + `effortClass` da tarefa.
3. **Reviewer:** `kind = "review"` + `effortClass` da tarefa.

### 6.3 Algoritmo de Resolução (Determinístico e Agent-Agnostic)

Para cada etapa `(kind, effortClass)`:

1. **Avaliação de regras (de cima para baixo):**
   - Ignorar regra com `enabled == false`.
   - `kinds` vazio **ou** contém `kind`.
   - `efforts` vazio **ou** contém `effortClass` (se `effortClass` for nulo, só casa regra com `efforts` vazio).
   - **Todos** os `gates` devem passar (`gate_passes`):
     - Se `QUOTA` do `gate.agent` ausente ou `status != "ok"` → **passa (`true`)** (provedor sem leitura nunca segura trabalho).
     - Se a janela nomeada for nula/`-` → **passa (`true`)**.
     - Caso contrário → passa se e somente se `usedPercent < gate.below`.
   - Resolver `role` em `roles` (preferindo `role.orchestrator == agenteAtualDoOrquestrador`, senão `role.orchestrator == null`).
   - Se `allowOpusOnDeep == false` e `role.model` contém `"opus"` (case-insensitive), pular regra.
   - **Checagem de instalação (`INSTALLED_AGENTS`):** se `role.agent` estiver em `INSTALLED_AGENTS`, **a regra vence** (`rule:<id>`, `role:<name>`). Se `role.agent` **não** estiver instalado, testar `role.fallback` (se instalado e mantendo `readOnly`); se nenhum estiver instalado, continuar para a próxima regra. Se nenhuma regra tiver agente instalado, escolher o primeiro agente de `INSTALLED_AGENTS` (priorizando o marcado `default`) e registrar `fallback: <role> → <agent-instalado> (agente não instalado)`.

2. **Checagem de limiar crítico e Fallback de 1 nível:**
   - Um provedor é **crítico** se e somente se `status == "ok"` **E** (`worst_pct >= criticalThreshold` **OU** `rateLimited == true`). Provedor `unavailable` ou ausente **não é crítico**.
   - Se o provedor do papel escolhido não for crítico → manter.
   - Se for crítico:
     - Tentar `role.fallback` (1 nível apenas; proibido elevar `readOnly: true` → `readOnly: false`).
     - Se `role.fallback` estiver em `INSTALLED_AGENTS` e não for crítico → trocar e registrar `fallback: <role> → <fallback> por cota (<agent> <worst>=<pct>%)`.
     - Se `role.fallback` **não** estiver instalado (ou ausente), procurar o próximo agente em `INSTALLED_AGENTS` não crítico que sirva ao papel (sem `model` hardcoded se não houver papel para ele, preservando `readOnly` no Reviewer) e registrar `fallback: <role> → <agent-instalado> (fallback <fallback> não instalado)`.

3. **Independência de vendor no Reviewer (Passo 4):**
   - Se o `agent` resolvido para o Reviewer for igual ao `agent` que executou o Executor, tentar `role.fallback` (se `readOnly: true`, instalado e não crítico) ou outro agente instalado diferente do Executor e registrar `vendor-independence: <role> → <destino> (Executor usou <agent>)`.

4. **Todos os provedores medidos críticos (`onBothCritical`):**
   - Considerar o conjunto `M` dos provedores com `status == "ok"` dentre os agentes em `INSTALLED_AGENTS`.
   - Se `M` não é vazio **E** todos em `M` estão críticos (`>= criticalThreshold`):
     - `"run-cheapest"`: selecionar o papel mais econômico disponível entre os instalados (ou o de menor `worst_pct`, respeitando `readOnly` no Reviewer) e registrar `all-critical: run-cheapest`.
     - `"ask"`: pausar e perguntar ao usuário se deseja prosseguir apesar das cotas críticas, exibindo percentuais e reset.
     - `"block"`: interromper sem despachar, exibindo percentuais e reset, e encerrar com `status: FALHA`.

### 6.4 Presets Embutidos (JSON válido, IDs do Orca e Modelos Reais)

Os 3 presets (`economy`, `balanced` [default], `performance`) usam IDs de agente do Orca (`claude`, `codex`, `antigravity`), `model: null` + `effort: null` onde o agente usa seu default (`codex`), e modelos reais do Antigravity/Claude verificados na máquina:

- **`economy`**: prioriza `antigravity` (`gemini-3.8-flash-medium`, `gemini-4-argon-medium`, `gemini-4-carbon-medium`) e `codex` (default); sem Opus.
- **`balanced` (padrão)**:
  - `docs`/`scrap`/`research` `light` → `scout` (`antigravity` `gemini-3.8-flash-high`, `low`, fallback `codex-light`)
  - `review` → `reviewer-antigravity` (`antigravity` `gemini-4-neon-high`, `high`, `readOnly: true`, fallback `codex-reviewer` `readOnly: true`)
  - `code`/`research`/`command` `deep` com gate `claude.week < 75` e `claude.opus < 50` (e `allowOpusOnDeep: true`) → `expert` (`claude` `claude-opus-5-5`, `high`, fallback `antigravity-planner`)
  - `research`/`docs` `standard`/`deep` → `planner-std` (`codex`, `model: null`, `effort: null`, fallback `antigravity-planner`)
  - `code`/`command` `light` → `codex-builder` (`codex`, `model: null`, `effort: null`, fallback `antigravity-builder`)
  - Default → `builder` (`claude` `claude-sonnet-5-5`, `medium`, fallback `codex-builder`)
- **`performance`**: prioriza `claude-opus-5-5` em `deep` (gate `claude.opus < 80`), `antigravity` `gemini-4-neon-xhigh` em `research`/`review`, `claude-sonnet-5-5` `high` em `code`, com fallbacks em `codex` (default) e `antigravity` `gemini-4-hydrogen-xhigh`.

---

## 7. Fluxo Completo e Trilha de Auditoria

1. **Passo 0 — Coleta Dinâmica, Classificação e Roteamento Inicial:**
   - Resolver `<ORQ_HANDLE>` via `orca terminal show --json`.
   - Executar `bash <caminho-da-skill>/scripts/get-quotas.sh` para obter `INSTALLED_AGENTS` e `QUOTA`/`BUCKET`.
   - Classificar o requisito em `effortClass` (`light | standard | deep`) e resolver Planner, Executor e Reviewer pelo preset ativo (`balanced` por padrão), filtrando contra `INSTALLED_AGENTS`.
   - **Sem perguntar sobre agentes/modelos**, exibir resumo compacto da decisão e seguir direto ao Passo 1.
2. **Passo 1 — Despacho do Planner (TUI obrigatória):**
   - Abrir com `orca agent launch --agent <id> --worktree active [--model <model> [--effort <effort>]] --surface terminal --focus --json`, aguardar `tui-idle`, injetar prompt `superpowers:brainstorming` + `superpowers:writing-plans` + contrato de notificação.
   - Aguardar `ETAPA planner CONCLUÍDA`.
3. **Passo 2 — Gate Obrigatório de Aprovação Humana (Única pergunta do fluxo normal):**
   - Apresentar resumo da arquitetura, tarefas/arquivos impactados e o bloco de **Trilha de Auditoria** do Planner + alocação prevista para Executor e Reviewer.
   - Perguntar explicitamente se aprova iniciar a implementação. **Nunca** despachar Executor sem confirmação afirmativa.
4. **Passo 3 — Despacho do Executor (TUI obrigatória):**
   - Reexecutar `bash <caminho-da-skill>/scripts/get-quotas.sh` para atualizar cotas após o gate; recalcular o papel do Executor se necessário.
   - Abrir com `orca agent launch ... --surface terminal --focus --json`, aguardar `tui-idle`, injetar prompt `superpowers:executing-plans` (TDD estrito, commits atômicos, checkboxes `[x]`, aviso ao `<ORQ_HANDLE>`).
   - Aguardar `ETAPA executor CONCLUÍDA` e conferir `[x]`.
5. **Passo 4 — Despacho do Reviewer (TUI obrigatória):**
   - Reexecutar `bash <caminho-da-skill>/scripts/get-quotas.sh`, resolver Reviewer aplicando guarda `readOnly` e regra de independência de vendor frente ao Executor real.
   - Abrir com `orca agent launch ... --surface terminal --focus --json`, aguardar `tui-idle`, injetar prompt `superpowers:requesting-code-review` + `superpowers:verification-before-completion` + bloco `## Trilha de Auditoria de Roteamento` para persistência no relatório `docs/superpowers/reviews/YYYY-MM-DD-<feature>-review.md`.
   - Aguardar `ETAPA reviewer CONCLUÍDA`.
6. **Passo 5 — Consolidação e Relatório Final:**
   - Exibir veredito, saída dos testes reais do Reviewer, caminho do relatório e a **Trilha de Auditoria de Roteamento** completa (`rule:<id>`, `role:<papel>`, `agent:<id>`, `model:<id>`, `fallback:<de→para> por cota`, agentes instalados e cotas lidas em cada decisão, sem PII).

---

## 8. Estratégia de Verificação e TDD (Bash Puro + Fixtures Sem PII)

Suíte única em **bash puro** (`bash tests/test-orchestration-auto.sh`), sem `bats`, `jq`, `python`, `node` nem PowerShell, executável de forma idêntica em **macOS, Linux e Windows (Git Bash)**:

1. **Fixtures sem PII (`tests/fixtures/agent-installed.json` e `tests/fixtures/account-list.json`):** reproduzem a estrutura real do Orca com e-mails, UUIDs e caminhos de home removidos.
2. **Um assert por comportamento de extração em `scripts/get-quotas.sh`:**
   - Sintaxe `bash -n` válida + zero chamadas a `python`/`node`/`jq`/`pwsh`/`powershell`.
   - Extração dos agentes instalados (`claude` default, `codex`, `opencode`, `opencode2`, `antigravity`, `copilot`).
   - Janela 5h e semanal do `claude` (`5` / `66`, pior `weekly`, plano `pro`).
   - Janela 5h e semanal do `codex` (`0` / `74`, pior `weekly`, plano `plus`).
   - Janelas 5h/semanal + os 4 `buckets[]` do `antigravity` (`Gemini Models` 300m=12% e 10080m=6%; `Claude and GPT models` 300m=0% e 10080m=0%).
   - Provedores `unavailable` (`gemini`, `kimi`, `opencodeGo`) reportados como indisponíveis (nunca críticos).
   - Zero PII ou segredos nas fixtures e na saída do script.
3. **Verificações estruturais da skill e documentação:**
   - Frontmatter YAML, seções obrigatórias, contrato `orca agent installed` / `orca account list` / `orca agent launch --surface terminal --focus` / `tui-idle` / `ETAPA ... CONCLUÍDA`, fallback `curl`, ausência de comandos/caminhos Windows-only ou `python`/`jq`/`powershell` dentro da skill.
   - Integridade dos 3 presets JSON em `SKILL.md` (chaves balanceadas, todo `role` de regra existe em `roles`, guarda `readOnly` nos fallbacks, nenhum modelo inventado).
   - `orca-superpowers-orchestration-auto/README.md` e `README.md` da raiz atualizados com os **5 destinos** de instalação.
