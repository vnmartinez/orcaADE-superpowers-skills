---
name: orca-superpowers-orchestration-auto
description: Use when orchestrating an end-to-end development cycle in Orca ADE with automatic agent and model selection from installed Orca agents and real quota usage, avoiding manual allocation prompts
---

# Orca Superpowers Orchestration Auto

## Overview

Coordena o ciclo completo de desenvolvimento dentro do **Orca ADE** no mesmo worktree ativo (`--worktree active`), mantendo o mesmo fluxo auditável do `orca-superpowers-orchestrator` (**Planner → Gate humano do plano → Executor → Reviewer → Consolidação**), mas com **seleção automática, determinística e agent-agnostic** de agente e modelo baseada nos agentes instalados e nas cotas reais do sistema.

- O orquestrador **nunca pergunta ao usuário qual agente ou modelo** executa Planner, Executor ou Reviewer.
- O **único gate humano** no fluxo padrão é a aprovação do plano gerado pelo Planner (Passo 2).
- Toda abertura de agente usa **TUI interativa obrigatória** via `orca agent launch ... --surface terminal --focus --json`, sem modo não-interativo (`-p`, `exec`, `run`).

```text
┌────────────────────────────────────────────────────────────────────────┐
│               Mesmo Workspace / Worktree Ativo no Orca                 │
│                                                                        │
│                      [AGENTE ORQUESTRADOR]                             │
│   Passo 0: get-quotas.sh (orca agent installed + orca account list)    │
│            Classifica effortClass + Resolve Planner/Executor/Reviewer  │
│            (SEM perguntar agente/modelo ao humano)                     │
│                                │                                       │
│    1. orca agent launch        ▼                                       │
│       ┌────────────────────────────────────────────────┐               │
│       │ [Processo 1: PLANNER]                          │               │
│       │ Executa: brainstorming + writing-plans         │               │
│       │ Envia: ETAPA planner CONCLUÍDA                │               │
│       └──────────────────────┬─────────────────────────┘               │
│                              ▼                                         │
│    2. GATE HUMANO ÚNICO: Orquestrador valida plano com usuário         │
│                              │                                         │
│    3. Revalida cotas + launch▼                                         │
│       ┌────────────────────────────────────────────────┐               │
│       │ [Processo 2: EXECUTOR]                         │               │
│       │ Executa: executing-plans (TDD estrito)         │               │
│       │ Marca checkboxes [x] no plano                  │               │
│       │ Envia: ETAPA executor CONCLUÍDA               │               │
│       └──────────────────────┬─────────────────────────┘               │
│                              ▼                                         │
│    4. Revalida cotas + vendor▼ independente                            │
│       ┌────────────────────────────────────────────────┐               │
│       │ [Processo 3: REVIEWER (readOnly)]              │               │
│       │ Executa: requesting-code-review + testes reais │               │
│       │ Persiste: ## Trilha de Auditoria de Roteamento │               │
│       │ Envia: ETAPA reviewer CONCLUÍDA               │               │
│       └──────────────────────┬─────────────────────────┘               │
│                              ▼                                         │
│    5. Consolidação final + Trilha de Auditoria completa                │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Descoberta Dinâmica de Agentes e Modelos

### Agentes instalados (fonte de verdade)

Em tempo de execução (Passo 0), o orquestrador descobre os agentes disponíveis executando `scripts/get-quotas.sh`, que consulta:

```bash
orca agent installed --worktree active --json
```

Regras rígidas de portabilidade:
- Nunca fixar uma lista fechada de CLIs.
- Cada `id` retornado por `orca agent installed --worktree active --json` é um candidato válido para `orca agent launch --agent <id>`.
- Se um papel ou seu `fallback` apontar para um agente ausente de `INSTALLED_AGENTS`, ele não pode ser despachado: o resolvedor escolhe o próximo agente instalado compatível e registra o desvio na trilha de auditoria.
- Um agente instalado que nenhum papel referencia simplesmente permanece fora do roteamento, sem erro.
- Nunca inventar `id` de agente nem `id` de modelo.

### Comando de abertura de agente (decisão arquitetural)

- **Caminho principal:**
  ```bash
  orca agent launch --agent <id> --worktree active [--model <id> [--effort <level>]] --surface terminal --focus --json
  ```
  Escolhido por ser **nativamente agent-agnostic** (aceita qualquer `id` retornado por `orca agent installed` sem mapear flags específicas de cada CLI) e manter o contrato de TUI interativa (`--surface terminal --focus`).
- **Regra obrigatória de `--effort`:** `--effort` exige `--model`. Quando o papel definir `"model": null` (default configurado no agente), omita **ambos** `--model` e `--effort`.
- **Alternativa documentada:** `orca terminal create --worktree active --title "<titulo>" --focus --command "<cli>" --json` fica reservado apenas para quando o usuário exigir flags específicas de CLI não expostas pelo `orca agent launch`.

### Descoberta de modelos por agente

- **Antigravity (`antigravity`):** `agy models` lista os modelos reais disponíveis no host:
  - `gemini-4-neon-low`, `gemini-4-neon-medium`, `gemini-4-neon-high`, `gemini-4-neon-xhigh`
  - `gemini-4-carbon-low`, `gemini-4-carbon-medium`, `gemini-4-carbon-high`
  - `gemini-4-argon-low`, `gemini-4-argon-medium`, `gemini-4-argon-high`
  - `gemini-4-hydrogen-low`, `gemini-4-hydrogen-medium`, `gemini-4-hydrogen-high`, `gemini-4-hydrogen-xhigh`
  - `gemini-pro-orchestrator`, `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator-argon`
  - `gemini-3.8-flash-low`, `gemini-3.8-flash-medium`, `gemini-3.8-flash-high`
  - `claude-opus-5-5-low`, `claude-opus-5-5-medium`, `claude-opus-5-5-high`
  - `claude-sonnet-5-5-low`, `claude-sonnet-5-5-medium`, `claude-sonnet-5-5-high`
  - `gpt-oss-120b-medium`
- **Claude (`claude`):** modelos/aliases configurados (`claude-sonnet-5-5`, `claude-opus-5-5`, `haiku`, ou `null` para default).
- **Codex (`codex`), OpenCode (`opencode`, `opencode2`), Copilot (`copilot`) e demais agentes sem listagem unificada:** usar `"model": null` e `"effort": null` (default do próprio agente, omitindo `--model` e `--effort`).

---

## Quando Usar

- Ao iniciar features, refatorações ou correções multi-arquivo no Orca ADE querendo seleção automática do melhor agente/modelo conforme as cotas atuais e sem perguntas manuais de alocação.
- Quando houver múltiplos agentes instalados e se quiser proteger cotas críticas (fallback automático) e garantir independência de vendor no Reviewer.

### Quando NÃO Usar

- Quando o usuário quiser escolher manualmente os agentes/modelos passo a passo (use `orca-superpowers-orchestrator`).
- Para ajustes triviais em um único arquivo que não exigem ciclo completo Planner → Executor → Reviewer.
- Em malha de correção após review reprovado (use `orca-superpowers-review-loop`) ou finalização/merge (use `orca-superpowers-merge`).

---

## Medição Real de Cotas

### Invocação cross-platform (bash / Git Bash)

- **macOS, Linux e Windows (Git Bash no `PATH`):**
  ```bash
  bash <caminho-da-skill>/scripts/get-quotas.sh
  ```
- **Windows (quando `bash` não estiver no `PATH`):**
  ```text
  "C:\Program Files\Git\bin\bash.exe" <caminho-da-skill>/scripts/get-quotas.sh
  ```

O coletor usa exclusivamente bash + utilitários POSIX do Git (`awk`, `sed`, `grep`, `tr`, `cut`, `curl`), sem dependências externas.

### Fonte principal: `orca account list --json` (`result.rateLimits`)

O comando `orca account list --json` é a fonte primária, cross-platform e agent-agnostic. O script lê dinamicamente todas as entradas de provedores dentro de `result.rateLimits` (como `claude`, `codex`, `antigravity`, `gemini`, `kimi`, `grok`, `cursor`, `muse`, `minimax`, `zcode`, `opencodeGo`):

- Mapeamento `agent.id` ↔ chave em `result.rateLimits`: match exato primeiro (`claude`, `codex`, `antigravity`, `gemini`, `kimi`, `cursor`, etc.) e alias conhecido `opencode`/`opencode2` ↔ `opencodeGo`.
- `antigravity` expõe também `buckets[]` (`Gemini Models` e `Claude and GPT models` em janelas `300` min = 5h e `10080` min = 7d).
- Provedor sem entrada (ex.: `copilot`) ou com `status: unavailable` **nunca é crítico** e nunca bloqueia o roteamento.

### Formato de saída do coletor

```text
SOURCE|orca
INSTALLED|claude|default
INSTALLED|codex|
INSTALLED|antigravity|
QUOTA|claude|ok|5|66|weekly|66|pro
QUOTA|codex|ok|0|74|weekly|74|plus
QUOTA|antigravity|ok|12|6|session|12|-
BUCKET|antigravity|Gemini Models|10080|6
BUCKET|antigravity|Gemini Models|300|12
BUCKET|antigravity|Claude and GPT models|10080|0
BUCKET|antigravity|Claude and GPT models|300|0
QUOTA|gemini|unavailable|-|-|-|-|-
```

Campos de `QUOTA`: `QUOTA|<provider>|<status>|<session_5h_pct>|<weekly_pct>|<worst_window>|<worst_pct>|<planType>`.
Campos de `BUCKET`: `BUCKET|<provider>|<group>|<windowMinutes>|<usedPercent>`.

### Fallback documentado via `curl`

Quando `orca` estiver ausente ou `orca account list --json` falhar (emitindo `SOURCE|direct-curl`), o script e o protocolo usam caminhos portáveis com `$HOME`:

- **Claude:** lê token de `$CLAUDE_OAUTH_TOKEN` ou `$HOME/.claude/.credentials.json` (`claudeAiOauth.accessToken`) e consulta:
  ```bash
  curl -sfS --max-time 10 -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" "https://api.anthropic.com/api/oauth/usage"
  ```
- **Codex:** lê credencial de `${CODEX_HOME:-$HOME/.codex}/auth.json` (caminho padrão `$HOME/.codex/auth.json`) e consulta:
  ```bash
  curl -sfS --max-time 10 -H "Authorization: Bearer $TOKEN" -H "User-Agent: orca-quota-check/1.0" "https://chatgpt.com/backend-api/wham/usage"
  ```
- **Antigravity:** quando houver token do keyring do SO (`security` no macOS ou `secret-tool` no Linux), consulta:
  ```bash
  curl -sfS --max-time 10 -X POST -H "Authorization: Bearer $TOKEN" -H "User-Agent: antigravity/1.0" -H "Content-Type: application/json" -d "{}" "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
  ```
  Quando o SO não expor o keyring em bash puro, degrada explicitamente para `status: unavailable` (não crítico).
- **Demais provedores:** `status: unavailable` (nunca críticos).

### Privacidade e segurança

Fixtures, saídas do script, logs e trilha de auditoria **nunca** imprimem nem gravam e-mails, UUIDs de organização, caminhos pessoais ou tokens de acesso.

---

## Motor Determinístico de Roteamento

### Modelo de dados

- **`kind`:** `research | code | review | command | docs | scrap`
- **`effortClass`:** `light | standard | deep`
- **`Role`:** `{ name, agent, model, effort, readOnly, timeoutSeconds, fallback, orchestrator }`
- **`QuotaGate`:** `{ agent, window, below }`
  - `"short"` → `session` (5h)
  - `"week"` → `weekly` (7d)
  - `"opus"` → janela semanal Opus do `claude` (fallback `weekly`)
  - Nome de grupo de bucket (ex.: `"Gemini Models"`, `"Claude and GPT models"`) → maior `usedPercent` do grupo em `BUCKET`
- **`RoutingRule`:** `{ id, enabled, kinds[], efforts[], gates[], role }`
- **`RoutingSettings`:**
  - `preset`: `"economy" | "balanced" | "performance" | "custom"` (padrão: `"balanced"`)
  - `criticalThreshold`: `0..100` (padrão: `80`)
  - `allowOpusOnDeep`: `true | false` (padrão: `true`)
  - `onBothCritical`: `"run-cheapest" | "ask" | "block"` (padrão na skill auto: `"run-cheapest"`, mantendo o gate do plano como única pergunta no fluxo padrão)

### Classificação da tarefa e mapeamento das 3 etapas

| `effortClass` | Critério objetivo |
|---|---|
| `light` | Ajuste localizado em 1–2 arquivos, correção pontual, documentação simples ou tarefa mecânica sem mudança arquitetural |
| `standard` | Nova feature ou refatoração localizada em múltiplos arquivos/módulos com TDD, seguindo padrões existentes |
| `deep` | Decisão arquitetural, novo protocolo/motor, concorrência, segurança, migração crítica ou mudança transversal |

Mapeamento por etapa:
1. **Planner:** `kind = "docs"` (se puramente documental) ou `kind = "research"` (padrão) + `effortClass`.
2. **Executor:** `kind = "docs"` (se entrega documental) ou `kind = "code"` (padrão; `"command"` para automação CLI pura) + `effortClass`.
3. **Reviewer:** `kind = "review"` + `effortClass`.

### Algoritmo de resolução (4 passos determinísticos)

Para cada etapa `(kind, effortClass)`:

1. **Avaliação top-down de regras filtrada por `INSTALLED_AGENTS`:**
   - Ignorar regra com `enabled == false`.
   - `kinds` deve ser vazio ou conter `kind`; `efforts` deve ser vazio ou conter `effortClass`.
   - Todos os `gates` devem passar: se a cota do `gate.agent` estiver ausente, com `status: unavailable` ou com janela `-`, o gate passa (`true`); caso contrário, exige `usedPercent < gate.below`.
   - Se `allowOpusOnDeep == false` e `role.model` contiver `opus`, pular regra.
   - Se `role.agent` estiver em `INSTALLED_AGENTS`, a regra vence (`rule:<id>`, `role:<name>`). Se não estiver instalado, tentar `role.fallback` (respeitando `readOnly`); se nenhum estiver instalado, seguir para a próxima regra. Se nenhuma regra casar com agente instalado, selecionar o primeiro agente de `INSTALLED_AGENTS` (priorizando o marcado `default`) e registrar o fallback na auditoria.
2. **Checagem de limiar crítico (`criticalThreshold`) e fallback de 1 nível:**
   - Um provedor é crítico **somente** se `status == "ok"` e `worst_pct >= criticalThreshold`. Provedor com `status: unavailable` ou sem entrada **nunca é crítico**.
   - Se o agente escolhido for crítico:
     - Tentar `role.fallback` (apenas 1 nível; proibido converter `readOnly: true` para `readOnly: false`).
     - Se `role.fallback` não estiver instalado ou também for crítico, procurar o próximo agente em `INSTALLED_AGENTS` não crítico compatível (omitindo `--model`/`--effort` quando não houver papel definido e preservando `readOnly: true` no Reviewer) e registrar `fallback:<de→para>`.
3. **Independência de vendor no Reviewer (Passo 4):**
   - Se o `agent` resolvido para o Reviewer for igual ao `agent` que executou o Executor, tentar `role.fallback` (desde que `readOnly: true`, instalado e não crítico) ou outro agente em `INSTALLED_AGENTS` diferente do Executor, registrando `vendor-independence`.
4. **Todos os provedores medidos críticos (`onBothCritical`):**
   - Considerar o conjunto `M` de provedores com `status == "ok"` dentre os agentes em `INSTALLED_AGENTS`.
   - Se `M` não é vazio e todos em `M` estão `>= criticalThreshold`:
     - `"run-cheapest"`: escolhe o papel/agente de menor `worst_pct` entre os instalados (preservando `readOnly` no Reviewer) e registra `all-critical: run-cheapest`.
     - `"ask"`: pausa e pergunta ao usuário se deseja prosseguir exibindo os percentuais atuais.
     - `"block"`: interrompe sem despachar e encerra com `status: FALHA`.

---

## Presets de Roteamento

```json
{
  "economy": {
    "description": "Prioriza modelos economicos do Antigravity e default do Codex; evita Opus",
    "roles": [
      {
        "name": "eco-scout",
        "agent": "antigravity",
        "model": "gemini-3.8-flash-medium",
        "effort": "low",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "eco-codex-ro",
        "orchestrator": null
      },
      {
        "name": "eco-planner",
        "agent": "antigravity",
        "model": "gemini-4-argon-medium",
        "effort": "medium",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "eco-codex-ro",
        "orchestrator": null
      },
      {
        "name": "eco-reviewer",
        "agent": "antigravity",
        "model": "gemini-4-carbon-medium",
        "effort": "medium",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "eco-codex-ro",
        "orchestrator": null
      },
      {
        "name": "eco-codex-ro",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "eco-planner",
        "orchestrator": null
      },
      {
        "name": "eco-builder",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "eco-ag-builder",
        "orchestrator": null
      },
      {
        "name": "eco-ag-builder",
        "agent": "antigravity",
        "model": "gemini-4-argon-medium",
        "effort": "medium",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "eco-builder",
        "orchestrator": null
      }
    ],
    "rules": [
      {
        "id": "eco-review",
        "enabled": true,
        "kinds": ["review"],
        "efforts": [],
        "gates": [],
        "role": "eco-reviewer"
      },
      {
        "id": "eco-light-ro",
        "enabled": true,
        "kinds": ["docs", "scrap", "research"],
        "efforts": ["light"],
        "gates": [],
        "role": "eco-scout"
      },
      {
        "id": "eco-research",
        "enabled": true,
        "kinds": ["research", "docs"],
        "efforts": ["standard", "deep"],
        "gates": [],
        "role": "eco-planner"
      },
      {
        "id": "eco-default",
        "enabled": true,
        "kinds": [],
        "efforts": [],
        "gates": [],
        "role": "eco-builder"
      }
    ]
  },
  "balanced": {
    "description": "Padrao recomendado: equilibra cota, custo e capacidade por kind e effortClass",
    "roles": [
      {
        "name": "scout",
        "agent": "antigravity",
        "model": "gemini-3.8-flash-high",
        "effort": "low",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "codex-reviewer",
        "orchestrator": null
      },
      {
        "name": "reviewer-antigravity",
        "agent": "antigravity",
        "model": "gemini-4-neon-high",
        "effort": "high",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "codex-reviewer",
        "orchestrator": null
      },
      {
        "name": "codex-reviewer",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "reviewer-antigravity",
        "orchestrator": null
      },
      {
        "name": "expert",
        "agent": "claude",
        "model": "claude-opus-5-5",
        "effort": "high",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "antigravity-planner",
        "orchestrator": null
      },
      {
        "name": "planner-std",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "antigravity-planner",
        "orchestrator": null
      },
      {
        "name": "antigravity-planner",
        "agent": "antigravity",
        "model": "gemini-4-neon-high",
        "effort": "high",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "planner-std",
        "orchestrator": null
      },
      {
        "name": "codex-builder",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "antigravity-builder",
        "orchestrator": null
      },
      {
        "name": "antigravity-builder",
        "agent": "antigravity",
        "model": "gemini-4-hydrogen-high",
        "effort": "high",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "codex-builder",
        "orchestrator": null
      },
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
    ],
    "rules": [
      {
        "id": "bal-light-ro",
        "enabled": true,
        "kinds": ["docs", "scrap", "research"],
        "efforts": ["light"],
        "gates": [],
        "role": "scout"
      },
      {
        "id": "bal-review",
        "enabled": true,
        "kinds": ["review"],
        "efforts": [],
        "gates": [],
        "role": "reviewer-antigravity"
      },
      {
        "id": "bal-deep-expert",
        "enabled": true,
        "kinds": ["code", "research", "command"],
        "efforts": ["deep"],
        "gates": [
          { "agent": "claude", "window": "week", "below": 75 },
          { "agent": "claude", "window": "opus", "below": 50 }
        ],
        "role": "expert"
      },
      {
        "id": "bal-planner",
        "enabled": true,
        "kinds": ["research", "docs"],
        "efforts": ["standard", "deep"],
        "gates": [],
        "role": "planner-std"
      },
      {
        "id": "bal-code-light",
        "enabled": true,
        "kinds": ["code", "command"],
        "efforts": ["light"],
        "gates": [],
        "role": "codex-builder"
      },
      {
        "id": "bal-default",
        "enabled": true,
        "kinds": [],
        "efforts": [],
        "gates": [],
        "role": "builder"
      }
    ]
  },
  "performance": {
    "description": "Prioriza maxima qualidade: Opus em deep, Neon XHigh em pesquisa/review e Sonnet High em codigo",
    "roles": [
      {
        "name": "perf-expert",
        "agent": "claude",
        "model": "claude-opus-5-5",
        "effort": "high",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "perf-ag-hydrogen",
        "orchestrator": null
      },
      {
        "name": "perf-research",
        "agent": "antigravity",
        "model": "gemini-4-neon-xhigh",
        "effort": "xhigh",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "perf-codex-ro",
        "orchestrator": null
      },
      {
        "name": "perf-reviewer",
        "agent": "antigravity",
        "model": "gemini-4-neon-xhigh",
        "effort": "xhigh",
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "perf-codex-ro",
        "orchestrator": null
      },
      {
        "name": "perf-codex-ro",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": true,
        "timeoutSeconds": null,
        "fallback": "perf-reviewer",
        "orchestrator": null
      },
      {
        "name": "perf-builder",
        "agent": "claude",
        "model": "claude-sonnet-5-5",
        "effort": "high",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "perf-codex-std",
        "orchestrator": null
      },
      {
        "name": "perf-codex-std",
        "agent": "codex",
        "model": null,
        "effort": null,
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "perf-ag-hydrogen",
        "orchestrator": null
      },
      {
        "name": "perf-ag-hydrogen",
        "agent": "antigravity",
        "model": "gemini-4-hydrogen-xhigh",
        "effort": "xhigh",
        "readOnly": false,
        "timeoutSeconds": null,
        "fallback": "perf-codex-std",
        "orchestrator": null
      }
    ],
    "rules": [
      {
        "id": "perf-review",
        "enabled": true,
        "kinds": ["review"],
        "efforts": [],
        "gates": [],
        "role": "perf-reviewer"
      },
      {
        "id": "perf-deep",
        "enabled": true,
        "kinds": ["code", "research", "command"],
        "efforts": ["deep"],
        "gates": [
          { "agent": "claude", "window": "opus", "below": 80 }
        ],
        "role": "perf-expert"
      },
      {
        "id": "perf-research-std",
        "enabled": true,
        "kinds": ["research", "docs", "scrap"],
        "efforts": [],
        "gates": [],
        "role": "perf-research"
      },
      {
        "id": "perf-default",
        "enabled": true,
        "kinds": [],
        "efforts": [],
        "gates": [],
        "role": "perf-builder"
      }
    ]
  }
}
```

---

## Protocolo Operacional do Orquestrador

### Passo 0: Coleta Dinâmica, Classificação e Roteamento Inicial

1. Resolver o handle do próprio orquestrador antes de qualquer despacho:
   ```bash
   orca terminal show --json
   ```
   Se falhar, interromper e avisar o usuário (os agentes não teriam destino para o aviso de conclusão).
2. Executar `bash <caminho-da-skill>/scripts/get-quotas.sh` para obter `INSTALLED_AGENTS` e `QUOTA`/`BUCKET`.
3. Classificar o requisito em `effortClass` (`light | standard | deep`) e resolver Planner, Executor e Reviewer pelo preset ativo (`balanced` por padrão), filtrando contra `INSTALLED_AGENTS`.
4. **Sem perguntar agente ou modelo ao usuário**, exibir resumo compacto da decisão e iniciar imediatamente o Passo 1.

### Passo 1: Disparo do Planejamento (Planner)

Abrir a TUI do agente escolhido para o Planner (omitindo `--model` e `--effort` se `model: null`):

```bash
orca agent launch --agent <PLANNER_AGENT> --worktree active [--model <PLANNER_MODEL> [--effort <PLANNER_EFFORT>]] --surface terminal --focus --json
orca terminal wait --terminal <handle_planner> --for tui-idle --timeout-ms 120000 --json
# satisfied: false -> repetir wait UMA vez com --timeout-ms 180000; ainda false -> PARAR e avisar o usuário
orca terminal send --terminal <handle_planner> --text "<PROMPT_PLANNER>" --enter --json
```

Para prompts longos com múltiplas linhas ou aspas internas, gravar em `${TMPDIR:-/tmp}/orca-prompt-planner.md` e enviar instrução curta sem aspas internas no `--text`.

#### Template de Prompt do Planner:
```text
Use as skills superpowers:brainstorming e superpowers:writing-plans.
REQUISITO DO USUÁRIO:
<REQUISITO_INICIAL>

