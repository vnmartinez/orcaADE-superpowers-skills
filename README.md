# orca-superpowers-skills

Combinação de ferramentas para usar superpowers e orquestração no Orca ADE.

## Skills

| Skill | Descrição |
|---|---|
| [orca-superpowers-orchestrator](orca-superpowers-orchestrator/SKILL.md) | Orquestrador central que despacha Planner → Gate humano → Executor → Reviewer em terminais do Orca, com TUI obrigatória e aviso de conclusão via CLI |
| [orca-superpowers-orchestration-auto](orca-superpowers-orchestration-auto/SKILL.md) | Variante do orquestrador com seleção automática de agente e modelo por papel, conforme agentes instalados e cotas reais, sem perguntas de alocação ao usuário |
| [orca-superpowers-review-loop](orca-superpowers-review-loop/SKILL.md) | Malha de review reprovado: Fixer corrige só os itens apontados → Re-review, com limite de 3 iterações e escala humana |
| [orca-superpowers-merge](orca-superpowers-merge/SKILL.md) | Finalização auditável pós-aprovação: testes reais → gate da estratégia de merge → merge/push → card do worktree e limpeza de terminais |
| [orca-superpowers-handoff](orca-superpowers-handoff/SKILL.md) | Cadeia de handoff sequencial entre agentes no mesmo worktree, com TUI obrigatória e aviso de conclusão via CLI |
| [orca-superpowers-avaliacao](orca-superpowers-avaliacao/SKILL.md) | Auditoria de prontidão das issues abertas pelas 6 dimensões SWEBOK de requisitos, com prova textual, dois gates de aprovação e correção via `gh issue edit` |

## Instalação

### Instalador multiagente (Recomendado — 1 comando)

Instala as 4 skills automaticamente em `.agents/skills` e em todos os CLIs detectados pelo Orca (`orca agent installed --worktree active --json`), com suporte a atualização idempotente, `--dry-run`, backup com `--force` e remoção segura com `--uninstall`. Execute no terminal (macOS/Linux ou Git Bash no Windows):

```bash
bash scripts/install-skills.sh
```

Comandos úteis:

```bash
bash scripts/install-skills.sh --dry-run    # simula sem gravar arquivos
bash scripts/install-skills.sh --local      # instala no projeto atual (.agents/skills + CLIs presentes)
bash scripts/install-skills.sh --force      # faz backup de cópias manuais divergentes e substitui
bash scripts/install-skills.sh --uninstall  # remove apenas as skills do plugin (preserva terceiros)
```

Consulte a documentação completa de flags, tabela de agentes e rollback em [plugin/README.md](plugin/README.md).

### Instalação manual (alternativa)

Copie as pastas das skills para os **5 destinos** dos agentes (`Claude Code`, `Antigravity (Gemini)`, `Codex`, `Agents` e `OpenCode`).

#### macOS / Linux / Git Bash (Windows)

```bash
skills=(
  "orca-superpowers-orchestrator"
  "orca-superpowers-orchestration-auto"
  "orca-superpowers-review-loop"
  "orca-superpowers-merge"
  "orca-superpowers-handoff"
  "orca-superpowers-avaliacao"
)

for skill in "${skills[@]}"; do
  for dest in \
    "$HOME/.claude/skills/$skill" \
    "$HOME/.gemini/config/skills/$skill" \
    "$HOME/.codex/skills/$skill" \
    "$HOME/.agents/skills/$skill" \
    "$HOME/.config/opencode/skills/$skill"
  do
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    cp -R "$skill" "$dest"
  done
done
```

#### Windows PowerShell (alternativa)

```powershell
# Claude Code / Antigravity (Gemini) / Codex / Agents / OpenCode
$skills = "orca-superpowers-orchestrator", "orca-superpowers-orchestration-auto", "orca-superpowers-review-loop", "orca-superpowers-merge", "orca-superpowers-handoff", "orca-superpowers-avaliacao"
$targets = "$env:USERPROFILE\.claude\skills", "$env:USERPROFILE\.gemini\config\skills", "$env:USERPROFILE\.codex\skills", "$env:USERPROFILE\.agents\skills", "$env:USERPROFILE\.config\opencode\skills"
foreach ($skill in $skills) {
  foreach ($target in $targets) {
    Copy-Item -Recurse -Force $skill "$target\$skill"
  }
}
```
