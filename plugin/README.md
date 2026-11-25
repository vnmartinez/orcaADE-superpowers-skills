# Plugin Multiagente — Orca Superpowers Skills

Pacote versionado (`plugin/manifest.json`) com instalador em **bash puro** (`scripts/install-skills.sh`) para instalar, atualizar e remover as 4 skills do repositório `orcaADE-superpowers-skills` em todos os CLIs suportados pelo **Orca ADE**, com layout compatível com o `orca skills install`.

- **ID do plugin:** `superpowers-skills`
- **Versão:** `1.0.0`
- **Manifesto:** [`plugin/manifest.json`](manifest.json)
- **Instalador:** [`scripts/install-skills.sh`](../scripts/install-skills.sh)

## Instalação rápida (1 comando)

Execute na raiz do repositório (macOS, Linux ou **Git Bash** no Windows):

```bash
bash scripts/install-skills.sh
```

Para pré-visualizar o plano de instalação sem gravar nenhum arquivo:

```bash
bash scripts/install-skills.sh --dry-run
```

## Como o plugin descobre os agentes

O instalador segue uma precedência dinâmica (sem lista fixa):

1. `--agent <lista>` (ou `--agent universal` para instalar apenas na pasta canônica compartilhada).
2. `--agents-file <caminho>` (JSON no formato de `orca agent installed --json`, útil para execução offline/testes).
3. `orca agent installed --worktree active --json` (descoberta automática dos CLIs instalados no host).
4. **Fallback sem Orca:** detecta diretórios de agentes já presentes em `$HOME` (ou no projeto em `--local`) e sempre garante a cópia canônica em `.agents/skills`.

As 4 pastas de skills na raiz do repositório continuam sendo a fonte única de verdade (`orca-superpowers-orchestrator`, `orca-superpowers-orchestration-auto`, `orca-superpowers-review-loop`, `orca-superpowers-merge`).

## Destinos por agente (layout Orca)

A cópia canônica é sempre gravada em `.agents/skills/<skill>` (relativo a `$HOME` no modo global ou à raiz do projeto no modo `--local`).

- **30 agentes compartilhados + futuros CLIs + `universal`:** lêem diretamente de `.agents/skills/<skill>` (`codex`, `opencode`, `opencode2`, `copilot`, `gemini`, `kimi`, `amp`, `cline`, `goose`, `kilo`, `devin`, `mistral-vibe`, `qwen-code`, `muse`, `autohand`, `crush`, `command-code`, `rovo`, `openclaw`, `pi`, `mimo-code`, `omp`, `prime-agent`, `qoder`, `qoder-cn`, `codebuff`, `freebuff`, `ante`, `jcode`, `dsh` e qualquer agente inédito).
- **12 agentes com pasta própria (`agentPaths` em `plugin/manifest.json`):** recebem symlink apontando para a cópia canônica (ou cópia automática em fallback se o SO não permitir symlinks nativos, ou quando `--copy` for informado).

| Agente | Destino global (`$HOME/...`) | Destino local (`--local`) |
|---|---|---|
| `claude` | `.claude/skills` | `.claude/skills` |
| `antigravity` | `.gemini/config/skills` | `.agents/skills` |
| `cursor` | `.cursor/skills` | `.agents/skills` |
| `droid` | `.factory/skills` | `.factory/skills` |
| `continue` | `.continue/skills` | `.continue/skills` |
| `trae` | `.trae-cn/skills` | `.trae-cn/skills` |
| `grok` | `.grok/skills` | `.grok/skills` |
| `aug` | `.augment/skills` | `.augment/skills` |
| `zcode` | `.zcode/skills` | `.agents/skills` |
| `codebuddy` | `.codebuddy/skills` | `.codebuddy/skills` |
| `kiro` | `.kiro/skills` | `.kiro/skills` |
| `openclaude` | `.openclaude/skills` | `.openclaude/skills` |

> **Nota sobre Antigravity:** no modo global, o destino `.gemini/config/skills` fica fora da pasta do plugin `superpowers` em `.gemini/config/plugins/superpowers/skills`, evitando que atualizações do plugin `superpowers` apaguem suas skills instaladas.
>
> **Nota sobre `--local`:** links em pastas dedicadas (como `.claude/skills`) só são criados se a pasta-pai do agente (ex.: `.claude/`) já existir no projeto, evitando poluir repositórios com diretórios de CLIs não utilizados.

## Referência de flags

| Flag | Comportamento |
|---|---|
| `--dry-run` | Simula e imprime todas as ações (`PLUGIN`, `ACTION`, `SUMMARY`) sem criar, mover ou apagar nada. |
| `--agent <lista\|universal>` | Instala apenas para os agentes informados (separados por vírgula) ou apenas `.agents/skills` (`universal`). |
| `--skill <nome>` | Instala ou remove apenas a skill indicada (pode ser repetida). |
| `--local` | Instala no projeto atual (`$PWD`, ou no caminho de `--target-dir`) em vez de `$HOME`. |
| `--target-dir <dir>` | Define a raiz do projeto usada com `--local`. |
| `--force` | Move cópias manuais divergentes para backup antes de substituir (ou antes de remover no `--uninstall`). |
| `--uninstall` | Remove apenas skills gerenciadas pelo plugin, preservando skills de terceiros e cópias manuais. |
| `--copy` | Cria cópias reais nos destinos de agente em vez de symlinks. |
| `--agents-file <path>` | Lê a lista de agentes de um JSON no formato de `orca agent installed --json`. |
| `--list` | Lista ID, versão e skills declaradas em `plugin/manifest.json`. |
| `-h`, `--help` | Exibe ajuda de uso. |

## Atualização, conflitos e rollback via backup

- **Atualizar:** execute `git pull && bash scripts/install-skills.sh`. O recibo `.agents/.orca-superpowers-installed` (sem PII, apenas caminhos relativos) detecta mudanças de versão ou conteúdo e atualiza in-place (`ACTION|UPDATE|...`).
- **Conflitos manuais:** se existir uma cópia manual divergente fora do recibo, o instalador emite `ACTION|SKIP|...` e preserva seus arquivos intactos.
- **Backup e rollback:** usando `--force`, o instalador move a pasta pré-existente inteira para `.agents/.orca-superpowers-backups/<timestamp>/<rel_path>` (`ACTION|BACKUP|...`). Para reverter, basta mover o diretório desejado do backup de volta ao caminho original.
- **Desinstalação segura:** `bash scripts/install-skills.sh --uninstall` remove somente links/cópias gerenciadas e o recibo de estado, mantendo intacta qualquer skill de terceiro.

## Windows (Git Bash)

No Windows, execute os comandos no **Git Bash** (incluído no Git for Windows). Caso o Windows não tenha Developer Mode habilitado para symlinks nativos, o instalador faz fallback automático para cópia (`ACTION|COPY|...`) mantendo idempotência (`KEEP`) e `--uninstall` reversível.

## Próximos passos (fora do escopo v1.0.0)

- Publicar tag de release `v1.0.0` após validação em uso real.
- Acompanhar a evolução do `orca-plugin.json`: quando o Orca liberar o campo `contributes.skills` (reservado/vazio no Orca 1.4.273), avaliar manifesto nativo apontando para as mesmas 4 pastas da raiz.
