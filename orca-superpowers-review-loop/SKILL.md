---
name: orca-superpowers-review-loop
description: Use when a code review in Orca ADE came back rejected and the findings must be fixed and re-reviewed iteratively, with a hard iteration cap and a human escalation gate, across Orca terminal sessions
---

# Orca Superpowers Review Loop

## Overview

Fecha o ciclo de **reprovação de code review** no **Orca ADE**: em vez de terminar apontando pendências (Passo 5 do `orca-superpowers-orchestrator`), a malha despacha um **Executor de correção** e um **Reviewer** em turnos alternados até a aprovação, com **limite rígido de 3 iterações** e escala obrigatória ao usuário.

Opera no **mesmo worktree ativo** (`--worktree active`), com o mesmo contrato das demais skills desta família:

- **TUI interativa OBRIGATÓRIA** em 100% dos despachos (`--focus` + `terminal wait --for tui-idle`), sem qualquer fallback para `-p`/`exec`/`run`.
- **Aviso de conclusão é a única prova de fim de etapa**: `ETAPA <fixer|reviewer> CONCLUÍDA | status: <OK|FALHA> | ...` enviado ao handle do coordenador.
- **O agente desta skill não codifica**: ele só abre terminais, injeta prompts, lê avisos e conta iterações.
- **Ponytail nível `full` no turno do Fixer** (correção é execução de código): menor correção que resolve o item inteiro, nunca no turno do Reviewer. Instalação por agente, fallback e trava anti-atalho em "Ponytail no Planejamento e na Execução" do `orca-superpowers-orchestrator`.

```
        [AGENTE DA SKILL — coordenador, não codifica]
                        │
   resolve <ORQ_HANDLE> │  orca terminal show --json
                        ▼
   ┌──────────────────────────────────────────────┐
   │ Turno R (Reviewer): requesting-code-review   │──▶ relatório em docs/superpowers/reviews/
   │         + verification-before-completion     │         │
   └──────────────────────────────────────────────┘         │
             aprovado? ── SIM ──▶ FIM (aprovação) ◀──────────┤
                        │ NÃO (extrai itens concretos)       │
                        ▼                                    │
   ┌──────────────────────────────────────────────┐          │
   │ Turno F (Fixer): receiving-code-review +     │◀─────────┘
   │ executing-plans+ponytail, itens apontados    │
   └──────────────────────────────────────────────┘
                        │ iteração < 3? ── SIM ──▶ volta ao Reviewer
                        │ NÃO ──▶ ESCALA AO USUÁRIO (status: FALHA)
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
- Ao escolher o agente, confirme também o modelo (Descoberta de Modelos no Passo 0 do orca-superpowers-orchestrator).

---

## Quando Usar

- Quando um review retornou **reprovado** com itens de correção e o usuário quer que outra rodada de correção + reavaliação aconteça automaticamente.
- Como continuação direta do `orca-superpowers-orchestrator` quando o Reviewer emite `status: FALHA`.
- Quando o próprio usuário traz um relatório de review reprovado e pede "corrige e revisa de novo".

### Quando NÃO Usar

- Review **aprovado** (`Ready to merge`) → use `orca-superpowers-merge`.
- Sem relatório de review existente e sem itens apontados → isso é desenvolvimento novo, use `orca-superpowers-orchestrator`.
- Tarefa trivial de um único arquivo → corrija direto no agente atual.

---

## Protocolo

### Passo 0: Entradas e Identificação

1. Localizar o relatório de review mais recente em `docs/superpowers/reviews/` (ou o caminho informado pelo usuário).
2. Confirmar que ele contém **itens concretos de correção**. Sem itens, não há o que corrigir: pare e avise o usuário.
3. Resolver o handle de destino dos avisos **antes** de qualquer despacho:

```bash
orca terminal show --json        # campo "handle" = <ORQ_HANDLE>
```

Falhou → o aviso não teria destino: informe o usuário e pare.

### Passo 1: Turno de Correção (Fixer) — só se o review estiver reprovado

```bash
orca terminal create --worktree active --title "fix-<N>-Fixer" --focus --command "<FIXER_CLI>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
# satisfied: false → repita UMA vez com timeout maior; ainda false → PARE e avise o usuário
orca terminal send --terminal <handle> --text "<TEMPLATE_FIXER>" --enter --json
```

#### Template injetado no Fixer:
```text
Use as skills superpowers:receiving-code-review, superpowers:executing-plans e ponytail no nível full (/ponytail full).
Se a skill ponytail não estiver instalada neste CLI, aplique o princípio na mão e diga isso no aviso final: menor correção que resolve o item inteiro.
RELATÓRIO DE REVIEW: <caminho-do-relatorio>
ITENS A CORRIGIR (iteração <N>):
- <item 1 — problema, arquivo, severidade>
- <item 2>

