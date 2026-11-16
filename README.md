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

> **Só no ambiente `local`.** No dev e no hml o `events-processing` não tem Ingress (o host
> `events-processing.alerta24-dev.com` nem resolve). Lá, as tarefas se testam pela coleção `alert-service`,
> pasta `[05]`. As pastas `[04]` e `[06]` pegam o `EVENTS_TI_DEVICE_ID` do env, gravado antes pelo
> `alert-service [03]`.

| Pasta | Cobertura |
|---|---|
| `[00] Saúde` | `/actuator/health` (sem auth) → `UP` |
| `[01] Telemetria` | `GET /api/v1/telemetries/{deviceId}` |
| `[02] Timelines` | `GET /api/v1/timelines` e `/consolidated-timelines/{deviceId}` |
| `[03] Status do Dispositivo` | `GET /api/v1/devices/status/{deviceId}` |
| `[04] Tasks` | `GET /api/v1/tasks/{deviceId}`, `/frequencies` e `/types`, que confere o catálogo da `main`: ids `1..6, 10, 11, 12`. Mais um `POST` agendado de Desligar Tomada (`type: 11`), opt-in por `TOMADA_ESCRITA_SENSIVEL=true` |
| `[05] Erros de Autenticação` | `[Erro]` telemetria sem `x-api-key` → 401 |
| `[06] Tomada Independente - catalogo da main (opt-in)` | `POST /api/v1/tasks` com 11, 10 e 12 no imediato, 12 no agendado, e dois `[Erro]`: Reiniciar com `duration: 0` → 400, e tipo 8 recusado. Os comandos só rodam com `TOMADA_ESCRITA_SENSIVEL=true` |

---

## Coleção `alert-service` — cobertura

Roda com `npm run test:alert` (ou `bash ./bin/run-tests.sh local alert-service`). Auth: `x-api-key`
cifrado (mesmo `d9Qk…`/`TomatoIsFruit000` do events) calculado no pre-request → `{{ALERT_API_KEY}}`.

| Pasta | Cobertura |
|---|---|
| `[00] Saúde` | `GET /actuator/health` (sem auth) → `UP` |
| `[01] Schemas Públicos` | `GET /api/v1/public/schema/users/types` (`{name,description}`) e `/support/subjects` (`{name,value}`) — exigem x-api-key, não JWT |
| `[02] Erros de Autenticação` | sem x-api-key → **403**; x-api-key inválida → **401**; `GET /api/v1/devices` sem JWT → **403**; `POST /auth/login` inválido → **500** (sem token) |
| `[03] Meus devices` | login do usuário do env (grava `ALERT_JWT` no env) e `GET /api/v1/devices`, que acha o `ALERT_TI_SERIAL` e grava `EVENTS_TI_DEVICE_ID` no env |
| `[04] Login do agent (PVD develop)` | `POST /auth/agent/login` com o serial, e os erros de serial e de senha |
| `[05] Tarefas e Tomada Independente - catalogo da main` | pelo proxy do alert: login, device, `GET /api/v1/tasks/types` (catálogo `1..6, 10, 11, 12`), `GET /api/v1/devices/{id}/tasks`, comandos 11, 10, 12 imediato e 12 agendado (opt-in por `TOMADA_ESCRITA_SENSIVEL=true`), e dois `[Erro]` |

> As pastas `[03]` a `[05]` só rodam com `ALERT_USER_LOGIN` e `ALERT_USER_PASSWORD` preenchidos. Sem eles,
> são puladas e o smoke continua verde. Ver CLAUDE.md para o modelo de auth completo.

---

## Validar o merge da `main` no dev (catálogo de tarefas novo)

Em 11/11 a `main` entrou na `develop-clamper` nos cinco serviços, e o catálogo de tarefas mudou: ids
1 a 6 da `main`, 7 e 8 vazios, 9 reservado e a **tomada em 10, 11 e 12** (antes, 7 a 9). O deploy no dev
foi feito em 16/11. Plano: `PI-0009-A24H` (fase 5) e `ADR-0009-A24H` v8, no `design-docs-power-view`.

