#!/bin/bash
# Publica um payload MQTT no broker local (container) para alimentar o events-processing.
# Newman/Postman NÃO falam MQTT — use este helper para gerar a ingestão antes de validar via HTTP.
#
# Uso: ./bin/mqtt-pub.sh <stream> [deviceId] [json]
#   stream   : startup | telemetry | event | keepalive   (default: telemetry)
#   deviceId : UUID do device JÁ registrado               (default: device-seed)
#   json     : payload customizado (se omitido, usa um exemplo válido do contrato)
#
# Requisitos: container 'mosquitto-mqtt-broker' de pé (docker compose do events-processing).
# Lembre: o deviceId precisa existir na tabela 'devices' (o events-processing rejeita desconhecidos).

set -e
export MSYS_NO_PATHCONV=1

STREAM="${1:-telemetry}"
DEV="${2:-00000000-0000-0000-0000-000000000001}"
JSON="$3"

if [ -z "$JSON" ]; then
  case "$STREAM" in
    startup)
      JSON="{\"deviceId\":\"$DEV\",\"agentId\":\"8b5f8c2e-1234-5678-9abc-def012345678\",\"timestamp\":\"2026-04-10T14:30:00Z\"}" ;;
    telemetry)
      JSON="{\"deviceId\":\"$DEV\",\"meters\":[{\"tipo\":\"consumo\",\"valor\":\"123.45\",\"data\":\"2026-04-10T14:30:00\"}]}" ;;
    event)
      JSON="{\"deviceId\":\"$DEV\",\"events\":[{\"tipo\":1,\"data\":\"2026-04-10T14:30:00.000Z\"}]}" ;;
    keepalive)
      JSON="{\"deviceId\":\"$DEV\",\"agentId\":\"8b5f8c2e-1234-5678-9abc-def012345678\",\"lastDate\":1712756400123}" ;;
    *)
      echo "Stream inválido: $STREAM (use startup|telemetry|event|keepalive)"; exit 1 ;;
  esac
fi

TOPIC="a24h/$DEV/$STREAM"
echo "Publicando em $TOPIC (QoS 1):"
echo "  $JSON"
docker exec mosquitto-mqtt-broker mosquitto_pub -h 127.0.0.1 -p 1883 -q 1 -t "$TOPIC" -m "$JSON"
echo "OK — acompanhe o processamento no console do events-processing (IntelliJ)."
