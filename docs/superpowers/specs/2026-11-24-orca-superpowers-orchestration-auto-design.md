# Especificação Técnica — `orca-superpowers-orchestration-auto`

**Data:** 2026-11-24
**Repositório:** `orcaADE-superpowers-skills`
**Branch:** `main`
**Status:** Proposta (aguardando gate humano via orquestrador)

---

## 1. Objetivo e Escopo

Criar a skill **`orca-superpowers-orchestration-auto`** no repositório `orcaADE-superpowers-skills`, seguindo o mesmo padrão estrutural e operacional das skills existentes (`orca-superpowers-orchestrator`, `orca-superpowers-review-loop`, `orca-superpowers-merge`).

A skill entrega o mesmo ciclo ponta a ponta do `orca-superpowers-orchestrator` (**Planner → Gate humano do plano → Executor → Reviewer → Consolidação**) no mesmo worktree ativo do Orca ADE (`--worktree active`) com **TUI interativa obrigatória**, mas substitui a alocação manual de agentes por um **motor determinístico de roteamento orientado a tarefa e cota real**:

- **Zero perguntas de alocação:** o orquestrador nunca pergunta ao usuário qual agente ou modelo executa Planner, Executor ou Reviewer.
- **Único gate humano no fluxo normal:** aprovação do plano gerado pelo Planner (Passo 2). A única exceção configurável é o modo `onAllCritical: "ask"` quando todos os provedores com leitura válida ultrapassam o limiar crítico.
- **Medição real de cota antes da decisão:** coleta local e reexecutável em PowerShell 5.1+ (Windows-first) das janelas de uso (5 horas, semanal, Opus/modelo e buckets) de `claude`, `codex` e `agy`, tratando provedores sem leitura (`opencode` ou falhas de leitura) como **não críticos**.
- **Trilha de auditoria completa:** toda decisão registra `preset`, `kind`, `effortClass`, snapshot das cotas lidas, regra vencedora (`rule:<id>`), papel escolhido, eventuais fallbacks por cota ou independência de vendor, e modelo/esforço efetivamente despachados.

### Fora de Escopo

- Alterar o comportamento da skill manual `orca-superpowers-orchestrator` (que continua perguntando ao usuário).
- Criar daemon, serviço em background ou dependência externa (Node, Python, Rust) para o roteamento: tudo opera via Markdown + PowerShell nativo do Windows (`powershell -NoProfile -ExecutionPolicy Bypass -File`).
- Implementar malha de review reprovado ou merge automatizado (continuam delegados a `orca-superpowers-review-loop` e `orca-superpowers-merge`).

---

## 2. Estrutura de Arquivos

| Caminho | Responsabilidade |
|---|---|
| `orca-superpowers-orchestration-auto/SKILL.md` | Definição completa da skill (frontmatter YAML `name`/`description` em inglês no padrão da família; protocolo operacional em português, presets JSON, algoritmo de roteamento, comandos de cota, templates de prompt e Red Flags) |
| `orca-superpowers-orchestration-auto/README.md` | Resumo da skill no padrão das 3 skills existentes (`Conteúdo`, `Visão Geral`, `Garantias`) |
| `orca-superpowers-orchestration-auto/scripts/get-quotas.ps1` | Script PowerShell 5.1+ reexecutável (e *dot-sourceable* para testes unitários offline) que mede cotas reais de `claude`, `codex`, `agy` e reporta `opencode` como indisponível, devolvendo JSON normalizado sem jamais expor segredos |
| `tests/Test-OrchestrationAuto.ps1` | Suíte de verificação TDD em PowerShell 5.1+: testes unitários offline dos parsers de cota + normalização + validações estruturais/determinísticas de `SKILL.md`, `README.md`, presets JSON e `README.md` da raiz |
| `README.md` (raiz) | Adicionar `orca-superpowers-orchestration-auto` à tabela `## Skills` e atualizar o loop de instalação para incluir a nova skill e os **5 destinos** (`claude`, `gemini/superpowers`, `codex`, `agents`, `opencode`) |

---