REGRAS RÍGIDAS:
1. Corrija EXCLUSIVAMENTE os itens listados; não faça refatorações nem melhorias não pedidas.
2. Cada item: escreva o teste que falha, corrija em TDD, veja passar.
3. Menor correção que resolve o item inteiro: antes de editar, faça grep de todos os chamadores da função que vai tocar e corrija a causa raiz uma vez no código compartilhado, em vez de remendar cada ponto de uso. Nada de abstração, wrapper ou flag que o item não pediu.
4. A correção mínima nunca corta validação, tratamento de erro, segurança, acessibilidade nem o teste do item — isso é correção inacabada, não preguiça.
5. Commit atômico por item: git commit -m "fix: <resumo-do-item>".
6. Se algum item estiver incorreto ou impossível, NÃO o pule: registre a discordância no aviso.
7. Ao concluir, avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA fixer CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | item: <itens corrigidos ou discordancia>" --enter --json
8. Só depois do envio, encerre a execução.
```

Aguarde `ETAPA fixer CONCLUÍDA` no seu terminal. Sem aviso em 10 minutos → `orca terminal read --terminal <handle> --limit 50 --json` antes de qualquer conclusão. Ausência de aviso nunca conta como conclusão.

### Passo 2: Turno de Reavaliação (Reviewer)

```bash
orca terminal create --worktree active --title "fix-<N>-Reviewer" --focus --command "<REVIEWER_CLI>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
orca terminal send --terminal <handle> --text "<TEMPLATE_REVIEWER>" --enter --json
```

#### Template injetado no Reviewer:
```text
Use as skills superpowers:requesting-code-review e superpowers:verification-before-completion.
RELATÓRIO ANTERIOR: <caminho-do-relatorio>  (iteração <N-1>)
ITENS QUE DEVEM ESTAR RESOLVIDOS: <mesma lista enviada ao Fixer>

REQUISITOS DA REAVALIAÇÃO:
1. Execute a suíte de testes do projeto e cole a saída real.
2. Avalie APENAS os itens da iteração anterior + regressões que eles tenham causado.
3. Acrescente ao mesmo relatório uma seção "## Iteração <N>" com: itens resolvidos, não resolvidos, novos e veredito.
4. Veredito: 'Ready to merge' (aprovado) ou 'Reprovado' (com a nova lista de itens concretos).
5. Sugestão: Reviewer de vendor independente do Executor (Antigravity/Gemini, ou Claude Code/Codex caso o Executor seja outro); o usuário pode definir outro agente.
6. Avise o orquestrador (obrigatório, mesmo em falha):
   orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA reviewer CONCLUÍDA | status: <OK|FALHA> | resumo: <3 frases> | veredito: <aprovado|reprovado> | relatorio: <caminho>" --enter --json
7. Só depois do envio, encerre.
```

### Passo 3: Decisão da Malha

Após `ETAPA reviewer CONCLUÍDA`:

| Veredito | Ação |
|---|---|
| **aprovado** | Fim. Reporte ao usuário com o caminho do relatório e siga para `orca-superpowers-merge`. |
| **reprovado** e iteração `< 3` | Volte ao Passo 1 com a nova lista de itens. |
| **reprovado** e iteração `= 3` | **PARE.** Escalone ao usuário. |
| `status: FALHA` (em qualquer etapa) | **PARE.** Escalone ao usuário com o conteúdo lido do terminal. |

Mensagem de encerramento por limite atingido (obrigatória):

```bash
orca terminal send --terminal <ORQ_HANDLE> --text "ETAPA review-loop CONCLUÍDA | status: FALHA | resumo: limite de 3 iterações atingido; pendências restantes: <lista> | relatorio: <caminho>" --enter --json
```

> NUNCA reinicie a contagem em uma nova rodada: o limite é **3 iterações totais por review-loop**, não por sessão.

---

## Comandos Úteis do Orca ADE

```bash
orca terminal show --json                                              # <ORQ_HANDLE> — ANTES do primeiro despacho
orca terminal create --worktree active --title "<t>" --focus --command "<agente-interativo>" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 120000 --json
orca terminal send --terminal <handle> --text "<prompt>" --enter --json
orca terminal read --terminal <handle> --limit 50 --json               # quando o aviso não chega
orca terminal list --worktree active --json
orca worktree current --json
```

---

## Red Flags - Erros Críticos

- **NUNCA corrija sem uma lista concreta de itens** vindos de relatório de review; "melhore o que achar relevante" quebra a auditoria.
- **NUNCA avance de turno sem `ETAPA <fixer|reviewer> CONCLUÍDA`** no terminal do coordenador — sem aviso, a etapa está indeterminada; leia o terminal antes de decidir.
- **NUNCA rode a suíte de testes nem o diff no coordenador** — ele apenas despacha e lê.
- **NUNCA ultrapasse 3 iterações** nem reinicie a contagem para "dar mais uma chance".
- **NUNCA deixe o Fixer tocar em código fora dos itens apontados** (refatoração extra invalida o escopo do review).
- **NUNCA aceite o ponytail como desculpa para entregar item sem teste, sem validação ou com a causa raiz intacta:** correção menor e inacabada volta reprovada e queima uma das 3 iterações.
- **NUNCA avance sem o aviso enviado ao `<ORQ_HANDLE>` real** resolvido no Passo 0.
- **TUI é OBRIGATÓRIA em 100% dos turnos**: `--focus` + `tui-idle` antes do `send`; duas falhas de `satisfied: false` → interrompa e avise o usuário. **NUNCA** use `-p`/`exec`/`run`.