DIRETRIZES:
1. Explore a arquitetura e elabore a especificação técnica em docs/superpowers/specs/YYYY-MM-DD-<feature>-design.md.
2. Escreva o plano de tarefas executável com TDD em docs/superpowers/plans/YYYY-MM-DD-<feature>.md com checkboxes '- [ ]' e testes explícitos por tarefa.
3. Ao concluir e comitar os arquivos, avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA planner CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: docs/superpowers/plans/<nome>.md" --enter --json
4. Só depois do envio, encerre.
```

Aguardar `ETAPA planner CONCLUÍDA` no terminal do orquestrador (se passar de 10 minutos sem aviso, ler com `orca terminal read --terminal <handle_planner> --limit 50 --json` antes de decidir).

### Passo 2: Gate Obrigatório de Aprovação Humana (Única pergunta do fluxo normal)

Assim que o Planner concluir:
1. Localizar o plano mais recente em `docs/superpowers/plans/`.
2. Apresentar ao usuário:
   - Resumo da arquitetura proposta e lista resumida de tarefas/arquivos impactados.
   - Bloco compacto da **Trilha de Auditoria** do Planner + alocação prevista para Executor e Reviewer.
3. Perguntar explicitamente:
   > *"O plano foi elaborado em `docs/superpowers/plans/<nome>.md`. Deseja aprovar o início da implementação pelo Executor (`<EXECUTOR_AGENT>` / `<EXECUTOR_MODEL>`)?"*
4. **NUNCA** despachar o Executor sem confirmação afirmativa do usuário.

### Passo 3: Disparo da Implementação (Executor)

1. Reexecutar `bash <caminho-da-skill>/scripts/get-quotas.sh` para atualizar cotas pós-gate e recalcular o Executor se necessário.
2. Abrir o Executor em TUI interativa obrigatória (`orca agent launch ... --surface terminal --focus --json`, `wait --for tui-idle`, `orca terminal send`).

#### Template de Prompt do Executor:
```text
Use a skill superpowers:executing-plans.
Consulte o plano em docs/superpowers/plans/<NOME_DO_PLANO>.md.

