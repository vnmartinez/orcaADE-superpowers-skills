# Especificação Técnica — Plugin Multiagente (`orcaADE-superpowers-skills`)

**Data:** 2026-11-25
**Repositório:** `orcaADE-superpowers-skills`
**Branch:** `main`
**Status:** Proposta (aguardando aprovação no gate humano do orquestrador)

---

## 1. Objetivo e Escopo

Transformar as 4 skills deste repositório (`orca-superpowers-orchestrator`, `orca-superpowers-orchestration-auto`, `orca-superpowers-review-loop`, `orca-superpowers-merge`) em um **plugin/bundle multiagente** instalável com **um único comando** em **todos os CLIs que o Orca ADE permite instalar**, de forma idempotente, atualizável, reversível e cross-platform (Windows via Git Bash, macOS e Linux).

### O que entra no escopo

- Manifesto declarativo do bundle na raiz de `plugin/` (`plugin/manifest.json`) com versão SemVer, lista de skills e mapa de destinos compatível com os 42 agentes suportados pelo Orca 1.4.273.
- Documentação de instalação e operação por agente (`plugin/README.md`).
- Instalador e desinstalador cross-platform em **bash puro** (`scripts/install-skills.sh`) replicando o layout nativo do `orca skills install` (`--dry-run`, `--force` com backup, `--uninstall`, `--local`, `--agent`, `--skill`, `--copy`, `--list`, `--agents-file`).
- Suíte de testes TDD em **bash puro** (`tests/test-plugin-installer.sh`) + fixture sem PII (`tests/fixtures/plugin-agents-minimal.json`) com smoke tests em `HOME` e projeto temporários.
- Atualização da seção `## Instalação` do `README.md` raiz para promover o comando único do instalador mantendo as instruções manuais atuais como alternativa.

### O que NÃO entra no escopo (Não-objetivos)

- Alterar o conteúdo, protocolo TUI, gate humano, roteamento ou aviso de conclusão das 4 skills existentes (`*/SKILL.md` e `*/README.md`).
- Publicar em catálogo remoto do Orca (`orca-catalog.json`), GitHub Releases ou npm/registry externo (documentado como próximo passo).
- Criar plugin TypeScript/Node de UI ou hook dentro do Orca Desktop (justificado na Seção 2).
- Exigir qualquer runtime além de Git Bash/bash POSIX + Orca CLI opcional.

---

## 2. Abordagens Consideradas e Decisões Arquiteturais

### Fatos verificados no Orca 1.4.273 desta máquina

1. **`orca-plugin.json` (`orca skills get orca-plugin-authoring --reference references/manifest.md`):** o campo `contributes.skills` é explicitamente **reservado e deve permanecer vazio** (`Reserved (must stay empty arrays): agentHarnesses, skills, mcpServers, taskSources, connections, sidebarCards`). Além disso, `ids` iniciados por `orca-` são reservados ao catálogo oficial, e qualquer plugin que execute código (`trusted-worker`) exige aprovação explícita (`--approve`) e capacidades privilegiadas (`terminal:send`), sem API nativa de filesystem para instalar skills nos CLIs.
2. **`orca skills install`:** instala apenas as 11 skills embutidas no binário do Orca (`--skill orca-superpowers-orchestrator` retorna `Unknown skill`), mas expõe via `--dry-run --json` o **layout canônico exato** que o Orca usa para os **42 agentes** suportados.
3. **`orca agent installed --worktree active --json`:** retorna dinamicamente os agentes instalados no host (nesta máquina: `claude` [default], `codex`, `opencode`, `opencode2`, `antigravity`, `copilot`).

### Abordagens avaliadas

| Abordagem | Como funciona | Trade-offs | Decisão |
|---|---|---|---|
| **(a) Plugin Orca puro (`orca plugin create`)** | Pacote com `orca-plugin.json` (`hook`/`panel`/`worker-panel`) que empacota e instala as skills. | **Inviável hoje:** `contributes.skills` é reservado (vazio obrigatório no Orca 1.4.273); `id` com prefixo `orca-` bloqueado; exige `trusted-worker` + `--approve`; não funciona headless/sem app Orca aberto. | Descartada |
| **(b) Bundle de skills multiagente + instalador bash próprio** | Manifesto declarativo `plugin/manifest.json` + `scripts/install-skills.sh` em bash puro replicando o layout oficial do `orca skills install` e descobrindo agentes via `orca agent installed`. | Zero dependências extras (quem tem Orca tem Git); cobre todos os 42 CLIs do Orca (e futuros CLIs via `.agents/skills`); 1 comando, idempotente, `--dry-run`, backup em `--force` e `--uninstall`; sem necessidade de aprovação de worker privilegiado. | **Escolhida** |
| **(c) Plugin Orca como distribuição + instalador bash como mecanismo** | Adiciona `orca-plugin.json` + worker TS apenas para invocar o script bash no terminal. | YAGNI com alta fricção: exige `trusted-worker`, `terminal:send`, `--approve` e toolchain TS do Orca apenas para encapsular um comando `bash scripts/install-skills.sh`, mantendo `contributes.skills` vazio. | Descartada (revisitar quando o Orca liberar `contributes.skills`) |

