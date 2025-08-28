#!/usr/bin/env bash
# AI_chan Development Runner con Auto Hot Reload Real y Salida Visible

echo "🚀 AI_chan Development Environment"
echo "🔥 Hot Reload AUTOMÁTICO activado - Guarda cualquier archivo .dart"
echo ""

# Verificar si inotify-tools está disponible
if ! command -v inotifywait >/dev/null 2>&1; then
    echo "⚠️  Para hot reload automático, instala: sudo apt install inotify-tools"
    echo "🔄 Ejecutando en modo manual (usa 'r' para hot reload)"
    echo ""
    flutter run -d linux --debug
    exit 0
fi

echo "✅ inotify-tools detectado - Hot reload automático disponible"
echo ""

# Cleanup function
cleanup() {
  echo ""
  echo "🧹 Cleaning up..."
  if [ -n "$FLUTTER_PID" ]; then
    kill $FLUTTER_PID 2>/dev/null || true
  fi
  if [ -n "$WATCHER_PID" ]; then
    kill $WATCHER_PID 2>/dev/null || true
  fi
  mkdir -p /tmp/ai_chan 2>/dev/null || true
  rm -f /tmp/ai_chan/flutter_input_pipe 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM

# Crear un named pipe para comunicación con Flutter  
mkfifo /tmp/ai_chan/flutter_input_pipe 2>/dev/null || true

echo "🚀 Iniciando Flutter con salida visible..."
echo "📺 Salida de Flutter:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Función para enviar hot reload
send_hot_reload() {
    echo ""
    echo "🔥 [AUTO HOT RELOAD] Cambio detectado: $1"
    if [ -n "$FLUTTER_PID" ] && kill -0 "$FLUTTER_PID" 2>/dev/null; then
        # Enviar SIGUSR1 a Flutter para hot reload (método alternativo)
        kill -SIGUSR1 "$FLUTTER_PID" 2>/dev/null || {
            # Si SIGUSR1 no funciona, usar el pipe
            echo 'r' > /tmp/ai_chan/flutter_input_pipe 2>/dev/null || true
        }
        echo "✅ [AUTO HOT RELOAD] Comando enviado"
    fi
    echo ""
}

# Iniciar Flutter normalmente
flutter run -d linux --debug &
FLUTTER_PID=$!

# Esperar un poco para que Flutter arranque
sleep 3

# Iniciar el monitor de archivos en segundo plano
echo ""
echo "👀 [MONITOR] Hot reload automático activo - guarda archivos .dart"
inotifywait -m -r -e close_write --format '%w%f' lib/ test/ --include='.*\.dart$' 2>/dev/null | while read file; do
    send_hot_reload "$file"
    sleep 1  # Evitar spam de reloads
done &
WATCHER_PID=$!

# Esperar a que termine Flutter
wait $FLUTTER_PID

cleanup