REGRAS RÍGIDAS DE EXECUÇÃO:
1. Execute cada tarefa do plano estritamente em TDD (escreva o teste, veja falhar, implemente o código, veja passar).
2. Faça commit atômico por tarefa no formato: git commit -m "feat/fix: <resumo>".
3. Atualize o arquivo do plano marcando cada checkbox concluída com '- [x]'.
4. Ao concluir todas as tarefas e garantir que a suíte de testes passa, avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA executor CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: <caminho-do-plano>" --enter --json
5. Só depois do envio, encerre.
```

Aguardar `ETAPA executor CONCLUÍDA` e confirmar que todas as checkboxes do plano estão `[x]`.

### Passo 4: Disparo da Auditoria (Reviewer)

1. Reexecutar `bash <caminho-da-skill>/scripts/get-quotas.sh`.
2. Resolver o Reviewer aplicando guarda `readOnly: true` e **independência de vendor** em relação ao `agent` que executou o Executor.
3. Abrir o Reviewer em TUI interativa obrigatória (`orca agent launch ... --surface terminal --focus --json`, `wait --for tui-idle`, `orca terminal send`).

#### Template de Prompt do Reviewer:
```text
Use as skills superpowers:requesting-code-review e superpowers:verification-before-completion.
Avalie o git diff da branch contra a spec em docs/superpowers/specs/ e o plano em docs/superpowers/plans/<NOME_DO_PLANO>.md.

