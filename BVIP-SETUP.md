# SupoClip no ambiente BVIP

Configuração aplicada neste clone (arquivo `.env`, não versionado):

| Variável | Valor | Motivo |
|---|---|---|
| `TRANSCRIPTION_PROVIDER` | `whisper` | Transcrição local, sem AssemblyAI |
| `WHISPER_MODEL_SIZE` | `medium` | Padrão do projeto; baixado na primeira transcrição (~1,5 GB) |
| `TRANSCRIPTION_LANGUAGE` | vazio | Whisper detecta o idioma por vídeo (defina `pt` para forçar português) |
| `BACKEND_CPU_ONLY` | `true` | Sem GPU no ambiente; usa torch CPU |
| `LLM` | `anthropic:claude-sonnet-5-5` | Seleção de clipes via API da Anthropic (Sonnet 5.5) |
| `ANTHROPIC_API_KEY` | vazio no `.env` | Vem da variável de ambiente do host (ver abaixo) |
| `BETTER_AUTH_SECRET`, `BACKEND_AUTH_SECRET`, `APP_SETTINGS_ENCRYPTION_KEY` | gerados com `openssl rand -hex 32` | Substituem os placeholders do exemplo |

## Chave da Anthropic

O Docker Compose dá prioridade ao ambiente do shell sobre o `.env`. Basta definir
`ANTHROPIC_API_KEY` como variável de ambiente (segredo) do ambiente BVIP e
subir a stack; `backend` e `worker` a recebem via `docker-compose.yml`.

Alternativa sem reiniciar: depois de criar o primeiro usuário (admin), a tela
`/admin` permite gravar a chave nas "runtime settings" (criptografadas com
`APP_SETTINGS_ENCRYPTION_KEY`).

Sem a chave, o backend sobe, mas a criação de tarefas falha com
"Selected LLM provider is Anthropic, but ANTHROPIC_API_KEY is not set".

## Subir a stack

```bash
cd /home/user/supoclip
docker compose up -d --build
docker compose logs -f backend worker
```

Frontend: http://localhost:3107 — API: http://localhost:8000/docs

Neste contêiner o daemon do Docker precisa ser iniciado manualmente
(`dockerd &`) e o Docker Hub limita pulls anônimos; o espelho
`https://mirror.gcr.io` foi configurado em `/etc/docker/daemon.json`.

## Rodar sem Docker (backend)

```bash
cd backend
uv sync --frozen --extra cpu
.venv/bin/uvicorn src.main:app --port 8000
.venv/bin/arq src.workers.tasks.WorkerSettings
```

Requer Postgres e Redis acessíveis (veja `docs/development.md`).
