---
name: orca-superpowers-avaliacao
description: Use when auditing the open issues of a project against the 6 SWEBOK requirements dimensions (clear/unambiguous, complete, consistent, verifiable, traceable, necessary/feasible) to report what is ready for a cycle and what is missing, then fixing the gaps with approval. Trigger on "avaliar issues", "auditar issues", "issues prontas", "issue está completa?", "6 dimensões SWEBOK", "requisito ambíguo", "preparar issues para o ciclo" or any request to check whether issue/requirement text is good enough to start development.
---

# Orca Superpowers Avaliação

## Overview

Auditoria de **prontidão de requisitos** para todas as issues abertas de um projeto, usando as **6 dimensões de qualidade do SWEBOK (Requirements Engineering)** como régua única. É a etapa barata que vem **antes** de qualquer ciclo de desenvolvimento: ler e julgar texto custa quase nada, enquanto planejar sobre uma issue ambígua custa um ciclo inteiro de Planner.

- Avalia cada issue nas 6 dimensões com **prova colada** (cita o trecho que sustenta o ❌ — nunca veredito sem evidência).
- Separa **"prontas pra ciclo"** (tudo ✅) de **"com lacunas"**.
- **Nunca escreve sem dois gates**: você escolhe quais issues corrigir e depois aprova o texto do rascunho.
- **Nunca inventa requisito**: o que não dá pra deduzir da própria issue vira `[DEFINIR: <pergunta>]`.

```text
1. Fonte auto-detectada (gh) ou fallback perguntando onde estão as issues
2. Avalia cada issue nas 6 dimensões com prova textual
3. Relatório: issue × 6 dims -> "prontas" / "com lacunas"
4. GATE: qual(is) issue(s) corrigir?
5. Rascunho antes/depois (lacunas viram [DEFINIR: ...]) -> GATE de texto
6. Aplica com gh issue edit --body-file
```

---

## Quando Usar

- Antes de iniciar um ciclo `orca-superpowers-orchestration-auto` ou `orca-superpowers-orchestrator` para garantir que a issue do trabalho está completa.
- Para auditar de uma vez todas as issues abertas de um repo e montar a fila de trabalho pronta.
- Quando alguém perguntar se uma issue/spec "está boa", "está completa", "dá pra começar".

### Quando NÃO Usar

- Para avaliar a spec que o Planner acabou de escrever (isso é o `PROBE` do Planner dentro do `orchestration-auto`).
- Para corrigir corpo de PR, commit message ou documentação existente.
- Quando não existem issues em lugar nenhum e o usuário só quer conversar sobre requisitos (responda direto).

---

## 1. Fonte das Issues (auto-detecção com fallback)

Ordem de tentativa, na própria sessão (sem TUI, sem dispatch de agente):

1. **GitHub via `gh`**, se as duas condições passarem:
   ```bash
   git remote get-url origin      # remote existe e aponta pra github.com
   gh auth status                 # gh instalado e autenticado
   ```
   Então:
   ```bash
   gh issue list --state open --json number,title,body,labels --limit 100
   ```
2. **Fallback**: se qualquer passo acima falhar, **perguntar ao usuário** onde estão as issues (repo local sem remote, arquivos em `docs/issues/` ou similar, formato desconhecido, ou texto colado na conversa).
3. **Nunca inventar fonte, número de issue nem conteúdo de issue.** Sem fonte confirmada, o fluxo para na pergunta do passo 2.

Formato de arquivo (quando o fallback for local): pedir um exemplo da primeira issue antes de assumir qualquer estrutura.

---

## 2. As 6 Dimensões (régua de avaliação)

Para cada issue, avaliar **o texto como está** e colar a prova:

| # | Dimensão SWEBOK | Pergunta de avaliação | Prova exigida |
|---|---|---|---|
| 1 | **Claro e não ambíguo** | Cada afirmação tem uma única leitura possível (sem "e/ou", "etc.", "alguns", termos vagos)? | Cita a frase ambígua ou marca ✅ citando a frase mais clara |
| 2 | **Completo** | Tudo que o resultado exige está dito: entradas, saídas, casos de erro/extremo, comportamento esperado? | Lista o que falta (ex.: "sem definição do que acontece com entrada vazia") |
| 3 | **Consistente** | Não contradiz internamente nem contradiz fatos conhecidos do projeto (endpoint, campo, decisão anterior)? | Cita as duas partes do conflito, ou ✅ |
| 4 | **Verificável** | Dá pra provar "foi feito" com teste automatizado ou comando objetivo? | Aponta o critério de aceitação ausente, ou cita o critério existente |
| 5 | **Rastreável** | Aponta pra onde isso se conecta: arquivo/endpoint/módulo/issue anterior que já existe no projeto? | Cita a referência existente, ou diz "nenhuma referência ao código existente" |
| 6 | **Necessário e factível** | Tudo que está pedido é necessário pro objetivo? É viável dentro do escopo/blast que a issue declara? | Aponta item supérfluo ou fora de escopo, ou ✅ |