### Resumo das 7 decisões (uma linha cada)

1. **Forma do artefato:** Escolhida **(b) bundle declarativo (`plugin/manifest.json`) + instalador bash (`scripts/install-skills.sh`)**, porque `contributes.skills` em `orca-plugin.json` ainda é reservado/vazio no Orca 1.4.273 e `orca skills install` só instala skills internas do Orca.
2. **Destinos:** Descoberta dinâmica via `orca agent installed --worktree active --json` (ou `--agent` / fallback `$HOME`), gravando cópia canônica em `.agents/skills/<skill>` (30 agentes + `universal` + agentes futuros) e links/cópias nos 12 agentes com pasta própria mapeados pelo Orca 1.4.273.
3. **Instalação idempotente e reversível:** Suporte completo a `--dry-run`, `--force` (backup em `.agents/.orca-superpowers-backups/<timestamp>/`), `--uninstall` e recibo de estado `.agents/.orca-superpowers-installed`, garantindo atualização in-place do que é gerenciado sem nunca apagar skills de terceiros.
4. **Fonte única de verdade:** As 4 pastas na raiz do repositório continuam sendo a única fonte do conteúdo das skills; `plugin/manifest.json` centraliza `version`, `skills[]`, caminhos de layout e `agentPaths`, tornando atualizar equivalente a rodar o instalador novamente.
5. **Runtime:** 100% **bash + utilitários POSIX do Git** (`awk`, `sed`, `grep`, `tr`, `cut`, `cp`, `mv`, `rm`, `mkdir`, `ln`, `find`, `cksum`), sem `python`, `python3`, `node`, `jq`, `pwsh` ou `powershell`.
6. **Cross-platform:** Windows (Git Bash), macOS e Linux com LF (`\n`), caminhos exclusivamente `$HOME/...` com `/` (sem `%APPDATA%`, `%TEMP%`, `$env:USERPROFILE` ou `\`) e fallback automático de symlink para cópia quando o SO não permite symlinks nativos.
7. **O que NÃO muda:** As 4 skills existentes (`*/SKILL.md` e `*/README.md`), `scripts/get-quotas.sh` e `tests/test-orchestration-auto.sh` permanecem intactos; o `README.md` raiz promove o comando único preservando as instruções manuais atuais como alternativa.

---

## 3. Estrutura de Arquivos

| Caminho | Responsabilidade |
|---|---|
| `plugin/manifest.json` | Manifesto canônico do bundle: `manifestVersion`, `id`, `name`, `version` (`1.0.0`), `description`, `repository`, `license`, `layout` (`sharedDir`, `backupDir`, `stateFile`), `skills[]` (4 nomes na raiz) e `agentPaths{}` (12 agentes com pasta dedicada, `global` e `local`). |
| `plugin/README.md` | Documentação operacional do plugin: comando único, referência de flags, tabela de destinos globais/locais dos agentes do Orca, atualização, rollback via backup e próximos passos de publicação. |
| `scripts/install-skills.sh` | Instalador/desinstalador em bash puro + POSIX `awk` (compatível com BSD `awk` no macOS e GNU `awk` no Linux/Git Bash). |
| `tests/fixtures/plugin-agents-minimal.json` | Fixture sem PII com `claude` (default), `codex`, `antigravity` e `future-cli` (agente não mapeado em `agentPaths`, provando roteamento dinâmico para `.agents/skills`). |
| `tests/test-plugin-installer.sh` | Suíte TDD em bash puro cobrindo sintaxe, LF, zero runtimes proibidos, integridade de `plugin/manifest.json`, zero PII e smoke tests completos em `HOME` e diretório de projeto temporários. |
| `README.md` (raiz) | Atualizar `## Instalação` destacando `bash scripts/install-skills.sh` e link para `plugin/README.md`, mantendo os blocos atuais (bash e PowerShell dos 5 destinos) em `### Instalação manual (alternativa)`. |

---

## 4. Contrato do Manifesto (`plugin/manifest.json`)

```json
{
  "manifestVersion": 1,
  "id": "superpowers-skills",
  "name": "Orca Superpowers Skills",
  "version": "1.0.0",
  "description": "Multi-agent superpowers orchestration skills bundle for all CLIs supported by Orca ADE.",
  "repository": "https://github.com/vnmartinez/orcaADE-superpowers-skills",
  "license": "MIT",
  "layout": {
    "sharedDir": ".agents/skills",
    "backupDir": ".agents/.orca-superpowers-backups",
    "stateFile": ".agents/.orca-superpowers-installed"
  },
  "skills": [
    "orca-superpowers-orchestrator",
    "orca-superpowers-orchestration-auto",
    "orca-superpowers-review-loop",
    "orca-superpowers-merge"
  ],
  "agentPaths": {
    "claude": { "global": ".claude/skills", "local": ".claude/skills" },
    "antigravity": { "global": ".gemini/config/skills", "local": ".agents/skills" },
    "cursor": { "global": ".cursor/skills", "local": ".agents/skills" },
    "droid": { "global": ".factory/skills", "local": ".factory/skills" },
    "continue": { "global": ".continue/skills", "local": ".continue/skills" },
    "trae": { "global": ".trae-cn/skills", "local": ".trae-cn/skills" },
    "grok": { "global": ".grok/skills", "local": ".grok/skills" },
    "aug": { "global": ".augment/skills", "local": ".augment/skills" },
    "zcode": { "global": ".zcode/skills", "local": ".agents/skills" },
    "codebuddy": { "global": ".codebuddy/skills", "local": ".codebuddy/skills" },
    "kiro": { "global": ".kiro/skills", "local": ".kiro/skills" },
    "openclaude": { "global": ".openclaude/skills", "local": ".openclaude/skills" }
  }
}
```

### Regras de mapeamento de destinos (fiel ao `orca skills install` 1.4.273)

- **Cópia canônica compartilhada (`layout.sharedDir` = `.agents/skills`):** sempre instalada primeiro. Atende nativamente os **30 agentes shared** do Orca (`codex`, `opencode`, `opencode2`, `copilot`, `gemini`, `kimi`, `amp`, `cline`, `goose`, `kilo`, `devin`, `mistral-vibe`, `qwen-code`, `muse`, `autohand`, `crush`, `command-code`, `rovo`, `openclaw`, `pi`, `mimo-code`, `omp`, `prime-agent`, `qoder`, `qoder-cn`, `codebuff`, `freebuff`, `ante`, `jcode`, `dsh`), o alvo `universal` e **qualquer agente futuro** retornado por `orca agent installed` que não tenha pasta dedicada em `agentPaths`.
- **12 agentes com pasta própria global (`agentPaths`):** recebem link (ou cópia em fallback) apontando para a cópia canônica `.agents/skills/<skill>`.
  - **Nota sobre Antigravity (`antigravity`):** usa `~/.gemini/config/skills/<skill>` (o destino oficial do Orca 1.4.273, fora da pasta do plugin `superpowers` em `~/.gemini/config/plugins/superpowers/skills` que é apagada a cada `agy plugin install`).
- **Comportamento quando a pasta do agente não existe:**
  - **Global (padrão, base `$HOME`):** cria o diretório de destino (`mkdir -p`) para cada agente detectado e instala o link/cópia.
  - **Local (`--local`, base `$PWD` ou `--target-dir <dir>`):** instala a cópia canônica em `<projeto>/.agents/skills/<skill>` e **só** cria link em pasta própria de agente (ex.: `<projeto>/.claude/skills/<skill>`) quando o diretório-pai do agente (`<projeto>/.claude`) **já existir** no projeto — sem poluir o repositório com pastas de CLIs não usados. Agentes cujo `local` é `.agents/skills` (`antigravity`, `cursor`, `zcode`) já ficam cobertos pela cópia canônica sem link redundante.

---

## 5. Contrato do Instalador (`scripts/install-skills.sh`)

### Interface CLI

```bash
bash scripts/install-skills.sh [opções]
```

| Flag | Descrição |
|---|---|
| `--skill <nome>` | Instala/remove apenas a skill informada (repetível; padrão = todas as listadas em `plugin/manifest.json`). Erro (exit `1`) se o nome não existir no manifesto. |
| `--agent <lista>` | Lista separada por vírgula de IDs de agente (ex.: `claude,codex,antigravity`) ou `universal` (apenas pasta compartilhada `.agents/skills`). Padrão = descoberta em tempo de execução. |
| `--local` | Instala no projeto atual (`$PWD`, ou diretório indicado por `--target-dir`) em vez de `$HOME`. |
| `--target-dir <dir>` | Diretório-alvo do projeto quando usado com `--local` (útil para automação e testes sem `cd`). |
| `--dry-run` | Calcula e imprime todo o plano sem criar, mover, copiar ou remover nenhum arquivo ou diretório. |
| `--force` | Substitui cópias pré-existentes não gerenciadas movendo cada uma (com todos os seus arquivos) para `<base>/<backupDir>/<YYYYMMDD-HHMMSS>/<rel_path>` antes de instalar (ou antes de remover no `--uninstall`). |
| `--uninstall` | Remove apenas skills gerenciadas pelo plugin (links/cópias nos agentes e cópia canônica, respeitando `--skill` e `--agent`), preservando integralmente skills de terceiros e cópias manuais não gerenciadas. |
| `--copy` | Força cópia em vez de symlink nos destinos de agente (em qualquer SO). |
| `--agents-file <path>` | Lê a lista de agentes instalados de um arquivo JSON no formato de `orca agent installed --json` (modo offline/testes). |
| `--list` | Imprime nome, versão e lista de skills do manifesto e sai com `0`. |
| `-h`, `--help` | Exibe ajuda de uso e sai com `0`. |

### Ordem de descoberta de agentes (nunca fixa)

1. `--agent <lista>` informado pelo usuário (`universal` → somente cópia canônica).
2. `--agents-file <path>` (falha com exit `1` se arquivo não existir).
3. `orca agent installed --worktree active --json` (se `orca` estiver no `PATH` e retornar `agents[].id`).
4. **Fallback sem Orca:** detecta no diretório-base quais diretórios-pai de `agentPaths` já existem (ex.: `$HOME/.claude`, `$HOME/.gemini/config`, `$HOME/.cursor`) e sempre inclui o compartilhado (`.agents/skills`).

### Assinatura de diretório, Symlink vs Cópia e Arquivo de Estado

- **Digest determinístico POSIX (`dir_digest`):** percorre todos os arquivos regulares do diretório (ordenados com `LC_ALL=C`), aplica `cksum` por arquivo + caminho relativo e reduz com `cksum`, produzindo `<crc>-<bytes>` idêntico em macOS, Linux e Windows Git Bash sem depender de `sha256sum`/`shasum`.
- **Materialização em destinos de agente:**
  - Sem `--copy`: tenta criar symlink real apontando para `<base>/.agents/skills/<skill>` (no Windows Git Bash usando `MSYS=winsymlinks:nativestrict ln -s` e verificando `[ -L "$dest" ]`). Se o SO recusar symlink (ex.: Windows sem Developer Mode), faz fallback automático para cópia (`cp -R`) e registra `copy` no estado.
  - Com `--copy`: usa `cp -R` diretamente e registra `copy`.
- **Arquivo de estado (`<base>/.agents/.orca-superpowers-installed`, sem PII):**
  - Guarda apenas caminhos relativos a `<base>` (nunca `$HOME` expandido, usuário ou host):
    ```text
    # orca-superpowers-skills state v1
    CANONICAL|<skill>|<rel_path>|<version>|<digest>
    TARGET|<agent>|<skill>|<rel_path>|<link|copy>|<version>|<digest>
    ```
- **Regras de idempotência, conflito e desinstalação:**
  - **Gerenciado igual à fonte (mesmo digest e versão):** `KEEP`.
  - **Gerenciado desatualizado (nova versão ou conteúdo alterado na fonte):** `UPDATE` in-place (atualiza cópia canônica, links/cópias e recibo), sem precisar de `--force`.
  - **Existente não gerenciado, mas idêntico à fonte:** adota no recibo (`KEEP`).
  - **Existente não gerenciado com conteúdo divergente:**
    - Sem `--force`: `SKIP` com aviso em stderr indicando `--force` (não modifica nem remove nada; exit `0`).
    - Com `--force`: move a pasta inteira para `<base>/<backupDir>/<timestamp>/<rel_path>` (`BACKUP`), imprime o destino do backup e instala.
  - **`--uninstall`:**
    - Remove somente caminhos de skills listadas no manifesto que estejam no arquivo de estado **ou** sejam symlinks apontando para `<base>/.agents/skills/<skill>`.
    - Cópias manuais divergentes não gerenciadas: `SKIP` (ou `BACKUP` + `REMOVE` com `--force`).
    - Skills de terceiros (qualquer nome fora de `plugin/manifest.json`) são **100% intocadas**.
    - Quando `--agent <x>` é passado junto com `--uninstall` (sem `universal`), remove apenas os destinos daqueles agentes, mantendo o canônico se outros agentes ainda o referenciarem.

### Saída estruturada e códigos de saída

```text
PLUGIN|superpowers-skills|1.0.0|<global|local>|<apply|dry-run>|agents:<lista-ou-universal>
ACTION|<INSTALL|UPDATE|LINK|COPY|KEEP|SKIP|BACKUP|REMOVE>|<skill>|<rel_path>|<detalhe>
SUMMARY|installed=<n>|updated=<n>|linked=<n>|copied=<n>|kept=<n>|skipped=<n>|backed_up=<n>|removed=<n>
```

- Exit `0`: sucesso (incluindo `--dry-run`, `--help`, `--list` e avisos `SKIP`).
- Exit `1`: erro operacional (manifesto ausente/inválido, skill desconhecida, `--agents-file` ausente, falha de I/O).
- Exit `2`: flag desconhecida ou valor obrigatório omitido.

---

## 6. Estratégia de Verificação e TDD (Bash Puro)

Suíte `bash tests/test-plugin-installer.sh` (zero dependências externas além do Git Bash/POSIX), somada à suíte existente `bash tests/test-orchestration-auto.sh`:

1. **Integridade estática e portabilidade:**
   - `bash -n` e terminação LF (`\n`, sem CRLF) em `scripts/install-skills.sh` e `tests/test-plugin-installer.sh`.
   - Zero ocorrências de `python`, `python3`, `node`, `jq`, `pwsh`, `powershell`, `%APPDATA%`, `%TEMP%`, `$env:USERPROFILE` ou PII (`@`, `C:\Users`) no instalador, no manifesto, nas fixtures e em `plugin/README.md`.
   - Validação de `plugin/manifest.json` em POSIX `awk` (JSON balanceado, versão SemVer, `layout` completo, todas as 4 skills existem na raiz com `SKILL.md`, todos os 12 `agentPaths` têm `global` e `local`).
2. **Smoke tests isolados em `HOME` temporário (`mktemp -d`):**
   - `--list` exibe id, versão e as 4 skills.
   - `--dry-run` imprime o plano esperado sem criar `.agents/skills` nem pastas de agente.
   - Instalação com `--agents-file tests/fixtures/plugin-agents-minimal.json` instala as 4 skills (incluindo `orca-superpowers-orchestration-auto/scripts/get-quotas.sh`) em `$TMP_HOME/.agents/skills`, cria destinos em `.claude/skills` e `.gemini/config/skills`, atende `codex` e `future-cli` pelo shared sem erro e grava `.orca-superpowers-installed` sem PII.
   - Idempotência: 2ª execução resulta em `installed=0`, `updated=0`, `kept>0`, `backed_up=0`.
   - `--agent universal` cria apenas `.agents/skills` (sem `.claude/skills` nem `.gemini/config/skills`).
   - Conflito não gerenciado: pré-criar cópia divergente com arquivo extra → execução padrão emite `SKIP` e preserva o arquivo extra; `--force` move para `.agents/.orca-superpowers-backups/...` preservando o arquivo extra e instala a versão canônica.
   - Atualização in-place: simular versão anterior no arquivo de estado → rodar instalador novamente atualiza sem `--force` (`updated>0`, `backed_up=0`).
   - `--uninstall`: remove apenas skills gerenciadas (links + canônico + estado) e preserva intacta uma skill de terceiro (`third-party-skill`) tanto em `.agents/skills` quanto em `.claude/skills`.
   - Fallback `--copy`: força cópia nos agentes, mantém idempotência (`KEEP`) e desinstalação limpa (`REMOVE`).
   - Modo `--local --target-dir <tmp_proj>`: cria `.agents/skills` e cria link apenas em `.claude/skills` (pasta `.claude/` pré-existente), sem criar `.cursor/`, `.kiro/` ou `.gemini/`.
3. **Documentação e retrocompatibilidade:**
   - `plugin/README.md` cobre comando único, todas as flags principais, destinos por CLI, atualização e próximos passos de publicação.
   - `README.md` raiz promove `bash scripts/install-skills.sh` e mantém a alternativa manual dos 5 destinos.
   - `bash tests/test-orchestration-auto.sh` continua 100% verde sem qualquer modificação.

---

## 7. Próximos Passos (Fora de Escopo)

- Publicar release tag `v1.0.0` no GitHub (`vnmartinez/orcaADE-superpowers-skills`) após validação em uso real.
- Acompanhar a evolução do `orca-plugin.json`: assim que o Orca liberar o campo `contributes.skills` (hoje reservado/vazio no Orca 1.4.273), avaliar adicionar um `orca-plugin.json` declarativo apontando para as mesmas 4 pastas da raiz sem duplicar arquivos.
