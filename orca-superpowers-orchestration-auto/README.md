# Skill Orquestração Automática (Orca Superpowers Orchestration Auto)

Skill `orca-superpowers-orchestration-auto` para orquestração autônoma, agent-agnostic e orientada a cotas no **Orca ADE**, executada em bash puro / Git Bash (Windows, macOS e Linux).

## Conteúdo
- [SKILL.md](SKILL.md): Definição completa da skill, descoberta dinâmica via Orca CLI, presets de roteamento (`economy`, `balanced`, `performance`), algoritmo determinístico, fallback `curl` e trilha de auditoria.
- [scripts/get-quotas.sh](scripts/get-quotas.sh): Coletor em bash puro (utilitários POSIX do Git, sem dependências externas) que consulta `orca agent installed` e `orca account list`, normalizando agentes instalados, janelas 5h/semanal e `buckets[]` sem PII nem tokens.

## Visão Geral
O orquestrador atua estritamente como coordenador central e seleciona agente e modelo automaticamente, sem perguntar ao usuário:
1. **Passo 0**: Resolve `<ORQ_HANDLE>` (`orca terminal show`), executa `scripts/get-quotas.sh`, classifica o `effortClass` (`light | standard | deep`) e resolve Planner, Executor e Reviewer pelo preset ativo sobre os agentes instalados.
2. **Passo 1 (Planner)**: Despacha via `orca agent launch --surface terminal --focus` com `superpowers:brainstorming` e `superpowers:writing-plans`.
3. **Passo 2 (Gate humano único)**: Apresenta arquitetura, plano e trilha de auditoria para aprovação explícita antes de implementar.
4. **Passo 3 (Executor)**: Revalida cotas, despacha o executor via `orca agent launch` com `superpowers:executing-plans` (TDD estrito e commits atômicos).
5. **Passo 4 (Reviewer)**: Revalida cotas, garante papel `readOnly` com independência de vendor frente ao Executor e despacha via `orca agent launch` com `superpowers:requesting-code-review` e `superpowers:verification-before-completion`.
6. **Passo 5 (Consolidação)**: Entrega o veredito, a saída real dos testes e a trilha completa de auditoria.

## Garantias
- Descoberta 100% dinâmica e agent-agnostic via `orca agent installed --worktree active --json` e `orca account list --json`.
- TUI interativa obrigatória em 100% dos despachos (`--surface terminal --focus` + `tui-idle`), sem fallback não-interativo (`-p`/`exec`/`run`).
- Prova de conclusão exclusiva pelo envio de `ETAPA <planner|executor|reviewer> CONCLUÍDA` ao `<ORQ_HANDLE>`.
- Provedor `status: unavailable` ou ausente nunca bloqueia nem é tratado como crítico; papéis `readOnly: true` nunca fazem fallback para `readOnly: false`.
- Zero PII e zero segredos nas fixtures, saídas do script e relatórios de auditoria.
