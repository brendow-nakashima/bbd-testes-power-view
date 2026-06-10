# CLAUDE.md — Contexto do Framework de Testes (Alerta24h / bbd-tests)

Contexto **específico do ecossistema Alerta24h**. Leia antes de criar/modificar testes.

> Molde de referência: `C:\Users\nakashbr\Projects\bbd-tests` (mobi-smart). Os padrões gerais
> de Newman/Postman vêm de lá. Este arquivo documenta o que é específico do Alerta24h.

---

## O que é este projeto

Testes de API do ecossistema **Alerta24h** (microserviços Spring Boot) usando **Newman**
(runner CLI do Postman). Diferente do mobi-smart (API única, JWT), aqui há **vários serviços
com auth heterogênea** — uma coleção por serviço.

Documentação do sistema e como subir cada serviço: `../design-docs-power-view/documents/Alerta24h/`
(em especial os runbooks `09_runbooks/rb-0001` e `rb-0002`).

---

## Mapa do ecossistema (portas locais + auth)

| Serviço | Porta | Auth | Coleção |
|---|---|---|---|
| events-processing | 8082 | `x-api-key` **criptografado** (AES-128-ECB/PKCS5+Base64) | ✅ `events-processing` |
| alert-service | 8081 | `x-api-key` (mesmo AES; `ApiKeyFilter` em `/api/v1/*`) + JWT no que é `authenticated` | ✅ `alert-service` |
| admin-service | 8084 | JWT (login de usuário) | ⬜ a fazer |
| notification-service | 8083 | a confirmar | ⬜ a fazer |
| pvd-legacy-adapter | 8085 | `x-api-key` | ⬜ a fazer |
| gateway (nginx) | 8100 | roteia para os serviços | ⬜ a fazer |

> Portas conforme a proposta do RB-0002 (resolve a colisão default em 8080). Confirme a porta
> real de cada serviço no `.env`/run config antes de criar a coleção.

---

## Padrões estabelecidos

### 1. Uma coleção por serviço
`collections/<serviço>.postman_collection.json`. Pastas numeradas e descritivas em PT-BR:
`[00] Saúde`, `[01] <recurso>`, … e `[Erro] <cenário>` para casos negativos.

### 2. Auth por serviço (NÃO é um `[01] Auth` único)
Cada serviço tem seu mecanismo — não replique o fluxo login→Bearer do mobi-smart cegamente.

**events-processing — `x-api-key` criptografado:** o backend faz
`AES/ECB/PKCS5PADDING` + Base64 e **decripta** o header recebido (`ApiKeyFilter` + `AES.java`).
O header é gerado no **pre-request da coleção** via CryptoJS:
```javascript
var key = CryptoJS.enc.Utf8.parse(pm.environment.get('EVENTS_API_KEY_SECRET'));
var enc = CryptoJS.AES.encrypt(pm.environment.get('EVENTS_API_KEY_RAW'), key,
          { mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7 });
pm.collectionVariables.set('EVENTS_API_KEY', enc.toString());
```
Auth da coleção = `apikey` (`x-api-key` = `{{EVENTS_API_KEY}}`). Requests de health/erro
sobrescrevem com `auth: noauth`.

> O mesmo segredo `TomatoIsFruit000` é reutilizado em vários serviços (era `VITE_CRYPTO_KEY` no
> front). O `ALERT_API_KEY_RAW` é **o mesmo** `d9Qk…` do `EVENTS_API_KEY_RAW` (ambos = `APP_HTTP_API_KEY`).

**alert-service — `x-api-key` (mesmo AES) + JWT em camadas:** o `ApiKeyFilter` (registrado em
`/api/v1/*`, ordem `MIN_VALUE`) roda **antes** do Spring Security e exige o `x-api-key` cifrado —
**exceto** `/api/v1/users/activate` e `/api/v1/notificables/activate`. Depois, o Spring Security
aplica JWT: `/auth/**`, `/actuator/**`, swagger e `/api/v1/public/**` + `GET /api/v1/admin/**` são
`permitAll` (bastam o x-api-key); o restante de `/api/v1/**` exige também o Bearer JWT. A coleção
usa o pre-request CryptoJS (igual ao events) com `ALERT_API_KEY_RAW`/`ALERT_API_KEY_SECRET`.
**Status reais validados (2026-06-10, localhost:8081):** sem x-api-key → **403**; x-api-key inválida
→ **401**; endpoint `authenticated` sem JWT → **403**; `POST /auth/login` inválido → **500**.

> ⚠️ **JWT happy-path fora do smoke:** os usuários-seed da migration V4 **não logam** (senha
> placeholder → login 500), e o cadastro+ativação cria dados e depende de token de e-mail. Por isso
> a coleção do alert cobre só o que é estável e read-only (health + schemas públicos + erros de auth).

### 3. Pré-requisito de dados — device registrado
O events-processing rejeita device desconhecido. Use o **device-seed**
`00000000-0000-0000-0000-000000000001` (`EVENTS_DEVICE_ID`). Não invente UUID novo sem registrá-lo.

### 4. Ingestão MQTT é externa ao Newman
Newman é HTTP-only. Para alimentar dados via MQTT use `bin/mqtt-pub.sh` (publica no container
`mosquitto-mqtt-broker`). Tópicos: `a24h/{deviceId}/{startup|telemetry|event|keepalive}`, QoS 1,
payloads do contrato `code/sms-legrand-a24h-events-processing/docs/mqtt-firmware-contract.md`.

### 5. Variáveis de ambiente
Em `environments/local.postman_environment.json`. Prefixe por serviço (`EVENTS_*`, e futuramente
`ALERT_*`, `ADMIN_*`). Marque chaves/secrets com `"type": "secret"`.

### 6. Execução
```bash
bash ./bin/run-tests.sh local                       # todas as coleções
bash ./bin/run-tests.sh local events-processing     # uma coleção
bash ./bin/run-tests.sh local events-processing '[01] Telemetria'
```
Relatório HTML+JSON em `report/local/<coleção>/`. Saída 0=OK / 1=falha.

---

## Decisões de design

- **Idioma PT-BR** em nomes de testes, comentários e docs.
- **Escopo incremental**: começou pelo events-processing (o serviço já validado). Cada serviço
  novo = nova coleção, sem mexer nas existentes.
- **Auth derivada, não hardcoded**: o `x-api-key` criptografado é calculado em runtime a partir
  de `RAW`+`SECRET` — assim a troca de key não exige reexportar a coleção.
- **Assertions ancoradas em respostas reais**: as formas (`meters`/`status`, arrays de
  `{id,description}`, etc.) foram verificadas contra o serviço no ar, não presumidas.
- **MQTT fora da coleção**: ingestão via `bin/mqtt-pub.sh`; o Newman cobre só a leitura HTTP.
