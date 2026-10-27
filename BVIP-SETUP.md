# Deploy no servidor BVIP — supoclip.barbearia.vip

SupoClip com **transcrição local (Whisper)** e **seleção de clipes pela API da
Anthropic (Claude Sonnet 5.5)**, publicado em `https://supoclip.barbearia.vip`.
O backend fica em `https://api.supoclip.barbearia.vip` porque o navegador envia
os uploads de vídeo diretamente para ele.

Arquivos deste repositório usados aqui:

- `docker-compose.override.yml`: frontend em modo produção, senha do Postgres
  aplicada nos quatro lugares que o compose exige, volume para o modelo Whisper.
- `deploy/Caddyfile`: proxy reverso com HTTPS automático.

## 0. Pré-requisitos no servidor

- Linux x86_64, Docker Engine + Compose v2.24 ou mais novo, `git`, `openssl`.
- Portas 80 e 443 chegando ao servidor (redirecione no roteador se for rede local).
- DNS: registros `A` para `supoclip.barbearia.vip` e `api.supoclip.barbearia.vip`
  apontando para o IP público do servidor.
- Hardware: Whisper `medium` em CPU usa ~5 GB de RAM; 8 GB+ e 4 núcleos+ ficam
  confortáveis. Um vídeo de 60 min leva dezenas de minutos para transcrever em CPU.

## 1. Clonar

```bash
sudo mkdir -p /opt/supoclip && sudo chown "$USER" /opt/supoclip
git clone https://github.com/joaorafaelvaz/supoclip.git /opt/supoclip
cd /opt/supoclip
```

## 2. Criar o `.env`

```bash
cp .env.example .env
```

Edite o `.env` e deixe estas linhas com estes valores (as demais podem ficar
como no exemplo):

```env
# Transcrição local
TRANSCRIPTION_PROVIDER=whisper
WHISPER_MODEL_SIZE=medium
TRANSCRIPTION_LANGUAGE=            # vazio = detecta o idioma; "pt" força português
BACKEND_CPU_ONLY=true              # false só se o servidor tiver GPU NVIDIA (ver §7)

# LLM
LLM=anthropic:claude-sonnet-5-5
ANTHROPIC_API_KEY=sk-ant-...       # sua chave

# Domínio público
FRONTEND_PORT=3107
FRONTEND_BUILD_TARGET=runner
NODE_ENV=production
NEXT_PUBLIC_APP_URL=https://supoclip.barbearia.vip
BETTER_AUTH_URL=https://supoclip.barbearia.vip
NEXT_PUBLIC_API_URL=https://api.supoclip.barbearia.vip
CORS_ORIGINS=https://supoclip.barbearia.vip

# Segredos (gere cada um com: openssl rand -hex 32)
BETTER_AUTH_SECRET=
BACKEND_AUTH_SECRET=
APP_SETTINGS_ENCRYPTION_KEY=
# Senhas de banco e cache (openssl rand -hex 24)
POSTGRES_PASSWORD=
REDIS_PASSWORD=

SELF_HOST=true
DISABLE_SIGN_UP=false              # mude para true depois de criar sua conta
```

`NEXT_PUBLIC_API_URL` não aparece no `.env.example`, mas o `docker-compose.yml`
a lê. Valores `NEXT_PUBLIC_*` entram na imagem do frontend no build: se mudar
algum deles depois, rode `docker compose up -d --build frontend`.

## 3. Subir a stack

```bash
docker compose up -d --build
docker compose logs -f backend worker
```

A primeira construção baixa torch CPU e dependências (alguns minutos). O
modelo Whisper (~1,5 GB) é baixado na primeira transcrição e fica no volume
`whisper_cache`. Confira:

```bash
docker compose ps
curl -s http://127.0.0.1:8000/health/db        # {"status":"healthy","database":"connected"}
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3107/api/auth/get-session   # 200
```

Se o `worker` registrar `relation "media_deletions" does not exist` logo após
subir, é só a ordem de inicialização; o backend cria o esquema e o erro para
de aparecer.

## 4. Proxy reverso com HTTPS (Caddy)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy emite os certificados Let's Encrypt sozinho. Teste:

```bash
curl -I https://supoclip.barbearia.vip
curl -s https://api.supoclip.barbearia.vip/health
```

Se preferir nginx, os pontos que importam são: `client_max_body_size 4G` e
`proxy_read_timeout 3600` no host da API, e `proxy_buffering off` para o SSE
de progresso.

## 5. Primeira conta e bloqueio de cadastro

1. Abra `https://supoclip.barbearia.vip`, crie sua conta (o primeiro usuário
   pode ser promovido a admin pelo banco, ver abaixo) e envie um vídeo de teste.
2. Feche o cadastro:

```bash
sed -i 's/^DISABLE_SIGN_UP=.*/DISABLE_SIGN_UP=true/' .env
docker compose up -d frontend
```

Para marcar seu usuário como admin (libera `/admin`, onde a chave da Anthropic
também pode ser trocada sem reiniciar):

```bash
docker compose exec -T postgres psql -U supoclip -d supoclip \
  -c "UPDATE users SET is_admin = true WHERE email = 'seu@email'"
```

## 6. Operação

```bash
docker compose logs -f worker          # acompanhar processamento
docker compose restart backend worker  # após mudar variáveis do backend
docker compose exec -T postgres pg_dump -U supoclip supoclip > backup-$(date +%F).sql
```

Atualizações: `git pull` e `docker compose up -d --build`. Se a atualização
trouxer arquivos novos em `backend/migrations/` ou
`frontend/prisma/migrations/`, aplique-os antes conforme `docs/setup.md`
(o `init.sql` só roda na criação do volume do Postgres). Nunca use
`docker compose down -v`: apaga o banco e os clipes.

## 7. Opcional: GPU NVIDIA

Com driver NVIDIA e `nvidia-container-toolkit` instalados, use
`BACKEND_CPU_ONLY=false` no `.env` e acrescente ao `docker-compose.override.yml`,
em `backend` e `worker`:

```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

Depois `docker compose up -d --build backend worker`. O Whisper passa a usar a
GPU automaticamente.

## Limites e ressalvas

- Vídeos: `MAX_VIDEO_DURATION=5400` (90 min) e `MAX_VIDEO_UPLOAD_BYTES` (4 GB)
  no `.env`.
- Links do YouTube usam `yt-dlp`; alguns vídeos exigem o sidecar `bgutil`
  (`COMPOSE_PROFILES=youtube-proxy` e `YOUTUBE_POT_PROVIDER_URL=http://bgutil:4416`).
  Uploads diretos não dependem disso.
- Um túnel Cloudflare no plano gratuito limita o corpo das requisições a
  100 MB e quebraria os uploads; exponha 80/443 diretamente.
