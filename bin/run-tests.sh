#!/bin/bash
# Executor de testes Newman para o ecossistema Alerta24h.
# Uso: ./bin/run-tests.sh <environment> [collection] [folder]
#   environment : nome do arquivo em environments/ (ex.: local)
#   collection  : nome do arquivo em collections/ sem extensão (ex.: events-processing).
#                 Se omitido, roda TODAS as coleções de collections/.
#   folder      : pasta específica dentro da coleção (ex.: '[01] Telemetria')

ENVIRONMENT=$1
COLLECTION_NAME=$2
FOLDER=$3

if [ -z "$ENVIRONMENT" ]; then
  echo "Uso: $0 <environment> [collection] [folder]"
  echo "Ambientes disponíveis: local"
  echo ""
  echo "Exemplos:"
  echo "  $0 local                                  # todas as coleções"
  echo "  $0 local events-processing                # só uma coleção"
  echo "  $0 local events-processing '[01] Telemetria'   # só uma pasta"
  exit 1
fi

ENV_FILE="environments/${ENVIRONMENT}.postman_environment.json"
if [ ! -f "$ENV_FILE" ]; then
  echo "Arquivo de ambiente não encontrado: $ENV_FILE"
  exit 1
fi

if [ -n "$COLLECTION_NAME" ]; then
  COLLECTIONS=("collections/${COLLECTION_NAME}.postman_collection.json")
else
  COLLECTIONS=(collections/*.postman_collection.json)
fi

OVERALL=0
for COLLECTION in "${COLLECTIONS[@]}"; do
  if [ ! -f "$COLLECTION" ]; then
    echo "Coleção não encontrada: $COLLECTION"
    OVERALL=1
    continue
  fi

  NAME=$(basename "$COLLECTION" .postman_collection.json)
  REPORT_DIR="report/${ENVIRONMENT}/${NAME}"
  mkdir -p "$REPORT_DIR"

  CMD="node_modules/.bin/newman run \"$COLLECTION\" \
    --environment \"$ENV_FILE\" \
    --reporter-htmlextra-title \"Alerta24h - ${NAME} (${ENVIRONMENT})\" \
    --reporter-htmlextra-export \"${REPORT_DIR}/index.html\" \
    -r htmlextra,cli,json \
    --reporter-json-export \"${REPORT_DIR}/result.json\""

  if [ -n "$FOLDER" ]; then
    CMD="$CMD --folder \"$FOLDER\""
  fi

  echo "================================================"
  echo " Alerta24h - Newman"
  echo " Coleção:   $NAME"
  echo " Ambiente:  $ENVIRONMENT"
  [ -n "$FOLDER" ] && echo " Pasta:     $FOLDER"
  echo " Relatório: ${REPORT_DIR}/index.html"
  echo "================================================"

  eval $CMD || OVERALL=1
done

echo ""
echo "================================================"
if [ $OVERALL -eq 0 ]; then
  echo " Todos os testes passaram!"
else
  echo " Há testes com falha. Verifique os relatórios em report/${ENVIRONMENT}/"
fi
echo "================================================"

exit $OVERALL
