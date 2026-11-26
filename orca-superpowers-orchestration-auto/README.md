# Skill Orquestração Automática (Orca Superpowers Orchestration Auto)

Skill `orca-superpowers-orchestration-auto` para orquestração autônoma, agent-agnostic e orientada a cotas no **Orca ADE**, executada em bash puro / Git Bash (Windows, macOS e Linux).

## Conteúdo
- [SKILL.md](SKILL.md): Definição completa da skill, descoberta dinâmica via Orca CLI, presets de roteamento (`economy`, `balanced`, `performance`), algoritmo determinístico, fallback `curl` e trilha de auditoria.
- [scripts/get-quotas.sh](scripts/get-quotas.sh): Coletor em bash puro (utilitários POSIX do Git, sem dependências externas) que consulta `orca agent installed` e `orca account list`, normalizando agentes instalados, janelas 5h/semanal e `buckets[]` sem PII nem tokens.

## Visão Geral
O orquestrador atua estritamente como coordenador central e seleciona agente e modelo automaticamente, sem perguntar ao usuário:
1. **Passo 0**: Resolve `<ORQ_HANDLE>` (`orca terminal show`), executa `scripts/get-quotas.sh`, extrai o `TaskProfile` da tarefa (`decision`, `verification`, `risk`, `ambiguity`, `blast`), deriva o `effortClass` e resolve Planner, Executor e Reviewer pelo preset — começando sempre pelo **candidato mais barato** em `costOrder` que os gates de cota permitem.
2. **Passo 1 (Planner)**: Despacha via `orca agent launch --surface terminal --focus` com `superpowers:brainstorming` e `superpowers:writing-plans`; a mensagem de conclusão carrega o veredito estruturado do `probe` com evidência.
3. **Passo 2 (Gate humano único)**: Apresenta arquitetura, plano, perfil da tarefa e trilha de auditoria para aprovação explícita antes de implementar.
4. **Passo 3 (Executor)**: Revalida cotas, despacha o executor via `orca agent launch` com `superpowers:executing-plans` (TDD estrito e commits atômicos) e confronta a evidência do `probe` com o filesystem.
5. **Passo 4 (Reviewer)**: Revalida cotas, garante papel `readOnly` com independência de vendor frente ao Executor e despacha via `orca agent launch` com `superpowers:requesting-code-review` e `superpowers:verification-before-completion`.
6. **Passo 5 (Consolidação)**: Entrega o veredito, a saída real dos testes, o histórico `probe`/`escalation` de cada etapa e a trilha completa de auditoria.

**Malha de escalação (propose–probe–compose):** etapa com `probe: FAIL` (confrontada contra evidência real) reexecuta uma única vez com o próximo papel em `costOrder`; segundo `FAIL` interrompe e avisa o usuário. A trilha `profile + probe + escalation` vira memória: nas próximas tarefas do mesmo domínio, ela sobe o ponto de partida sem perguntar.

## Garantias
- Descoberta 100% dinâmica e agent-agnostic via `orca agent installed --worktree active --json` e `orca account list --json`.
- Rota inicial sempre na opção **mais barata que o perfil da tarefa aceita** (`TaskProfile` → `effortClass` → `costOrder`), com escalação de 1 nível por `probe: FAIL` e corte no segundo `FAIL`.
- TUI interativa obrigatória em 100% dos despachos (`--surface terminal --focus` + `tui-idle`), sem fallback não-interativo (`-p`/`exec`/`run`).
- Prova de conclusão exclusiva pelo envio de `ETAPA <planner|executor|reviewer> CONCLUÍDA` ao `<ORQ_HANDLE>`, sempre com `probe: <PASS|FAIL>` e uma linha de evidência.
- Provedor `status: unavailable` ou ausente nunca bloqueia nem é tratado como crítico; papéis `readOnly: true` nunca fazem fallback para `readOnly: false`.
- Zero PII e zero segredos nas fixtures, saídas do script e relatórios de auditoria.
