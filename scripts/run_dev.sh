#!/usr/bin/env bash
# Complete Flutter development runner - todo en uno CHACHI PIRULI
# Everything you want: logs + colors + hot reload + interactive + non-blocking

echo "🚀 Starting AI_chan development environment..."
echo "✨ Features enabled:" 
echo "   🐛 Debug mode with colors"
echo "   🔄 Hot reload con 'r'" 
echo "   📝 Real-time logs with colors"
echo "   🖥️ Interactive commands"
echo "   🎯 Non-blocking VS Code"
echo ""

# Trap para limpieza al salir
cleanup() {
  echo ""
  echo "🧹 Cleaning up..."
  [ -n "${FLUTTER_PID}" ] && kill ${FLUTTER_PID} 2>/dev/null || true
  rm -f .flutter_run_pid
  exit 0
}
trap cleanup SIGINT SIGTERM

# Lanzar flutter run en foreground con colores e interactividad
flutter run -d linux --debug &
FLUTTER_PID=$!
echo "[run_dev] flutter pid: ${FLUTTER_PID}"
echo ${FLUTTER_PID} > .flutter_run_pid

# Esperar flutter y mostrar que está listo
wait ${FLUTTER_PID}
cleanup