---
name: orca-superpowers-handoff
description: Use when orchestrating a sequential multi-agent task in Orca ADE across Claude Code, Codex, and AGY with Superpowers planning, implementation via executing-plans, and code review
---

# Orca Superpowers Handoff

## Overview

Coordena o ciclo de desenvolvimento sequencial de uma funcionalidade dentro do **Orca ADE**, operando no mesmo workspace/branch ativo. O fluxo distribui papéis especializados entre três agentes de IA através de abas de terminal criadas via Orca CLI e skills do Superpowers:

1. **Claude Code (Planner):** Elabora spec e plano detalhado com `superpowers:brainstorming` e `superpowers:writing-plans` sob `ponytail` nível `ultra`; **pausa obrigatoriamente** para aprovação do usuário.
2. **Codex (Executor):** Assume após a aprovação humana, executando as tarefas do plano via `superpowers:executing-plans` sob `ponytail` nível `full`, com TDD estrito e menor diff.
3. **AGY (Reviewer):** Audita a suíte de testes e o git diff seguindo `superpowers:requesting-code-review`, **sem ponytail** (quem audita não julga com o mesmo viés de economia); aprova ou documenta falhas em relatório de review.

Antes de propor a cadeia, rode a Descoberta de Modelos do orca-superpowers-orchestrator (Passo 0) e inclua o modelo de cada salto na proposta enviada ao usuário. Confirme também o ponytail nas fases de planejamento e execução — instalação por agente, níveis, fallback e trava anti-atalho estão em "Ponytail no Planejamento e na Execução" naquela skill.

```
┌────────────────────────────────────────────────────────────────────────┐
│               Mesmo Workspace / Worktree Ativo no Orca                 │
│                                                                        │
│  [1. Claude Code: Planner]                                             │
│       │  Injeta: Requisito inicial do usuário                          │
│       │  Executa: brainstorming + writing-plans + ponytail (ultra)     │
│       │  Produz: docs/superpowers/specs/ e plans/<data>-<feature>.md   │
│       │          (incluindo a Task Final de chamada do AGY)            │
│       ▼                                                                │
│  [PAUSA DE APROVAÇÃO HUMANA] ◄── Claude pergunta ao usuário se aprova  │
│       ▼ (Somente após "Sim")                                           │
│    Handoff via `orca terminal create`                                  │
│       ▼                                                                │
│  [2. Codex: Executor]                                                  │
│       │  Consome: docs/superpowers/plans/<data>-<feature>.md           │
│       │  Executa: executing-plans + ponytail full (TDD, menor diff)    │
│       │  Executa: Task Final do plano (chama AGY via Orca CLI)         │
│       │  Atualiza: Checkboxes [x] no plano                             │
│       ▼                                                                │
│    Handoff via `orca terminal create`                                  │
│       ▼                                                                │
│  [3. AGY: Reviewer]                                                    │
│       │  Consome: git diff + plano + suíte de testes                   │
│       │  Executa: superpowers:requesting-code-review                   │
│       └─ Resultado:                                                    │
│            ├─ Aprovado: Relatório de sucesso no terminal               │
│            └─ Falhas: Cria docs/superpowers/reviews/ e pausa           │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Matriz Agente ↔ Modelo por Papel

Sugestão de pareamento agente↔modelo por papel — **não é regra nem lista fechada**. O usuário pode definir qualquer combinação, inclusive agentes ou modelos não listados; se não tiver o agente/modelo instalado, ou simplesmente não quiser usar, escolha outro. Pergunte sempre e confirme antes do Passo 1 — nunca troque papel ou modelo sozinho.

| Papel | Agente + modelo | Motivo |
|---|---|---|
| Orquestrador | Claude Code `--model sonnet` (evite `haiku`) | Só despacha: exige obediência de protocolo (handle, `tui-idle`, avisos `ETAPA ... CONCLUÍDA`), não raciocínio caro |
| Planner | Codex (`gpt-6-luna`, reasoning medium) | Spec + plano são o artefato de maior alavanca do ciclo |
| Executor | Claude Code `claude --model sonnet` (alternativa: Codex) | Melhor laço editar → teste → commit atômico |
| Reviewer | Antigravity (`agy`, default Gemini) | Contexto longo sobre diff + spec e vendor independente do Executor: não aprova o próprio trabalho |
| Handoff em cadeia | rotaciona o agente não usado a cada salto | Independência por salto pesa mais que força bruta |

- OpenCode nesta máquina só expõe modelo free (sem provider pago configurado): sugestão é usá-lo como Orquestrador ou em handoff; como Reviewer costuma ser fraco — avise uma vez e siga a escolha do usuário.
- Se o CLI escolhido não subir a TUI em 2 tentativas de `tui-idle`, avise o usuário e pergunte qual agente usar em seguida; nunca recua para `-p`/`exec`/`run`.

---

## Como Iniciar o Fluxo (Prompt Inicial)

No Orca ADE, abra uma aba de terminal com o **Claude Code** (no workspace do projeto) e envie a instrução com o requisito inicial:

```text
Use a skill orca-superpowers-handoff.

