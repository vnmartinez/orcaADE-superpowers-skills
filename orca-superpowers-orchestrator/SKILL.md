---
name: orca-superpowers-orchestrator
description: Use when orchestrating an end-to-end development cycle in Orca ADE where a dedicated orchestrator agent dispatches planner, executor, and reviewer agents across terminal sessions
---

# Orca Superpowers Orchestrator

## Overview

Coordena o ciclo completo de desenvolvimento dentro do **Orca ADE**, operando no mesmo workspace/branch ativo através de um **Agente Orquestrador Central**. 

Diferente do handoff em cadeia simples, o Orquestrador atua estritamente como **hub supervisor e despachante**: ele não escreve código de produção, não redige especificações e não faz code review diretamente. Ele gerencia o fluxo em 3 processos distintos acionados via **Orca CLI**:

1. **Processo 1: Planejador (Planner):** Executa `superpowers:brainstorming` e `superpowers:writing-plans` sob `ponytail` nível `ultra`, para gerar a spec técnica e o plano com checkboxes no menor escopo que resolve o requisito.
2. **Processo 2: Executor (Executor):** Assume após o gate de aprovação humana, executando o plano via `superpowers:executing-plans` sob `ponytail` nível `full`, com TDD estrito, menor diff e commits atômicos.
3. **Processo 3: Revisor (Reviewer):** Audita a suíte de testes e o `git diff` via `superpowers:requesting-code-review` e `superpowers:verification-before-completion`.

```
┌────────────────────────────────────────────────────────────────────────┐
│               Mesmo Workspace / Worktree Ativo no Orca                 │
│                                                                        │
│                      [AGENTE ORQUESTRADOR]                             │
│   (Pergunta ao usuário a ordem/distribuição dos 4 agentes:             │
│    Claude Code, Codex, AGY, OpenCode)                                  │
│                                │                                       │
│    1. orca terminal create     ▼                                       │
│       ┌────────────────────────────────────────────────┐               │
│       │ [Processo 1: PLANNER (ex: Claude Code)]        │               │
│       │ Executa: brainstorming+writing-plans+ponytail  │               │
│       │ Produz: docs/superpowers/specs/ & plans/       │               │
│       └──────────────────────┬─────────────────────────┘               │
│                              ▼                                         │
│    2. GATE DE APROVAÇÃO: Orquestrador valida plano com usuário         │
│                              │                                         │
│    3. orca terminal create   ▼                                         │
│       ┌────────────────────────────────────────────────┐               │
│       │ [Processo 2: EXECUTOR (ex: Codex)]             │               │
│       │ Executa: executing-plans (TDD+ponytail)        │               │
│       │ Marca checkboxes [x] no plano                  │               │
│       └──────────────────────┬─────────────────────────┘               │
│                              ▼                                         │
│    4. orca terminal create   ▼                                         │
│       ┌────────────────────────────────────────────────┐               │
│       │ [Processo 3: REVIEWER (ex: AGY / OpenCode)]    │               │
│       │ Executa: requesting-code-review + testes reais │               │
│       │ Produz: docs/superpowers/reviews/ ou aprovação │               │
│       └──────────────────────┬─────────────────────────┘               │
│                              ▼                                         │
│    5. Orquestrador consolida resultado e reporta ao usuário            │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Agentes Suportados e Matriz de Invocação

O Orquestrador suporta qualquer permutação dos 4 agentes instalados no sistema. **Abrir a TUI interativa é OBRIGATÓRIO em toda etapa** — todo agente nasce como TUI visível (`--focus`), e não existe fallback para modo não-interativo (`-p`/`exec`/`run`): se a TUI não abrir, o fluxo é interrompido e o usuário é avisado, jamais se recorre ao modo batch. O prompt é injetado depois, via `orca terminal send`, apenas após a TUI confirmar pronta (`tui-idle`):

O modelo faz parte da invocação (`--model <modelo>` no Claude Code, `-m <modelo>` no Codex). As sugestões de modelo desta skill são apenas sugestões: o usuário define o modelo de cada etapa, inclusive nenhum (default do CLI). Modelos muito fracos (ex.: `haiku`, modelos free) costumam pular etapas de protocolo — avise uma vez, mas siga a escolha do usuário.

| Agente | CLI | Comando de Abertura Interativa (via Orca CLI) |
|---|---|---|
| **Claude Code** | `claude` | `claude --dangerously-skip-permissions` (acrescente `--model <modelo>` só quando o usuário escolher modelo diferente do default) |
| **Codex CLI** | `codex` | `codex --dangerously-bypass-approvals-and-sandbox` |
| **Antigravity CLI** | `agy` | `agy --dangerously-skip-permissions` |
| **OpenCode CLI** | `opencode` | `opencode` |

Padrão de injeção do prompt em qualquer passo:

```bash
orca terminal create --worktree active --title "<titulo>" --focus --command "<AGENTE_INTERATIVO>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json   # só envie se satisfied: true
# satisfied: false → repita o wait uma vez com timeout maior; ainda assim false → PARE e avise o usuário (nunca use -p/exec/run)
orca terminal send --terminal <handle> --text "<PROMPT>" --enter --json
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