REQUISITOS DA AUDITORIA:
1. Execute a suíte de testes automatizados do projeto e colete a saída real.
2. Inspecione qualidade de código, aderência à spec e possíveis regressões.
3. Salve o relatório em docs/superpowers/reviews/YYYY-MM-DD-<feature>-review.md contendo obrigatoriamente a seção "## Trilha de Auditoria de Roteamento" com o bloco abaixo:
<BLOCO_TRILHA_AUDITORIA>
4. Em qualquer veredito (aprovado ou reprovado), avise o orquestrador:
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA reviewer CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: docs/superpowers/reviews/<arquivo>.md" --enter --json
5. Só depois do envio, encerre.
```

Aguardar `ETAPA reviewer CONCLUÍDA`.

### Passo 5: Consolidação Final

Após receber `ETAPA reviewer CONCLUÍDA`:
- Apresentar veredito, saída real dos testes coletados pelo Reviewer, caminho do relatório e a **Trilha de Auditoria** completa.
- Se aprovado: sugerir `orca-superpowers-merge`. Se reprovado: sugerir `orca-superpowers-review-loop`.

---

## Trilha de Auditoria

Toda decisão de roteamento (Passos 0, 3 e 4) e o relatório do Reviewer (`## Trilha de Auditoria de Roteamento`) devem registrar, **sem PII e sem tokens**:

