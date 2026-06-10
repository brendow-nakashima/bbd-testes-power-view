# Alerta24h — Testes de API (Newman/Postman)

Framework de testes de API para o ecossistema **Alerta24h** (microserviços) usando Newman e
Postman Collections. Mesmo molde do projeto `bbd-tests` (mobi-smart), adaptado para vários
serviços e auth heterogênea.

---

## Estrutura

```
bbd-tests/
├── bin/
│   ├── run-tests.sh                    # executor (suporta ambiente + coleção + pasta)
│   └── mqtt-pub.sh                     # helper p/ publicar no MQTT (Newman não fala MQTT)
├── collections/
│   ├── events-processing.postman_collection.json   # smoke do events-processing
│   └── alert-service.postman_collection.json       # smoke do alert-service (CORE)
├── environments/
│   └── local.postman_environment.json  # localhost (portas/keys validadas)
├── report/                             # relatórios gerados (git-ignored)
├── package.json
├── README.md
└── CLAUDE.md
```

> Escopo atual: **events-processing** e **alert-service**. Os demais serviços (admin, notification,
> pvd) entram como novas coleções em `collections/` conforme forem subindo (ver CLAUDE.md).

---

## Pré-requisitos

- Node.js >= 18 e npm >= 9
- O serviço **events-processing rodando em `localhost:8082`** com a infra (MySQL/Mosquitto/
  RabbitMQ) de pé — ver `design-docs-power-view/.../09_runbooks/rb-0001` e `rb-0002`.

---

## Instalação

```bash
npm run setup        # ou: npm install
```

---

## Rodar os testes

```bash
# Todas as coleções — ambiente local
npm run test:local

# Só o events-processing
npm run test:events

# Diretamente (suporta coleção e pasta específicas)
bash ./bin/run-tests.sh local events-processing
bash ./bin/run-tests.sh local events-processing '[01] Telemetria'
```

Relatórios em `report/local/<coleção>/index.html` (HTML) e `result.json` (JSON p/ CI).
Código de saída: `0` = tudo passou, `1` = houve falha.

---

## Autenticação — `x-api-key` criptografado

O events-processing **não usa Bearer/JWT**: ele espera o header `x-api-key` **criptografado**
(`AES-128-ECB/PKCS5` + Base64 da API key, com a chave-secreta `TomatoIsFruit000`).

O valor é gerado **automaticamente** no *pre-request da coleção* (CryptoJS), a partir de duas
variáveis de ambiente, e exposto como `{{EVENTS_API_KEY}}`:

| Variável | Descrição |
|---|---|
| `EVENTS_API_KEY_RAW` | a API key em texto (igual ao `APP_HTTP_API_KEY` do `.env`) |
| `EVENTS_API_KEY_SECRET` | a chave AES (`TomatoIsFruit000`) |
| `EVENTS_API_KEY` | **derivada** — o header criptografado pronto (não editar) |

Para mudar a key, troque `EVENTS_API_KEY_RAW`/`EVENTS_API_KEY_SECRET` — o header é recalculado.

---

## Pré-requisito de dados — device registrado

O events-processing **rejeita devices desconhecidos** (a leitura retorna `No devices found`).
Em local existe um **device-seed** (`EVENTS_DEVICE_ID = 00000000-0000-0000-0000-000000000001`,
serial `SN-TEST-001`) criado por migration. As coleções usam esse id por padrão.

Devices reais entram via admin-service (fila `persist-device-queue`) — fora do escopo local.

---

## Ingestão MQTT (fora do Newman)

Newman não fala MQTT. Para exercitar a ingestão (startup/telemetry/event/keepalive) antes de
validar pela API HTTP, use o helper:

```bash
bash ./bin/mqtt-pub.sh telemetry                 # device-seed, payload exemplo
bash ./bin/mqtt-pub.sh startup
bash ./bin/mqtt-pub.sh event   00000000-0000-0000-0000-000000000001
```

Depois rode os testes HTTP para ver o dado persistido.

---

## Coleção `events-processing` — cobertura

| Pasta | Cobertura |
|---|---|
| `[00] Saúde` | `/actuator/health` (sem auth) → `UP` |
| `[01] Telemetria` | `GET /api/v1/telemetries/{deviceId}` |
| `[02] Timelines` | `GET /api/v1/timelines` e `/consolidated-timelines/{deviceId}` |
| `[03] Status do Dispositivo` | `GET /api/v1/devices/status/{deviceId}` |
| `[04] Tasks` | `GET /api/v1/tasks/{deviceId}`, `/types`, `/frequencies` |
| `[05] Erros de Autenticação` | `[Erro]` telemetria sem `x-api-key` → 401 |

---

## Coleção `alert-service` — cobertura

Roda com `npm run test:alert` (ou `bash ./bin/run-tests.sh local alert-service`). Auth: `x-api-key`
cifrado (mesmo `d9Qk…`/`TomatoIsFruit000` do events) calculado no pre-request → `{{ALERT_API_KEY}}`.

| Pasta | Cobertura |
|---|---|
| `[00] Saúde` | `GET /actuator/health` (sem auth) → `UP` |
| `[01] Schemas Públicos` | `GET /api/v1/public/schema/users/types` (`{name,description}`) e `/support/subjects` (`{name,value}`) — exigem x-api-key, não JWT |
| `[02] Erros de Autenticação` | sem x-api-key → **403**; x-api-key inválida → **401**; `GET /api/v1/devices` sem JWT → **403**; `POST /auth/login` inválido → **500** (sem token) |

> **Read-only por design:** o fluxo JWT (registrar → ativar por e-mail → login) cria dados e os
> usuários-seed da V4 não logam — fora do smoke. Ver CLAUDE.md para o modelo de auth completo.

---

## Adicionar uma nova coleção (outro serviço)

1. Subir o serviço alvo (ver runbooks) e validar portas/auth.
2. Criar `collections/<serviço>.postman_collection.json` (schema v2.1.0).
3. Acrescentar as variáveis do serviço em `environments/local...json` (base URL + auth).
4. Documentar a cobertura aqui e, se necessário, um script em `package.json`.