## Ponytail no Planejamento e na Execução

[Ponytail](https://github.com/DietrichGebert/ponytail) é o modo "dev sênior preguiçoso": a menor mudança que resolve a tarefa **inteira**, sem abstração, opção, wrapper ou código "para depois" que ninguém pediu. Nesta família de skills ele é ligado **só nas fases de planejamento e execução** — o Reviewer audita sem ele, para não ter viés de economia ao julgar o próprio critério.

| Fase | Nível | Motivo |
|---|---|---|
| Planner (Passo 1) | `ultra` | Além das regras, questiona o requisito antes de especificar: corta escopo caro onde a alavanca é maior (spec e plano) |
| Executor (Passo 3) | `full` | Menor diff que cumpre o plano já aprovado, sem rediscutir o que passou pelo gate humano |

Instalação no CLI de cada papel (os 4 agentes suportados têm adapter oficial):

| Agente | Instalação |
|---|---|
| Claude Code | `/plugin marketplace add DietrichGebert/ponytail` e, em prompt separado, `/plugin install ponytail@ponytail` |
| Codex | `codex plugin marketplace add DietrichGebert/ponytail` + `codex plugin add ponytail@ponytail` |
| Antigravity CLI | `agy plugin install https://github.com/DietrichGebert/ponytail` |
| OpenCode | `opencode plugin add @dietrichgebert/ponytail` |

- **Nível vai sempre escrito no prompt injetado**, nunca só via `/ponytail <nível>`: Antigravity não tem hooks de ciclo de vida e não persiste nível entre turnos.
- **Fallback obrigatório:** se o ponytail não estiver instalado no CLI daquele papel, o ciclo **não para**. O agente aplica o princípio declarado no próprio prompt (menor solução completa, zero abstração não pedida) e registra no aviso de conclusão que rodou sem a skill.
- **Trava anti-atalho:** ponytail encurta a *solução*, nunca o *acabamento* da mudança. Ele jamais autoriza pular TDD, o teste de cada tarefa do plano, validação em fronteira de confiança, tratamento de erro, segurança, acessibilidade ou qualquer item pedido pelo usuário.

---

## Quando Usar

- Ao iniciar o desenvolvimento de features, refatorações ou correções complexas no Orca ADE.
- Quando se deseja supervisão centralizada por um agente neutro sem poluir o contexto com código ou arquivos de implementação.
- Quando o usuário deseja alternar papéis entre Claude, Codex, AGY e OpenCode (ex: Codex planejando, OpenCode executando, AGY revisando).

### Quando NÃO Usar
- Para tarefas atômicas triviais de um único arquivo (use diretamente um agente no terminal).
- Em ambientes fora do Orca ADE onde a CLI `orca` não está disponível.

---

## Protocolo Operacional do Orquestrador

### Passo 0: Coleta de Requisito e Alocação dos Papéis

O Orquestrador recebe o requisito inicial e pergunta ao usuário qual agente executará cada papel (ou adota a sugestão se o usuário confirmar):

#### Descoberta de Modelos (sempre pergunte ao usuário)

Rode no seu próprio terminal e inclua o resultado na pergunta ao usuário:

| Agente | Como descobrir o modelo atual |
|---|---|
| OpenCode | `opencode models` (lista os modelos disponíveis; sem provider pago só aparecem os free) |
| Claude Code | campo `model` de `%USERPROFILE%\.claude\settings.json` |
| Codex | campos `model` e `model_reasoning_effort` de `%USERPROFILE%\.codex\config.toml` |
| Antigravity | modelo default do vendor (Gemini); CLI não expõe flag de modelo — registre como "default" |

Apresente tudo numa tabela `| Agente | CLI | Modelo atual | Observação |` e faça a pergunta dupla, com a matriz como sugestão:

> *"Qual agente e qual modelo assumem cada papel? Sugestão: Planner=Codex (gpt-6-luna), Executor=Claude Code (--model sonnet), Reviewer=Antigravity (Gemini default). Confirma ou troca?"*

Regras:
- Se o usuário trocar o modelo, injete o flag correspondente na invocação daquela etapa (`claude --model <modelo>`, `codex -m <modelo>`). Se o CLI não aceitar flag de modelo, avise antes de seguir.
- Se o modelo listado for fraco para o papel (ex.: `haiku`, ou modelo free do OpenCode em Planner/Reviewer/Executor), avise **uma vez** e sugira troca; a decisão é do usuário e vale sem insistir.
- Sem a descoberta rodada e sem o usuário responder, não avance ao Passo 1 — mas aceite qualquer resposta: ele pode aceitar o default, trocar, indicar agente/modelo fora da lista, ou recusar a sugestão.
- Na mesma pergunta, confirme o **ponytail** nas fases de planejamento e execução (Planner `ultra`, Executor `full` — ver "Ponytail no Planejamento e na Execução"). Não instalado, ou recusado pelo usuário: siga com o fallback declarado no prompt e não bloqueie o ciclo.

> **Sugestão Padrão Recomendada:**
> - **Orquestrador:** Claude Code `claude --dangerously-skip-permissions --model sonnet`
> - **Planner:** Codex (`codex`, gpt-6-luna, reasoning medium)
> - **Executor:** Claude Code `claude --dangerously-skip-permissions --model sonnet` (alternativa: Codex)
> - **Reviewer:** Antigravity (`agy --dangerously-skip-permissions`, Gemini default — vendor independente do Executor)
> Tudo acima é sugestão: pergunte e deixe o usuário confirmar ou redefinir papéis e modelos. Se algum agente ou modelo sugerido não existir na máquina, diga o que existe e pergunte quem assume cada papel.

Se o usuário desejar ordem personalizada (ex.: Planner=OpenCode, Executor=Claude Code, Reviewer=Codex), o Orquestrador parametriza as variáveis de execução:
- `$PLANNER_CLI`
- `$EXECUTOR_CLI`
- `$REVIEWER_CLI`

#### Identificação do Orquestrador (obrigatória antes do Passo 1)

Cada agente precisa saber **para quem** avisar a conclusão. Antes de disparar qualquer etapa, o Orquestrador resolve o próprio handle de terminal e o injeta em todos os prompts como `<ORQ_HANDLE>`:

```bash
orca terminal show --json        # sem --terminal = terminal ativo = o do orquestrador → campo "handle"
```

Se `terminal show` falhar (orquestrador fora de um terminal Orca), não siga: o aviso via CLI não teria destino. Informe o usuário e pare.

**Contrato de notificação (vale para Planner, Executor e Reviewer):** o agente só é considerado concluído quando envia, do próprio terminal, exatamente:

```bash
orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA <planner|executor|reviewer> CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: <caminho-do-plano ou ->" --enter --json
```

`<ORQ_HANDLE>` é substituído pelo handle real no momento da injeção do prompt. A mensagem chega automaticamente como entrada na sessão do Orquestrador; o aviso é obrigatório mesmo em caso de falha (`status: FALHA`).

---

### Passo 1: Disparo do Processo de Planejamento (Planner)

O Orquestrador não cria o plano diretamente. Ele cria uma aba no Orca para o Planner:

```bash
# TUI obrigatória: --focus + agente interativo; sem tui-idle satisfied não há Passo 1
orca terminal create --worktree active --title "1-Planner" --focus --command "<PLANNER_CLI>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
# satisfied: false → repita o wait com timeout maior; ainda false → PARE e avise o usuário (proibido recorrer a modo não-interativo)
orca terminal send --terminal <handle> --text "<TEMPLATE_DO_PROMPT_ABAIXO>" --enter --json
```

#### Template de Prompt injetado no Planner:
```text
Use as skills superpowers:brainstorming, superpowers:writing-plans e ponytail no nível ultra (/ponytail ultra).
Se a skill ponytail não estiver instalada neste CLI, aplique o princípio na mão e diga isso no aviso final: menor solução que resolve o requisito inteiro, sem feature, opção, abstração ou "para depois" que ninguém pediu.
REQUISITO DO USUÁRIO:
<REQUISITO_INICIAL>

DIRETRIZES:
1. Explore a arquitetura e elabore a especificação técnica em docs/superpowers/specs/YYYY-MM-DD-<feature>-design.md.
2. Antes de escolher a solução, percorra as opções do ponytail na ordem: já existe no repo (helper, componente, serviço, padrão) > biblioteca padrão ou recurso da plataforma > dependência já instalada > código novo mínimo. Nunca adicione dependência por poucas linhas.
3. Escreva o plano de tarefas executável com TDD em docs/superpowers/plans/YYYY-MM-DD-<feature>.md com checkboxes '- [ ]' e testes explícitos por tarefa.
4. Encerre a spec com duas seções de uma linha cada: "Deixado de fora" (o que o requisito não justifica) e "Risco conhecido".
5. O corte de escopo nunca atinge: teste de cada tarefa, validação em fronteira de confiança, tratamento de erro, segurança, acessibilidade ou qualquer coisa que o usuário pediu explicitamente.
6. Ao concluir a criação dos dois arquivos e comitá-los, avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA planner CONCLUÍDA | status: OK | resumo: <3 frases> | plano: docs/superpowers/plans/<nome>.md" --enter --json
7. Só depois do envio, encerre a execução.
```

O Orquestrador aguarda a notificação do Planner chegar ao seu terminal (a mensagem injetada entra como nova entrada na sessão dele) e confere a geração do arquivo em `docs/superpowers/plans/`. Se não houver aviso em 10 minutos, leia o terminal do Planner (`orca terminal read --terminal <handle_planner> --json`) antes de qualquer conclusão — ausência de aviso nunca conta como conclusão.

---

### Passo 2: Gate Obrigatório de Aprovação Humana

Assim que o plano é gerado:
1. O Orquestrador localiza o plano mais recente em `docs/superpowers/plans/`.
2. Apresenta ao usuário:
   - Resumo da arquitetura proposta.
   - Lista resumida de tarefas e arquivos impactados.
3. **Pausa obrigatória**: O Orquestrador pergunta explicitamente ao usuário:
   > *"O plano foi elaborado em `docs/superpowers/plans/<nome>.md`. Deseja aprovar o início da implementação pelo Executor (`<EXECUTOR_CLI>`)?"*
4. **NUNCA** dispare o Executor antes da confirmação afirmativa do usuário ("Sim", "Aprovado", etc.).

---

### Passo 3: Disparo do Processo de Implementação (Executor)

Após aprovação humana, o Orquestrador abre uma nova aba para o Executor:

```bash
# TUI obrigatória: --focus + agente interativo; sem tui-idle satisfied não há Passo 3
orca terminal create --worktree active --title "2-Executor" --focus --command "<EXECUTOR_CLI>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
# satisfied: false → repita o wait com timeout maior; ainda false → PARE e avise o usuário (proibido recorrer a modo não-interativo)
orca terminal send --terminal <handle> --text "<TEMPLATE_DO_PROMPT_ABAIXO>" --enter --json
```

#### Template de Prompt injetado no Executor:
```text
Use a skill superpowers:executing-plans e a skill ponytail no nível full (/ponytail full).
Se a skill ponytail não estiver instalada neste CLI, aplique o princípio na mão e diga isso no aviso final: menor diff que cumpre a tarefa inteira.
Consulte o plano em docs/superpowers/plans/<NOME_DO_PLANO>.md.

REGRAS RÍGIDAS DE EXECUÇÃO:
1. Execute cada tarefa do plano estritamente em TDD (escreva o teste, veja falhar, implemente o código, veja passar).
2. Menor diff que cumpre a tarefa inteira: reuse o helper, componente ou padrão que já existe no repo, mantenha as camadas e convenções atuais e não crie abstração, wrapper, flag, config ou código "para depois" que o plano não pediu. Deleção vale mais que adição.
3. Preguiça é na solução, nunca na mudança: termine tudo que a tarefa alcança (chamadores, testes, fixtures que seu diff quebrar) e nunca corte validação, tratamento de erro, segurança, acessibilidade ou item do plano. Atalho com limite conhecido leva comentário no código no formato: shortcut: <o limite>, <quando revisar>.
4. Faça commit atômico por tarefa no formato: git commit -m "feat/fix: <resumo>".
5. Atualize o arquivo do plano marcando a checkbox correspondente com '- [x]'.
6. Divergiu do plano para fazer menos código? Não decida sozinho: registre a divergência no aviso de conclusão para o orquestrador levar ao usuário.
7. Ao concluir todas as tarefas e garantir que a suíte de testes passa, avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA executor CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: <caminho-do-plano>" --enter --json
8. Só depois do envio, encerre.
```

O Orquestrador aguarda o aviso do Executor no seu terminal e confere que todas as checkboxes principais do plano estão marcadas com `[x]`. Se não houver aviso em 10 minutos, leia o terminal do Executor antes de qualquer conclusão.

---

### Passo 4: Disparo do Processo de Auditoria (Reviewer)

Com a implementação concluída e commitada, o Orquestrador aciona o Revisor:

```bash
# TUI obrigatória: --focus + agente interativo; sem tui-idle satisfied não há Passo 4
orca terminal create --worktree active --title "3-Reviewer" --focus --command "<REVIEWER_CLI>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
# satisfied: false → repita o wait com timeout maior; ainda false → PARE e avise o usuário (proibido recorrer a modo não-interativo)
orca terminal send --terminal <handle> --text "<TEMPLATE_DO_PROMPT_ABAIXO>" --enter --json
```

#### Template de Prompt injetado no Revisor:
```text
Use as skills superpowers:requesting-code-review e superpowers:verification-before-completion.
Avalie o git diff da branch contra a spec em docs/superpowers/specs/ e o plano em docs/superpowers/plans/<NOME_DO_PLANO>.md.

REQUISITOS DA AUDITORIA:
1. Execute a suíte de testes automatizados do projeto e colete a saída real.
2. Inspecione a qualidade de código, padrões de projeto e possíveis regressões.
3. Se houver falhas críticas ou importantes: salve o relatório em docs/superpowers/reviews/YYYY-MM-DD-<feature>-review.md e detalhe os problemas.
4. Se aprovado: emita o relatório final de aprovação ('Ready to merge').
5. Em ambos os casos, avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA reviewer CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | plano: <caminho-do-relatorio-ou->" --enter --json
6. Só depois do envio, encerre.
```

O Orquestrador aguarda o aviso do Reviewer no seu terminal antes de consolidar. Se não houver aviso em 10 minutos, leia o terminal do Reviewer antes de qualquer conclusão.

---

### Passo 5: Consolidação e Encerramento pelo Orquestrador

O Orquestrador só consolida após receber o aviso do Reviewer (`ETAPA reviewer CONCLUÍDA`) no seu terminal — aviso é a prova de conclusão, não a ausência de output. Depois do aviso:
- **Se Aprovado:** Notifica o usuário com o resumo dos testes bem-sucedidos e instrução para merge da branch.
- **Se Reprovado / Pendências:** Aponta ao usuário o relatório gerado em `docs/superpowers/reviews/` e oferece a opção de reacionar o Executor para corrigir as pendências.

---

## Comandos Úteis do Orca ADE

```bash
# Handle do próprio orquestrador (destino dos avisos de conclusão) — rodar ANTES do Passo 1
orca terminal show --json

# Consultar worktree atual
orca worktree current --json

# Criar aba de terminal com a TUI do agente — OBRIGATÓRIO: sempre interativo e com --focus
orca terminal create --worktree active --title "<titulo>" --focus --command "<agente-interativo>" --json

# Aguardar a TUI do agente ficar pronta antes de enviar o prompt (obrigatório)
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json

# Injetar o prompt no agente interativo
orca terminal send --terminal <handle> --text "<prompt>" --enter --json

# Listar terminais abertos
orca terminal list --worktree active --json

# Inspecionar saída de um terminal específico
orca terminal read --terminal <handle> --limit 50 --json

# Aguardar encerramento de um terminal
orca terminal wait --terminal <handle> --for exit --timeout-ms 300000 --json
```

---

## Red Flags - Erros Críticos

- **NUNCA execute código ou testes no agente Orquestrador:** o orquestrador apenas despacha os processos dedicados via Orca CLI.
- **NUNCA dispare o Executor sem aprovação humana expressa do plano gerado pelo Planner.**
- **NUNCA permita que o Executor pule a marcação das checkboxes no plano:** o Orquestrador depende do plano para validar a conclusão antes de chamar o Reviewer.
- **NUNCA considere o Review concluído sem a execução dos comandos reais de teste do projeto.**
- **NUNCA crie novos worktrees separados para cada agente:** todos os agentes devem operar no mesmo worktree ativo (`--worktree active`).
- **TUI é OBRIGATÓRIA em 100% das etapas:** todo `terminal create` de agente usa comando interativo + `--focus` + `wait --for tui-idle` antes do envio do prompt. **NUNCA** exista fallback para `-p`/`exec`/`run`: se a TUI não abrir (duas tentativas de `tui-idle` com `satisfied: false`), interrompa o fluxo e avise o usuário.
- **NUNCA avance de etapa sem o aviso explícito do agente:** toda injeção de prompt deve conter o `<ORQ_HANDLE>` real e o comando de notificação; sem `ETAPA <nome> CONCLUÍDA` no terminal do Orquestrador, a etapa está indeterminada — leia o terminal do agente antes de decidir.
- **NUNCA se esqueça de resolver o handle do orquestrador (`orca terminal show`) antes do Passo 1:** sem ele os agentes não têm destino para o aviso.
- **NUNCA aceite o ponytail como desculpa para pular teste, validação, segurança ou item do plano:** ele encurta a solução, não o acabamento da mudança. Diff menor com tarefa inacabada é `status: FALHA`.
- **NUNCA ligue o ponytail no Reviewer (Passo 4):** quem audita não pode julgar com o mesmo viés de economia de quem planejou e executou.
- **NUNCA trave o ciclo porque o ponytail não está instalado no CLI do papel:** os templates já declaram o princípio como fallback; siga e registre no aviso.