**A cadeia de variáveis** (o que cada request consome e produz, as entradas manuais e a ordem dos cenários)
está no `RB-0003-A24H` do `design-docs-power-view`
(`documents/_independent_socket/code-first/Alerta24h/09_runbooks/`). Este roteiro é a sequência **S1** dele.

### 1. Preencher só as entradas manuais do env `dev`

`environments/dev.postman_environment.json` vai para o git com os segredos **vazios**. Preencha na sua
máquina (no Postman, em *Current value*, ou no arquivo **sem commitar**):

| Variável | O que é |
|---|---|
| `ALERT_API_KEY_RAW` | o `APP_HTTP_API_KEY` do dev (`ENV_FILE_DEV` do GitLab) |
| `ALERT_API_KEY_SECRET` | a chave AES do dev |
| `ALERT_USER_LOGIN`, `ALERT_USER_PASSWORD` | usuário do dev dono do UPS de bancada (serial `ALERT_TI_SERIAL` = `295010007306`) |
| `TOMADA_ESCRITA_SENSIVEL` | `false` por padrão. `true` manda os comandos de verdade e **corta energia da carga** |

**Não preencha** `ALERT_JWT` nem `EVENTS_TI_DEVICE_ID`: a própria pasta os grava no env a partir das
respostas. O `deviceId` esperado do PRM1500 no dev é `3e4a3dab-f3b4-4f3a-a021-f24e068a48dd`.

### 2. Rodar, numa execução só

```bash
# Só leitura (TOMADA_ESCRITA_SENSIVEL=false): login, device, catálogo e tarefas do device
bash ./bin/run-tests.sh dev alert-service '[05] Tarefas e Tomada Independente - catalogo da main'

# Com os comandos: troque TOMADA_ESCRITA_SENSIVEL para true no env e rode o mesmo comando
```

A ordem dentro da pasta é obrigatória: o **Login** grava `ALERT_JWT`, o **Device da tomada** grava
`EVENTS_TI_DEVICE_ID`, e os passos seguintes os usam. Se um deles falhar, os seguintes são pulados com o
motivo no console. **Rode sempre a pasta inteira**: no Newman, o que uma execução grava no env não passa
para a seguinte. No Postman, o env fica salvo.

Os scripts `npm run test:*` usam o env `local`. Para o dev, use o `run-tests.sh` como acima.

### 3. O que olhar no resultado

| Passo | Esperado | Se falhar |
|---|---|---|
| Tipos de task | catálogo `[1..6, 10, 11, 12]` | o deploy do events não é o do merge |
| Tarefas do device | `200` | **`500` indica tarefa antiga com `TURN_OFF_NOBREAK` no banco** (Q-02 do `PI-0009-A24H`) |
| Comandos | `200` com `taskId` | o proxy devolve `500` genérico para qualquer erro do events: o motivo está no log do pod do `alert-service` |
| `[Erro]` duration 0 e tipo 8 | recusados (`500` pelo proxy) | aceitos = a validação do events não está no deploy |

### 4. Conferir no fio e nos logs

O `200` prova que a nuvem aceitou e gravou. Para ver o que desce para o equipamento, deixe um assinante em
`pvd/<deviceId>/task` antes de rodar, e confira `tipoEvento` 10, 11 e 12, `duracao` e `targetOutlet`.
Para o acesso ao cluster (`kubectl`, namespaces `alerta24h` e `emqx`), ver o `DR-0014-A24H` §4.12 no
`design-docs-power-view`.

O UPS só executa certo depois que o firmware e o PVD forem ajustados ao catálogo novo (premissas P2 e P3
do `PI-0009-A24H`).

---

## Adicionar uma nova coleção (outro serviço)

1. Subir o serviço alvo (ver runbooks) e validar portas/auth.
2. Criar `collections/<serviço>.postman_collection.json` (schema v2.1.0).
3. Acrescentar as variáveis do serviço em `environments/local...json` (base URL + auth).
4. Documentar a cobertura aqui e, se necessário, um script em `package.json`.