## 3. Contrato Operacional no Orca ADE

Idêntico ao contrato duro das demais skills da família:

1. **Papel estrito do Orquestrador:** atua apenas como hub supervisor, medidor de cota e despachante. Nunca escreve código de produção, especificações, planos ou executa a suíte de testes do projeto-alvo.
2. **Worktree único:** todos os despachos usam `--worktree active`. Nunca criar worktrees separados por etapa.
3. **TUI interativa 100% obrigatória:**
   ```powershell
   orca terminal create --worktree active --title "<titulo>" --focus --command "<CLI_COM_MODELO>" --json
   orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
   # Se satisfied: false -> repetir wait UMA vez com timeout maior (ex.: 180000); ainda false -> PARAR e avisar o usuário
   orca terminal send --terminal <handle> --text "<PROMPT>" --enter --json
   ```
   **Proibido** qualquer fallback para modo não-interativo (`-p`, `--print`, `exec`, `run`).
4. **Identificação prévia do orquestrador (`<ORQ_HANDLE>`):** executar `orca terminal show --json` antes do Passo 1. Se falhar, interromper e avisar o usuário.
5. **Prova exclusiva de conclusão:** cada agente despachado só encerra após enviar ao `<ORQ_HANDLE>`:
   ```text
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA <planner|executor|reviewer> CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: <caminho-ou->" --enter --json
   ```
   Ausência de aviso nunca conta como conclusão; sem aviso em 10 minutos, ler o terminal do agente (`orca terminal read --terminal <handle> --limit 50 --json`) antes de decidir.
6. **Envio seguro de prompts em PowerShell:** evitar aspas duplas não escapadas dentro do `--text` ou gravar prompts longos em arquivo temporário e passar uma instrução curta no `--text` (ex.: `Leia o arquivo <caminho> e execute as instrucoes dele.`), prevenindo corrupção de payload pelo PowerShell.

---

## 4. Matriz de Invocação das CLIs Locais

Comandos verificados na máquina local (Windows) para abertura interativa com modelo e esforço explícitos:

| Agente (`agent`) | CLI | Comando interativo base | Flags de modelo e esforço |
|---|---|---|---|
| `claude` | `claude` | `claude --dangerously-skip-permissions` | `--model <model>` e `--effort <low\|medium\|high>` |
| `codex` | `codex` | `codex --dangerously-bypass-approvals-and-sandbox` | `-m <model>` (omitir quando `model: null` para usar default de `~/.codex/config.toml`) e `-c model_reasoning_effort="<effort>"` |
| `agy` | `agy` | `agy --dangerously-skip-permissions` | `--model <model>` e `--effort <low\|medium\|high\|xhigh\|max>` (quando aplicável além do sufixo do modelo) |
| `opencode` | `opencode` | `opencode` | Seleção de modelo conforme `opencode models` / configuração da sessão |

### Modelos reais disponíveis na máquina (usados nos presets e exemplos)

Obtidos localmente (`agy models`, `~/.claude/settings.json`, `~/.codex/config.toml`, `opencode models`):

- **Antigravity (`agy`):**
  - Família Gemini 4 Neon: `gemini-4-neon-low`, `gemini-4-neon-medium`, `gemini-4-neon-high`, `gemini-4-neon-xhigh`
  - Família Gemini 4 Carbon: `gemini-4-carbon-low`, `gemini-4-carbon-medium`, `gemini-4-carbon-high`
  - Família Gemini 4 Argon: `gemini-4-argon-low`, `gemini-4-argon-medium`, `gemini-4-argon-high`
  - Família Gemini 4 Hydrogen: `gemini-4-hydrogen-low`, `gemini-4-hydrogen-medium`, `gemini-4-hydrogen-high`, `gemini-4-hydrogen-xhigh`
  - Orquestradores: `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator`, `gemini-pro-orchestrator-argon`
  - Flash: `gemini-3.8-flash-low`, `gemini-3.8-flash-medium`, `gemini-3.8-flash-high`
  - Via Antigravity: `claude-opus-5-5-{low,medium,high}`, `claude-sonnet-5-5-{low,medium,high}`, `gpt-oss-120b-medium`