REQUISITO INICIAL:
<Descreva detalhadamente o que precisa ser feito>
```

---

## Protocolo Detalhado por Etapa

### Etapa 1: Claude Code (Planejador)
* **Responsabilidade:** Transformar o requisito inicial em especificação técnica e plano de tarefas executável, no menor escopo que resolve o requisito inteiro.
* **Superpowers requeridos:** `brainstorming` e `writing-plans`.
* **Skill requerida:** `ponytail` no nível `ultra` (`/ponytail ultra`) — questiona o requisito antes de especificar. Antes de escolher a solução, percorra a ordem do ponytail: já existe no repo > biblioteca padrão/plataforma > dependência já instalada > código novo mínimo. Sem a skill instalada no CLI, aplique o princípio na mão e registre isso na spec.
* **Entregáveis:**
  - `docs/superpowers/specs/YYYY-MM-DD-<feature>-design.md`, encerrada com duas seções de uma linha: "Deixado de fora" e "Risco conhecido"
  - `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` (com seções de contexto, checkboxes `- [ ]` e testes explícitos).
* **O corte de escopo nunca atinge:** teste de cada tarefa, validação em fronteira de confiança, tratamento de erro, segurança, acessibilidade ou qualquer coisa que o usuário pediu explicitamente.
* **Regra Obrigatória do Plano (Task Final Embutida no Plano):**
  Como o Codex é estritamente orientado pelas checkboxes do plano, o Claude **DEVE OBRIGATORIAMENTE** incluir como última tarefa do plano a etapa de disparo do AGY:

  ````markdown
  ### Task Final: Acionar Code Review no AGY via Orca CLI

  - [ ] **Step 1: Disparar o AGY no Orca ADE**

  Execute os comandos abaixo para abrir a TUI do AGY e injetar a auditoria (TUI interativa é obrigatória; nunca use `-p`):

  ```bash
  # 1. Abre a TUI interativa do AGY
  orca terminal create --worktree active --title "3-AGY-Review" --focus --command "agy --dangerously-skip-permissions" --json
  # 2. Aguarda a TUI confirmar pronta (repita uma vez se satisfied: false; ainda false → PARE e avise o usuário)
  orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
  # 3. Só então injeta o prompt da auditoria
  orca terminal send --terminal <handle> --text "Use o protocolo de code review do Superpowers (superpowers:requesting-code-review). Avalie o git diff da branch contra o plano em docs/superpowers/plans/<nome-do-plano>.md e a spec em docs/superpowers/specs/. Execute a suíte de testes do projeto e produza a auditoria nos moldes do template (Strengths, Issues: Critical/Important/Minor, Recommendations, Assessment: Ready to merge / With fixes). Se houver pendências, salve em docs/superpowers/reviews/ e pause; se aprovado, emita o resumo no terminal." --enter --json
  ```
  ````

* **Gate Obrigatório de Aprovação Humana:**
  Ao finalizar e commitar a documentação, o Claude **NÃO** abre o Codex imediatamente. Ele apresenta o resumo do plano no terminal e pergunta explicitamente ao usuário:
  > *"O plano foi salvo em `docs/superpowers/plans/<nome>.md`. Posso abrir a aba do Codex no Orca para iniciar a implementação?"*
* **Comando de Handoff (após o usuário responder "Sim"):**
  O Claude abre uma nova aba com a TUI interativa do Codex no mesmo workspace e injeta o prompt (TUI é obrigatória; nunca use `exec`):

  ```bash
  # 1. Abre a TUI interativa do Codex
  orca terminal create --worktree active --title "2-Codex-Exec" --focus --command "codex --dangerously-bypass-approvals-and-sandbox" --json
  # 2. Aguarda a TUI confirmar pronta (repita uma vez se satisfied: false; ainda false → PARE e avise o usuário)
  orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
  # 3. Só então injeta o prompt do plano
  orca terminal send --terminal <handle> --text "Use a skill superpowers:executing-plans e a skill ponytail no nível full (/ponytail full); sem a skill instalada, aplique o princípio na mão e diga isso no fim. Leia o plano em docs/superpowers/plans/<nome-do-plano>.md, revise criticamente, execute cada tarefa em TDD estrito com commits atômicos e atualize as checkboxes. Menor diff que cumpre cada tarefa: reuse helper, componente e padrão que já existem no repo e não crie abstração, wrapper, flag ou código 'para depois' que o plano não pediu — isso nunca reduz TDD, validação, segurança nem item do plano. Ao concluir a implementação, execute a Task Final do plano para acionar o AGY via Orca CLI conforme a skill orca-superpowers-handoff." --enter --json
  ```

---

### Etapa 2: Codex (Executor)
* **Responsabilidade:** Implementar o código e testes previstos no plano, sem atalhos.
* **Superpower obrigatório:** `superpowers:executing-plans`.
* **Skill requerida:** `ponytail` no nível `full` (`/ponytail full`) — menor diff que cumpre o plano aprovado. Sem a skill instalada no CLI, aplique o princípio na mão e registre isso no fechamento da etapa.
* **Regras de Execução:**
  1. Carregar e ler o plano mais recente em `docs/superpowers/plans/`.
  2. Executar cada tarefa individualmente:
     - Escrever o teste automatizado correspondente antes do código.
     - Executar o teste e certificar-se de que falhou pelo motivo esperado.
     - Escrever o código mínimo de produção para fazê-lo passar: reuse o que já existe no repo, mantenha camadas e convenções atuais e não crie abstração, wrapper, flag, config ou código "para depois" que o plano não pediu.
     - Preguiça é na solução, nunca na mudança: termine chamadores, testes e fixtures que o diff quebrar, e jamais corte validação, tratamento de erro, segurança, acessibilidade ou item do plano. Atalho com limite conhecido leva comentário `shortcut: <o limite>, <quando revisar>`.
     - Executar a suíte de testes e garantir aprovação.
     - Fazer commit da tarefa: `git commit -m "feat/fix: <resumo da tarefa>"`.
     - Marcar a tarefa no documento de plano com `- [x]`.
  3. **Execução da Task Final (Handoff para o AGY):**
     Ao concluir todas as tarefas de código e testes, o Codex **deve executar a Task Final descrita no plano**, disparando o comando do Orca para abrir a aba do AGY e marcando a respectiva checkbox `- [x]`.

---

### Etapa 3: AGY (Revisor)
* **Responsabilidade:** Auditoria rigorosa de qualidade, execução de testes e encerramento do ciclo.
* **Superpowers requeridos:** `superpowers:requesting-code-review` e `superpowers:verification-before-completion`.
* **Checklist de Auditoria:**
  1. Executar o comando real da suíte de testes do projeto (ex.: `npm test`, `pytest`, `cargo test`, etc.).
  2. Executar linter/verificação estática se disponível.
  3. Inspecionar `git diff` contra a branch base para verificar conformidade com a arquitetura definida na spec.
* **Desfecho do Review:**
  * **Cenário A (Aprovado):**
    - Todos os testes passaram e o diff cumpre integralmente o plano.
    - O AGY imprime no terminal o resumo de aprovação (`Ready to merge`) e instruções finais.
  * **Cenário B (Falhas encontradas):**
    - Salvar o relatório estruturado em `docs/superpowers/reviews/YYYY-MM-DD-<feature>-review.md` com as seções:
      - `### Strengths`
      - `### Issues (Critical / Important / Minor)` com referências `arquivo:linha`
      - `### Recommendations`
      - `### Assessment`
    - Imprimir alerta claro no terminal com a lista de pendências e **pausar para intervenção do usuário**.

