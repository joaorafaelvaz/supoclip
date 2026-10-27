# SupoClip no ambiente BVIP

Clone de https://github.com/FujiwaraChoki/supoclip configurado para
**transcrição local com Whisper** e **seleção de clipes com a API da Anthropic
(Claude Sonnet 5.5)**. Nenhum código do projeto foi alterado: o backend já
suporta `anthropic:claude-sonnet-5-5` (saída estruturada nativa) e
`TRANSCRIPTION_PROVIDER=whisper`.

## O que foi configurado (`.env`, não versionado)

| Variável | Valor | Motivo |
|---|---|---|
| `TRANSCRIPTION_PROVIDER` | `whisper` | Transcrição local, sem AssemblyAI |
| `WHISPER_MODEL_SIZE` | `medium` | Padrão do projeto; baixado na primeira transcrição (~1,5 GB) |
| `TRANSCRIPTION_LANGUAGE` | vazio | Whisper detecta o idioma por vídeo (`pt` força português) |
| `BACKEND_CPU_ONLY` | `true` | Sem GPU; torch CPU |
| `LLM` | `anthropic:claude-sonnet-5-5` | Sonnet 5.5 via API da Anthropic |
| `ANTHROPIC_API_KEY` | comentada | Vem do ambiente do host (abaixo) |
| `BETTER_AUTH_SECRET`, `BACKEND_AUTH_SECRET`, `APP_SETTINGS_ENCRYPTION_KEY` | gerados (`openssl rand -hex 32`) | Substituem os placeholders |

Arquivos adicionados ao repositório (branch `bvip-setup`):

- `docker-compose.override.yml`: publica o Postgres em `127.0.0.1:5432` para
  rodar backend/worker nativamente contra o container.
- `scripts/bvip-native.sh`: `start | stop | status` para backend, worker e
  frontend nativos.

## Chave da Anthropic

Defina `ANTHROPIC_API_KEY` como variável/segredo do ambiente BVIP. A linha
correspondente no `.env` está comentada de propósito: assim nem o Docker
Compose nem o script sobrescrevem o valor do host com uma string vazia.
Com a chave ausente, o backend sobe, mas a criação de tarefas falha com
"Selected LLM provider is Anthropic, but ANTHROPIC_API_KEY is not set".

Alternativa sem reiniciar: após criar o primeiro usuário, a tela `/admin`
grava a chave nas runtime settings (criptografadas com
`APP_SETTINGS_ENCRYPTION_KEY`).

## Como rodar neste ambiente (validado)

Neste contêiner, o daemon do Docker não sobe sozinho e o tráfego HTTPS de
dentro dos containers passa por um interceptador TLS cujo certificado as
imagens não têm. Resultado: `docker compose up --build` falha ao baixar
dependências, e containers do app não alcançariam `api.anthropic.com`.
Postgres e Redis em container funcionam (não precisam de rede externa);
backend, worker e frontend rodam nativamente no host, que confia no
certificado.

```bash
cd /home/user/supoclip
dockerd > /tmp/dockerd.log 2>&1 &          # daemon manual; espelho mirror.gcr.io já em /etc/docker/daemon.json
docker compose up -d postgres redis
(cd backend && uv sync --frozen --extra cpu)          # torch CPU + whisper + anthropic SDK
(cd frontend && pnpm install --frozen-lockfile)
scripts/bvip-native.sh start                         # backend :8000, worker, frontend :3107
scripts/bvip-native.sh status
```

O backend cria e migra o esquema no startup; o script só inicia o worker
depois de `/health/db` responder (evita a corrida que gera
"relation media_deletions does not exist").

Verificado nesta sessão: `torch 2.11.0+cpu`, Whisper rodando em CPU pelo
código do projeto, `AnthropicModel("claude-sonnet-5-5")` construído pelo
backend, `/health/db` saudável, worker sem erros, frontend respondendo em
`/api/auth/get-session` e `/`.

## Num host com Docker normal (VPS, máquina própria)

```bash
docker compose up -d --build
docker compose logs -f backend worker
```

Frontend: http://localhost:3107 — API: http://localhost:8000/docs

## Persistência

Este contêiner de sessão é efêmero: clone, `.env`, venv, imagens e o modelo
Whisper baixado somem quando ele é recolhido. Para que novas sessões já
encontrem tudo: adicione o repositório (ou o fork com a branch `bvip-setup`)
como fonte do ambiente BVIP, coloque as variáveis acima nas variáveis do
ambiente e `ANTHROPIC_API_KEY` nos segredos, e use um setup script com os
comandos de instalação da seção anterior.