- **Claude Code (`claude`):** `claude-opus-5-5`, `claude-sonnet-5-5`, `haiku`
- **Codex (`codex`):** `null` (usa o default de `~/.codex/config.toml`, atualmente `gpt-6.2-sol`) ou nome explícito configurado
- **OpenCode (`opencode`):** modelos descobertos por `opencode models` (ex.: `opencode/deepseek-v4.1-flash-free`, `opencode/nemotron-3.5-super-vl-free`)

> **Nota sobre `readOnly: true`:** nos papéis de revisão, `readOnly: true` é uma garantia do contrato de papel (o Reviewer não altera código de produção, apenas executa a suíte de testes e grava o relatório em `docs/superpowers/reviews/`) e impede fallback para um papel com `readOnly: false`.

---

## 5. Medição Real de Cotas (Windows-first PowerShell)

Antes de resolver papéis (no Passo 0 e, opcionalmente, revalidando antes do Executor no Passo 3 e do Reviewer no Passo 4 quando houver pausa longa no gate humano), o orquestrador executa:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<CAMINHO_DA_SKILL>\scripts\get-quotas.ps1"
```

### 5.1 Fontes de Cota por Provedor

#### 1. Claude (`claude`)
- **Descoberta do token (somente leitura):**
  1. Variável de ambiente `$env:CLAUDE_OAUTH_TOKEN`.
  2. Arquivo `$env:USERPROFILE\.claude\.credentials.json` → `claudeAiOauth.accessToken` (até 3 tentativas com intervalo de 80 ms para tolerar escrita concorrente do CLI).
- **Requisição HTTP:**
  - `GET https://api.anthropic.com/api/oauth/usage`
  - Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
  - Timeout: 10 s.
- **Extração e normalização:**
  - `windows["5h"]` = `five_hour.utilization` (`resets_at`)
  - `windows["week"]` = `seven_day.utilization` (`resets_at`)
  - `windows["opus"]` = `seven_day_opus.utilization` (`resets_at`); se `seven_day_opus` for nulo/ausente, extrair de `limits[]` o item com `kind == "weekly_scoped"`, `scope.surface == null` e `scope.model.display_name` igual a `"opus"` (case-insensitive), campo `percent`.
  - Demais itens `weekly_scoped` sem `scope.surface` entram em `windows[<display_name_lowercase>]`.
  - `worst` = janela de maior utilização; `used = [math]::Round(worst.used)`; `rateLimited = false`.

#### 2. Codex (`codex`)
- **Descoberta do token (somente leitura — nunca rotacionar refresh token):**
  - `$env:CODEX_HOME\auth.json` (fallback `$env:USERPROFILE\.codex\auth.json`) → `tokens.access_token` e opcional `tokens.account_id`.
  - Se o login for por `OPENAI_API_KEY` sem `tokens.access_token`, retorna `status: "no_auth"`.
- **Requisição HTTP:**
  - `GET https://chatgpt.com/backend-api/wham/usage`
  - Headers: `Authorization: Bearer <token>`, `User-Agent: orca-quota-check/1.0`, e `ChatGPT-Account-Id: <account_id>` quando presente.
  - Timeout: 10 s.
- **Extração e normalização:**
  - `primary` = `rate_limit.primary_window` (`used_percent`, `limit_window_seconds / 60`, `reset_at * 1000`).
  - `secondary` = `rate_limit.secondary_window`.
  - **Normalização por duração (`by_duration`):** planos com cota exclusivamente semanal (ex.: Pro Lite) enviam a janela semanal em `primary_window`. Se `primary.window_minutes > 1440` e `secondary.window_minutes <= 1440`, inverter `(primary, secondary)` para que `windows["5h"]` seja sempre a janela curta e `windows["week"]` seja sempre a semanal.
  - `plan = plan_type`, `rateLimited = [bool]rate_limit.limit_reached`.
  - `worst` = maior entre `5h` e `week`; `used = [math]::Round(worst.used)`; `resetsAt` em ISO-8601 UTC (`null` se epoch 0).
  - **Fallback em HTTP 401 (documentado):** se o token estiver expirado, retornar `status: "no_auth"` por padrão (ou executar opcionalmente `codex app-server` com `account/rateLimits/read` via JSON-RPC para renovação segura pelo próprio CLI).