```text
preset: balanced | kind: <kind> | effortClass: <light|standard|deep> | source: <orca|direct-curl>
installed: <lista de agent ids retornados por orca agent installed>
quotas: claude(5h=5%, 7d=66%), codex(5h=0%, 7d=74%), antigravity(5h=12%, 7d=6%)
planner  -> rule:<id> | role:<nome> | agent:<id> | model:<id|default> | fallback:<de→para ou nenhum>
executor -> rule:<id> | role:<nome> | agent:<id> | model:<id|default> | fallback:<de→para ou nenhum>
reviewer -> rule:<id> | role:<nome> | agent:<id> | model:<id|default> | fallback:<de→para ou nenhum> | vendor-independence:<ok|fallback>
```

---

## Comandos Úteis do Orca ADE

```bash
# Handle do próprio orquestrador (rodar antes do Passo 1)
orca terminal show --json

# Agentes instalados e cotas reais
orca agent installed --worktree active --json
orca account list --json
bash <caminho-da-skill>/scripts/get-quotas.sh

# Abertura obrigatória em TUI interativa (agent-agnostic)
orca agent launch --agent <id> --worktree active [--model <id> [--effort <level>]] --surface terminal --focus --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
orca terminal send --terminal <handle> --text "<prompt>" --enter --json

# Inspeção e acompanhamento
orca terminal list --worktree active --json
orca terminal read --terminal <handle> --limit 50 --json
```

---

## Red Flags - Erros Críticos

- **NUNCA pergunte ao usuário qual agente ou modelo usar:** o objetivo central da skill é a seleção automática baseada em `orca agent installed` e `orca account list`.
- **NUNCA dispare o Executor sem aprovação humana do plano no Passo 2.**
- **NUNCA passe `--effort` sem `--model`:** no `orca agent launch`, `--effort` exige `--model`; quando `"model": null`, omita ambos.
- **NUNCA use modo não-interativo (`-p`, `--print`, `exec`, `run`):** se `tui-idle` falhar em duas tentativas, interrompa e avise o usuário.
- **NUNCA trate `status: unavailable` ou agente sem cota como crítico:** apenas provedores com `status: ok` e `worst_pct >= criticalThreshold` disparam fallback.
- **NUNCA permita que um papel `readOnly: true` faça fallback para `readOnly: false` no Reviewer.**
- **NUNCA crie worktrees separados por etapa:** todo o ciclo usa `--worktree active`.
- **NUNCA execute código, testes do projeto-alvo ou gravação de spec/plano diretamente no Orquestrador.**
- **NUNCA inclua e-mails, UUIDs ou tokens de autenticação em logs, fixtures ou relatórios.**
