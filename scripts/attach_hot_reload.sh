#!/usr/bin/env bash
# Start a flutter attach process that listens for file changes and sends 'r' to trigger hot reload
PID_FILE=$1
if [ -z "${PID_FILE}" ]; then
  echo "attach_hot_reload: se requiere path al archivo con el PID del flutter run principal"
  exit 1
fi

if [ ! -f "${PID_FILE}" ]; then
  echo "attach_hot_reload: PID file no encontrado: ${PID_FILE}"
  exit 1
fi

FLUTTER_RUN_PID=$(cat "${PID_FILE}" 2>/dev/null)
if [ -z "${FLUTTER_RUN_PID}" ]; then
  echo "attach_hot_reload: PID vacío"
  exit 1
fi

echo "attach_hot_reload: esperando 1s para asegurar que flutter run esté listo (PID=${FLUTTER_RUN_PID})"
sleep 1

# Intentar encontrar el device id desde flutter processes (fallback simple)
DEVICE_ID=$(flutter devices --machine 2>/dev/null | awk -F '"' '/id/ {print $4; exit}' || true)
echo "attach_hot_reload: detected device id: ${DEVICE_ID}"

# Lanzar flutter attach en background y capturar su PID
(flutter attach ${DEVICE_ID:+-d $DEVICE_ID} --no-resident) &
ATTACH_PID=$!
echo "attach_hot_reload: flutter attach started (PID=${ATTACH_PID})"

# Usar inotifywait para detectar cambios y enviar 'r' a attach process stdin
if ! command -v inotifywait >/dev/null 2>&1; then
  echo "attach_hot_reload: inotifywait no disponible. Instala inotify-tools para habilitar hot-reload-on-save.";
  wait ${ATTACH_PID}
  exit 0
fi

WATCH_DIR="$(pwd)/lib"
echo "attach_hot_reload: observando ${WATCH_DIR} para cambios..."

while inotifywait -e close_write,moved_to,create -r "${WATCH_DIR}" >/dev/null 2>&1; do
  sleep 0.12
  # Enviar 'r' al proceso attach (escribiendo al fd 0 del proceso attach)
  if kill -0 ${ATTACH_PID} >/dev/null 2>&1; then
    FD0="/proc/${ATTACH_PID}/fd/0"
    if [ -e "${FD0}" ] && [ -w "${FD0}" ]; then
      printf 'r' > "${FD0}" || echo "attach_hot_reload: fallo al escribir a ${FD0}"
      echo "attach_hot_reload: enviado 'r' al attach (PID=${ATTACH_PID})"
    else
      echo "attach_hot_reload: stdin descriptor no disponible para PID ${ATTACH_PID}"
    fi
  else
    echo "attach_hot_reload: attach ya no está en ejecución. Saliendo."
    break
  fi
  sleep 0.4
done

wait ${ATTACH_PID}