#### 3. Antigravity / Gemini (`agy`)
- **Descoberta do token (Windows Credential Manager, somente leitura):**
  - P/Invoke Win32 `advapi32.dll!CredRead` (`CRED_TYPE_GENERIC = 1`) sobre o alvo literal `"gemini:antigravity"`.
  - Decodifica o blob UTF-8 como JSON e lê `token.access_token`.
  - *(Nota cross-platform documentada: Linux Secret Service / macOS Keychain usam `service = "gemini"`, `account = "antigravity"`.)*
- **Requisição HTTP:**
  - `POST https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`
  - Body JSON: `{}`
  - Headers: `Authorization: Bearer <token>`, `User-Agent: orca-quota-check/1.0 antigravity-usage` (**obrigatório conter `antigravity` no `User-Agent`**; sem ele o endpoint responde HTTP 403 Forbidden — verificado empiricamente na máquina).
  - Timeout: 10 s.
  - Em caso de HTTP 401: acionar `agy models` uma única vez (timeout 12 s) para renovar a credencial no Credential Manager, reler o segredo e repetir o `POST` uma vez.
- **Extração e normalização (espelhando `antigravity_usage.rs`):**
  - Percorrer `body.models.*` com `quotaInfo.remainingFraction` numérico.
  - `normalized = clamp(remainingFraction, 0.0, 1.0)`; `fractionKey = [math]::Round($normalized * 1000000)`.
  - Agrupar modelos por chave `(fractionKey, resetTime)` em buckets.
  - Rótulo do bucket: `"Gemini"` se todos os modelos contêm `gemini`, `"Claude"` se todos contêm `claude`, `"GPT"` se todos contêm `gpt`, caso contrário o primeiro `displayName` (ordenado).
  - `remainingPercent = fractionKey / 10000.0`; `usedPercent = clamp(100.0 - remainingPercent, 0.0, 100.0)`.
  - Ordenar buckets por `usedPercent` decrescente, desempate por `label` crescente.
  - `worst` = rótulo do bucket mais consumido; `used = [math]::Round(maxUsed)`; `resetsAt` = `resetTime` do pior bucket; `rateLimited = (maxUsed >= 99.9)`.
  - `windows` expõe cada bucket por rótulo (ex.: `"Gemini"`, `"Claude"`) e o agregado `"short"` igual a `maxUsed` para interoperabilidade com gates genéricos.

#### 4. Provedores sem leitura de cota (`opencode` e estados de erro)
- **`opencode`:** não possui API de cota por janela; sempre retorna `status: "unavailable"`, `reason: "no_quota_api"`, `used: null`, `rateLimited: false`, `windows: {}`.
- **Qualquer falha em `claude`, `codex` ou `agy`** (CLI ausente → `no_cli`; credencial ausente/expirada → `no_auth`; timeout/rede/HTTP 5xx/JSON inválido → `unavailable`) retorna `status != "ready"`, `used: null`, `rateLimited: false`, `windows: {}` e `reason` descritivo (sem segredos).
- **Regra inegociável:** provedor sem leitura (`status != "ready"`) **nunca é considerado crítico** e **nunca falha um `QuotaGate`**.

### 5.2 Contrato de Saída JSON (`get-quotas.ps1`)