Regras de veredito:
- Cada dimensão é ✅ ou ❌ — **sem "meio ponto"**; dúvida razoável é ❌ com a dúvida explicitada.
- A prova é **sempre um trecho da própria issue** (ou a ausência dele). Nada de avaliação genérica.
- Issue sem corpo (só título): as 6 dims avaliam o título e quase todas caem em ❌ — reportar isso como "issue só com título" é resultado esperado, não erro.

---

## 3. Relatório

Apresentar **um relatório só**, com esta estrutura:

```text
Avaliação de <N> issues abertas | fonte: <gh | local | colado> | régua: 6 dims SWEBOK

PRONTAS PRA CICLO (tudo ✅)
#12 Fix CSV export            1✅2✅3✅4✅5✅6✅

COM LACUNAS
#31 Migrar auth para JWT       1❌ 2✅ 3✅ 4❌ 5❌ 6✅
    1. claro e não ambíguo: "melhorar o login" é vago — nenhuma frase define o alvo
    4. verificável: nenhum critério de aceitação citado
    5. rastreável: nenhuma referência a arquivo/endpoint existente

Resumo: <prontas> prontas | <com lacunas> com lacunas | <N total> avaliadas
```

Agrupar sempre por "prontas" e "com lacunas"; as falhas vêm numeradas pela mesma ordem da tabela das 6 dimensões.

---

## 4. GATE 1 — O que corrigir

Depois do relatório, **uma pergunta só**:

> *"Quer corrigir: (a) todas as <N> issues com lacunas, (b) só as que eu escolher, (c) nenhuma — só o relatório?"*

- **(c) ou nenhuma seleção** → encerra com o relatório. Sem escrita.
- **(a)/(b)** → passa ao rascunho.

---

## 5. Rascunho + GATE 2 — Aprovação do texto

Para cada issue a corrigir, gerar o corpo corrigido **preservando todo o conteúdo original** e mostrar antes/depois:

- O que foi **mantido** (não se apaga sem avisar).
- O que foi **reescrito** (clareza/completude — reescreve só a frase problemática).
- O que foi **acrescentado**.
- Lacuna sem respaldo na issue original → `[DEFINIR: <pergunta objetiva>]`. **Nunca** preencher com suposição nem com informação do outro assunto.

Apresentar os rascunhos e esperar aprovação explícita do texto (GATE 2). Correção de texto não é coberta pelo GATE 1.

---

## 6. Aplicação

Só após o GATE 2:

```bash
gh issue edit <numero> --body-file /tmp/issue-<numero>.md
```

- Gravar cada corpo corrigido em arquivo temporário antes do `--body-file` (o corpo pode ter aspas e crases; nunca embutir no comando).
- Aplicar issue por issue e reportar `issue <n>: atualizada | issue <m>: pulada`.
- Se o `gh issue edit` falhar, reportar a falha daquela issue e seguir com as demais — nunca repetir silenciosamente.

---

## Red Flags - Erros Críticos

- **NUNCA avalie sem colar a prova**: todo ❌ cita o trecho ausente/problemático da issue.
- **NUNCA escreva sem os dois gates**: escolha das issues (GATE 1) e aprovação do texto (GATE 2).
- **NUNCA invente requisito**: lacuna sem evidência = `[DEFINIR: <pergunta>]`.
- **NUNCA apague conteúdo existente** sem mostrar isso no antes/depois e ser aprovado.
- **NUNCA rode dispatch de agente, TUI ou consultas de cota**: esta skill lê e julga texto na própria sessão.
- **NUNCA trate `gh` indisponível como erro fatal**: é fallback para a pergunta ao usuário.
- **NUNCA inclua e-mails, UUIDs ou tokens** em relatórios e rascunhos.
