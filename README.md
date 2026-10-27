# orca-superpowers-skills

Combinação de ferramentas para usar superpowers e orquestração no Orca ADE.

## Skills

| Skill | Descrição |
|---|---|
| [orca-superpowers-orchestrator](orca-superpowers-orchestrator/SKILL.md) | Orquestrador central que despacha Planner → Gate humano → Executor → Reviewer em terminais do Orca, com TUI obrigatória e aviso de conclusão via CLI |
| [orca-superpowers-review-loop](orca-superpowers-review-loop/SKILL.md) | Malha de review reprovado: Fixer corrige só os itens apontados → Re-review, com limite de 3 iterações e escala humana |
| [orca-superpowers-merge](orca-superpowers-merge/SKILL.md) | Finalização auditável pós-aprovação: testes reais → gate da estratégia de merge → merge/push → card do worktree e limpeza de terminais |

| [orca-superpowers-handoff](orca-superpowers-handoff/SKILL.md) | Cadeia de handoff sequencial entre agentes no mesmo worktree, com TUI obrigatória e aviso de conclusão via CLI |

## Pré-requisito opcional: ponytail

As fases de **planejamento** e **execução** destas skills rodam sob a skill [ponytail](https://github.com/DietrichGebert/ponytail) — "dev sênior preguiçoso": a menor mudança que resolve a tarefa inteira, sem abstração ou código "para depois" que ninguém pediu. Planner em `ultra` (questiona o requisito antes de especificar), Executor e Fixer em `full`. O **Reviewer não usa ponytail**, para não auditar com o mesmo viés de economia.

| Agente | Instalação do ponytail |
|---|---|
| Claude Code | `/plugin marketplace add DietrichGebert/ponytail` e, em prompt separado, `/plugin install ponytail@ponytail` |
| Codex | `codex plugin marketplace add DietrichGebert/ponytail` + `codex plugin add ponytail@ponytail` |
| Antigravity CLI | `agy plugin install https://github.com/DietrichGebert/ponytail` |
| OpenCode | `opencode plugin add @dietrichgebert/ponytail` |

Sem o ponytail instalado o ciclo continua igual: os prompts injetados já declaram o princípio em texto como fallback, e o agente registra no aviso de conclusão que rodou sem a skill. Detalhes (níveis, fallback e trava anti-atalho) em [Ponytail no Planejamento e na Execução](orca-superpowers-orchestrator/SKILL.md#ponytail-no-planejamento-e-na-execução).

## Instalação

Copie a pasta da skill para o diretório de skills do agente:

```powershell
# Claude Code / Antigravity (Gemini) / Codex / OpenCode (agents)
$skills = "orca-superpowers-orchestrator", "orca-superpowers-review-loop", "orca-superpowers-merge", "orca-superpowers-handoff"
$targets = "$env:USERPROFILE\.claude\skills", "$env:USERPROFILE\.gemini\config\skills", "$env:USERPROFILE\.codex\skills", "$env:USERPROFILE\.agents\skills", "$env:USERPROFILE\.config\opencode\skills"
foreach ($skill in $skills) {
  foreach ($target in $targets) {
    Copy-Item -Recurse -Force $skill "$target\$skill"
  }
}
```