```json
{
  "collectedAt": "2026-11-24T23:55:00Z",
  "providers": {
    "claude": {
      "status": "ready",
      "worst": "week",
      "used": 66,
      "resetsAt": "2026-11-30T01:59:59Z",
      "rateLimited": false,
      "windows": { "5h": 5.0, "week": 66.0, "opus": 0.0 }
    },
    "codex": {
      "status": "ready",
      "plan": "plus",
      "worst": "week",
      "used": 74,
      "resetsAt": "2026-11-30T12:00:00Z",
      "rateLimited": false,
      "windows": { "5h": 0.0, "week": 74.0 }
    },
    "agy": {
      "status": "ready",
      "worst": "Gemini",
      "used": 6,
      "resetsAt": "2026-11-25T05:48:14Z",
      "rateLimited": false,
      "windows": { "Gemini": 6.5, "short": 6.5 },
      "buckets": [
        {
          "label": "Gemini",
          "usedPercent": 6.5,
          "remainingPercent": 93.5,
          "resetsAt": "2026-11-25T05:48:14Z",
          "models": ["Gemini 3 Flash"]
        }
      ]
    },
    "opencode": {
      "status": "unavailable",
      "reason": "no_quota_api",
      "worst": null,
      "used": null,
      "resetsAt": null,
      "rateLimited": false,
      "windows": {}
    }
  }
}
```

### 5.3 Invariante de Segurança

`get-quotas.ps1` e a skill **jamais** imprimem, registram em log ou gravam em relatórios qualquer token (`accessToken`, `access_token`, `refresh_token`, `Authorization`, `CLAUDE_OAUTH_TOKEN`, segredo bruto do Credential Manager). Mensagens de erro incluem apenas código HTTP ou categoria (`no_auth`, `http_401`, `http_403`, `timeout`, `parse_error`).

---

## 6. Motor Determinístico de Roteamento

Inspirado diretamente em `orchestrator_core.rs`, `routingPresets.ts` e `agentFitness.ts` do Alethe, adaptado ao ciclo Orca ADE.

### 6.1 Modelo de Dados