---

## Comandos Úteis do Orca ADE

| Ação | Comando Orca CLI |
|---|---|
| Obter workspace atual | `orca worktree current --json` |
| Abrir aba (TUI interativa) no workspace atual | `orca terminal create --worktree active --title "<titulo>" --focus --command "<agente-interativo>" --json` |
| Aguardar TUI pronta antes do prompt | `orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json` |
| Enviar comando a terminal | `orca terminal send --terminal <handle> --text "<texto>" --enter --json` |
| Aguardar encerramento | `orca terminal wait --terminal <handle> --for exit --timeout-ms <ms>` |

---

## Red Flags - Erros Comuns

- **NUNCA** gerar o plano sem a `Task Final` de acionamento do AGY embutida no próprio documento markdown.
- **NUNCA** abrir o Codex sem aprovação expressa do usuário sobre o plano gerado pelo Claude.
- **NUNCA** criar worktrees secundários separados para esse fluxo; a flag `--worktree active` deve ser sempre usada para manter o trabalho no mesmo diretório local.
- **NUNCA** permitir que o Codex comite código sem os testes automatizados descritos em cada tarefa do plano.
- **NUNCA** aceitar o ponytail como desculpa para pular teste, validação, segurança ou item do plano: ele encurta a solução, não o acabamento da mudança.
- **NUNCA** ligar o ponytail no AGY (Etapa 3): quem audita não julga com o mesmo viés de economia de quem planejou e executou.
- **NUNCA** aprovar o review no AGY baseado apenas em leitura visual de código: a suíte real de testes deve ser executada obrigatoriamente.
- **NUNCA** despachar nenhum dos 4 agentes (Claude Code, Codex, AGY, OpenCode) em modo não-interativo: todo agente nasce como TUI interativa (`--focus` + `wait --for tui-idle`), e o prompt é injetado depois via `terminal send`. Sem TUI (duas tentativas de `satisfied: false`), interrompa e avise o usuário; jamais recaia em `-p`/`exec`/`run`.
