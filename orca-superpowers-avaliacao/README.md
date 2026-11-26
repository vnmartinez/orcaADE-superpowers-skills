# Skill Avaliação de Issues (Orca Superpowers Avaliação)

Skill `orca-superpowers-avaliacao`: auditoria de prontidão de requisitos das issues abertas de um projeto pelas **6 dimensões de qualidade do SWEBOK (Requirements Engineering)** — a etapa barata **antes** de qualquer ciclo `orchestration-auto`/`orchestrator`.

## Conteúdo
- [SKILL.md](SKILL.md): fonte auto-detectada (`gh`) com fallback, régua das 6 dimensões com prova textual, relatório "prontas"/"com lacunas", dois gates de aprovação e aplicação via `gh issue edit --body-file`.

## As 6 Dimensões
1. Claro e não ambíguo
2. Completo
3. Consistente
4. Verificável
5. Rastreável
6. Necessário e factível

Cada veredito vem com **prova colada** da própria issue (trecho que sustenta o ❌ ou o critério ausente).

## Fluxo
1. **Fonte**: `git remote` para GitHub + `gh` autenticado → `gh issue list --state open`; caso contrário, **pergunta** ao usuário onde estão as issues (nunca inventa).
2. **Avalia** cada issue nas 6 dimensões.
3. **Relatório**: `issue × 6 dims`, agrupando *prontas pra ciclo* e *com lacunas*.
4. **GATE 1**: quais issues corrigir (todas / escolher / nenhuma).
5. **Rascunho** antes/depois, preservando o original; lacunas viram `[DEFINIR: <pergunta>]`.
6. **GATE 2**: aprovação do texto → `gh issue edit <n> --body-file`.

## Garantias
- Zero escrita sem os dois gates; zero requisito inventado; zero conteúdo apagado sem aprovação.
- Sem TUI, sem dispatch de agente, sem consulta de cota — leitura e julgamento de texto na sessão.
- Zero PII e zero segredos em relatórios e rascunhos.

## Relação com a família
- **Antes** do `orca-superpowers-orchestration-auto`: o Passo 0 dele aponta pra esta skill como a régua única das 6 dims da issue (input).
- O `PROBE` do Planner no `orchestration-auto` continua avaliando a **saída** (spec) com a mesma régua de 6 dims.