- **`kind`** (6 valores fixos): `research | code | review | command | docs | scrap`
- **`effortClass`** (3 valores fixos): `light | standard | deep`
- **`Role`**:
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
  { "agent": "claude", "window": "opus", "below": 50 }
  ```
  Mapeamento de `window`:
  - `"short"` → `"5h"` (em `claude` e `codex`) ou `"short"` (em `agy`)
  - `"week"` → `"week"`
  - `"opus"` → `"opus"` em `claude`; em `codex` (sem janela Opus), mapeia para `"week"`
  - Qualquer outro rótulo (ex.: `"Gemini"`, `"Claude"` em `agy`) → busca exata em `windows[window]`
- **`RoutingRule`**:
  ```json
  {
    "id": "bal-deep-opus",
    "enabled": true,
    "kinds": ["code", "research", "command"],
    "efforts": ["deep"],
    "gates": [
      { "agent": "claude", "window": "opus", "below": 50 },
      { "agent": "claude", "window": "week", "below": 75 }
    ],
    "role": "expert"
  }
  ```
- **`RoutingSettings`**:
  - `preset`: `"economy" | "balanced" | "performance" | "custom"` (padrão: **`"balanced"`**)
  - `criticalThreshold`: número `0..100` (padrão: **`80`**)
  - `allowOpusOnDeep`: booleano (padrão: **`true`**)
  - `onAllCritical`: `"run-cheapest" | "ask" | "block"` (padrão na skill auto: **`"run-cheapest"`**, garantindo zero interrupções fora do gate do plano; configurável pelo usuário no prompt inicial se quiser `"ask"` ou `"block"`)

### 6.2 Classificação da Tarefa e Mapeamento para o Ciclo de 3 Etapas

No Passo 0, o orquestrador classifica o requisito em `effortClass` usando heurística determinística documentada:

| `effortClass` | Critério objetivo |
|---|---|
| `light` | Ajuste localizado em 1–2 arquivos, correção pontual, documentação/README simples ou tarefa mecânica sem mudança arquitetural |
| `standard` | Nova feature ou refatoração localizada em múltiplos arquivos/módulos com TDD, seguindo padrões existentes do repo |
| `deep` | Decisão arquitetural, novo protocolo/motor, concorrência, segurança, migração crítica ou mudança transversal em vários subsistemas |

Cada etapa do ciclo invoca o resolvedor com seu `kind` fixo e o `effortClass` do requisito:

1. **Planner:** `kind = "docs"` (se requisito for puramente documental/markdown sem lógica) ou `kind = "research"` (padrão) + `effortClass` da tarefa.
2. **Executor:** `kind = "docs"` (se entrega for apenas documentação) ou `kind = "code"` (padrão; `"command"` se for automação/CLI pura) + `effortClass` da tarefa.
3. **Reviewer:** `kind = "review"` + `effortClass` da tarefa.

### 6.3 Algoritmo de Resolução (Passo a Passo Determinístico)

Para cada etapa `(kind, effortClass)`:

1. **Avaliação de regras (de cima para baixo):**
   - Ignorar regra com `enabled == false`.
   - `kinds` deve ser vazio **ou** conter `kind`.
   - `efforts` deve ser vazio **ou** conter `effortClass` (se `effortClass` for nulo, só casa regra com `efforts` vazio).
   - **Todos** os `gates` devem passar (`gate_passes`):
     - Se `providers[gate.agent]` ausente ou `status != "ready"` → **passa (`true`)**.
     - Buscar `used` em `windows[mappedWindow]` (ou `snapshot.used` se `snapshot.worst == mappedWindow`).
     - Se `used` ausente/nulo → **passa (`true`)**.
     - Caso contrário → passa se e somente se `used < gate.below`.
   - Resolver `role` em `roles`: preferir linha com `role.orchestrator == agenteAtualDoOrquestrador`; caso contrário, linha com `role.orchestrator == null`. Se não existir, pular regra.
   - Se `allowOpusOnDeep == false` e o papel usar modelo Opus (`model` contém `"opus"`, case-insensitive), pular regra.
   - **Primeira regra que passar vence.** Registrar `rule:<id>` e `role:<name>`.

2. **Checagem de limiar crítico e Fallback (máximo 1 nível):**
   - Um provedor é **crítico** (`past_threshold`) se e somente se `status == "ready"` **E** (`rateLimited == true` **OU** `used >= criticalThreshold`).
   - Se o provedor do papel escolhido **não** for crítico → manter papel escolhido.
   - Se for crítico **E** `role.fallback` estiver definido:
     - Localizar papel de fallback (mesma precedência de `orchestrator`, com `fallback.name != role.name`).
     - **Guarda `readOnly`:** se `role.readOnly == true` e `fallback.readOnly == false`, **não** aplicar fallback (proibido elevar leitura para escrita).
     - Se o provedor do fallback **não** for crítico → trocar para o fallback e registrar `fallback: <role> → <fallback> por cota (<agent> <worst>=<used>%)`.
     - Nunca encadear segundo nível (`fallback.fallback` é ignorado).

3. **Independência de vendor no Reviewer (Passo 4):**
   - Se, após os passos 1–2, o `agent` resolvido para o Reviewer for igual ao `agent` que executou o Executor **E** o papel do Reviewer tiver `fallback` com `readOnly == true`, `agent != executor.agent` e provedor não crítico → aplicar esse fallback e registrar `vendor-independence: <role> → <fallback> (Executor usou <agent>)`.

4. **Todos os provedores medidos críticos (`onAllCritical`):**
   - Considerar o conjunto `M` dos provedores com `status == "ready"` presentes nos papéis do preset (tipicamente `claude`, `codex`, `agy`).
   - Se `M` não é vazio **E** todo provedor em `M` está crítico (`past_threshold == true`):
     - `"run-cheapest"`: selecionar o papel mais econômico disponível (priorizando `agy` com `gemini-3.8-flash-medium` ou o provedor com menor `used%` entre os medidos, respeitando `readOnly` no Reviewer) e registrar `all-critical: run-cheapest`.
     - `"ask"`: pausar e perguntar ao usuário se deseja prosseguir mesmo com todos os provedores medidos acima de `criticalThreshold`, mostrando percentuais e `resetsAt`.
     - `"block"`: interromper imediatamente sem despachar, exibindo percentuais e `resetsAt`, e encerrar com `status: FALHA`.

### 6.4 Presets Embutidos (JSON válido e pronto para uso)

A skill traz 3 presets prontos (`economy`, `balanced` [default], `performance`), todos usando modelos reais verificados na máquina:

- **`economy`**: prioriza `agy` (`gemini-3.8-flash-medium`, `gemini-4-argon-medium`, `gemini-4-carbon-medium`) e `codex` (`low`/`medium`); sem Opus.
- **`balanced` (padrão)**:
  - `docs`/`scrap`/`research` `light` → `scout` (`agy` `gemini-3.8-flash-high`, `low`, fallback `codex-light`)
  - `review` → `reviewer-agy` (`agy` `gemini-4-neon-high`, `high`, `readOnly: true`, fallback `codex-reviewer` `readOnly: true`)
  - `code`/`research`/`command` `deep` com gates `claude.opus < 50` e `claude.week < 75` (e `allowOpusOnDeep: true`) → `expert` (`claude` `claude-opus-5-5`, `high`, fallback `agy-planner`)
  - `research`/`docs` `standard`/`deep` → `planner-std` (`codex` default, `medium`, fallback `agy-planner` `gemini-4-neon-high`)
  - `code`/`command` `light` → `codex-builder` (`codex` default, `medium`, fallback `agy-builder`)
  - Default → `builder` (`claude` `claude-sonnet-5-5`, `medium`, fallback `codex-builder`)
- **`performance`**: prioriza `claude-opus-5-5` em `deep` (gate `opus < 80`), `gemini-4-neon-xhigh` em `research`/`review`, `claude-sonnet-5-5` `high` em `code`, com fallbacks em `codex` `high` e `gemini-4-hydrogen-xhigh`.

---

## 7. Fluxo Completo e Trilha de Auditoria

1. **Passo 0 — Coleta de Cota, Classificação e Roteamento Inicial:**
   - Resolver `<ORQ_HANDLE>` via `orca terminal show --json`.
   - Rodar `get-quotas.ps1` e capturar o snapshot JSON.
   - Classificar o requisito em `effortClass` (`light | standard | deep`) e resolver os 3 papéis (Planner, Executor, Reviewer) pelo preset ativo (`balanced` por padrão, ou preset/overrides informados no pedido).
   - **Sem perguntar sobre agentes/modelos**, exibir resumo compacto da decisão e seguir direto ao Passo 1.
2. **Passo 1 — Despacho do Planner (TUI obrigatória):**
   - Abrir terminal `1-Planner` com o comando exato do papel resolvido (`agent` + `model` + `effort`), aguardar `tui-idle` e enviar prompt com `superpowers:brainstorming` + `superpowers:writing-plans` + contrato de notificação.
   - Aguardar `ETAPA planner CONCLUÍDA`.
3. **Passo 2 — Gate Obrigatório de Aprovação Humana (Única pergunta do fluxo normal):**
   - Apresentar ao usuário: resumo da arquitetura, tarefas/arquivos impactados e o bloco de **Trilha de Auditoria** do Planner + alocação prevista para Executor e Reviewer.
   - Perguntar explicitamente se aprova iniciar a implementação. **Nunca** despachar Executor sem confirmação afirmativa.
4. **Passo 3 — Despacho do Executor (TUI obrigatória):**
   - Reexecutar `get-quotas.ps1` para validar que as cotas não ficaram críticas durante a espera do gate; recalcular o papel do Executor se necessário (registrando eventual mudança na trilha).
   - Abrir terminal `2-Executor`, aguardar `tui-idle`, injetar prompt `superpowers:executing-plans` com TDD estrito, commits atômicos, marcação `[x]` e aviso ao `<ORQ_HANDLE>`.
   - Aguardar `ETAPA executor CONCLUÍDA` e confirmar checkboxes `[x]`.
5. **Passo 4 — Despacho do Reviewer (TUI obrigatória):**
   - Reexecutar `get-quotas.ps1`, resolver o papel do Reviewer (aplicando guarda `readOnly` e regra de independência de vendor frente ao Executor real).
   - Abrir terminal `3-Reviewer`, aguardar `tui-idle`, injetar prompt `superpowers:requesting-code-review` + `superpowers:verification-before-completion` + **bloco pronto de `## Trilha de Auditoria de Roteamento`** para o Reviewer persistir integralmente no relatório `docs/superpowers/reviews/YYYY-MM-DD-<feature>-review.md`.
   - Aguardar `ETAPA reviewer CONCLUÍDA`.
6. **Passo 5 — Consolidação e Relatório Final:**
   - Exibir ao usuário veredito, resumo dos testes reais executados pelo Reviewer, link do relatório e a **Trilha de Auditoria de Roteamento** completa:
     - Preset, `criticalThreshold`, `allowOpusOnDeep`, `onAllCritical`, `effortClass`.
     - Tabela por etapa (Planner / Executor / Reviewer): `kind`, regra vencedora (`rule:<id>`), papel inicial, fallback aplicado e motivo (ex.: `fallback: builder → codex-builder por cota (claude week=84%)`), agente/modelo/esforço final.
     - Cotas lidas em cada momento de decisão (`timestamp`, `claude 5h/week/opus`, `codex 5h/week/rateLimited`, `agy worst/buckets`, `opencode unavailable`).

---

## 8. Estratégia de Verificação e TDD

1. **Testes unitários offline do coletor de cotas (`tests/Test-OrchestrationAuto.ps1`):**
   - *Dot-source* das funções puras de `get-quotas.ps1` (`ConvertFrom-ClaudeUsage`, `ConvertFrom-CodexUsage`, `ConvertFrom-AntigravityUsage`, `New-UnavailableFitness`).
   - Casos obrigatórios:
     - Claude com `seven_day_opus` preenchido vs nulo com fallback em `limits[]` (`weekly_scoped`, ignorando limites com `scope.surface != null`).
     - Codex padrão (`5h` + `week`) + Codex Pro Lite (janela semanal chegando em `primary_window`, trocada por `by_duration`) + `limit_reached = true`.
     - Antigravity agrupando modelos de mesma `(remainingFraction, resetTime)` em buckets (`Gemini`, `Claude`), ordenação pelo pior bucket, `usedPercent = 100 - remaining*100`, `rateLimited = true` para `>= 99.9%`.
     - Provedores indisponíveis (`opencode`, `no_auth`, `no_cli`, `unavailable`) com `rateLimited = false`, `used = null` e `windows = {}`.
     - Invariante de segurança: execução do script com payloads simulados ou reais nunca contém strings de token na saída.
2. **Verificação estrutural e determinística das skills Markdown (`tests/Test-OrchestrationAuto.ps1`):**
   - Frontmatter YAML válido em `orca-superpowers-orchestration-auto/SKILL.md` (`name: orca-superpowers-orchestration-auto`, `description: Use when ...`).
   - Presença obrigatória de todas as seções: Overview, Matriz de Invocação, Medição Real de Cotas (Claude, Codex, Antigravity + User-Agent `antigravity`, indisponíveis), Motor Determinístico de Roteamento (`kind`, `effortClass`, `QuotaGate`, `fallback`, `readOnly`, `onAllCritical`), Presets (`economy`, `balanced`, `performance`), Protocolo Passo 0–5, Trilha de Auditoria e Red Flags.
   - Blocos JSON de presets e schema dentro de `SKILL.md` validados com `ConvertFrom-Json` (zero erro de sintaxe, todos os `role` referenciados pelas regras existem em `roles`, todo `fallback` de papel `readOnly: true` também tem `readOnly: true`, zero referência a modelos inexistentes).
   - Ausência de redação de pergunta de alocação manual (garantir que o Passo 0 explicite nunca perguntar agente/modelo) e presença explícita das proibições duras (TUI obrigatória, zero fallback `-p`/`exec`/`run`, gate humano obrigatório no Passo 2).
   - `orca-superpowers-orchestration-auto/README.md` existente com seções padrão.
   - `README.md` da raiz listando `orca-superpowers-orchestration-auto` na tabela e no `$skills`, com todos os **5 destinos** de instalação (`.claude`, `.gemini\config\plugins\superpowers`, `.codex`, `.agents`, `.config\opencode`).
