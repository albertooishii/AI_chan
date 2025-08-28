#!/usr/bin/env bash
set -euo pipefail

TMPDIR="${TMPDIR:-/tmp}"
BASE="$TMPDIR/ai_chan"

print_usage() {
  cat <<'USAGE'
Uso: clean_tmp_ai_chan.sh [--dry-run|-n] [--yes|-y]

Opciones:
  -n, --dry-run   Listar lo que se borraría sin eliminar nada.
  -y, --yes       Borrar sin pedir confirmación interactiva.
  -h, --help      Mostrar esta ayuda.

El script trabaja con el directorio: $TMPDIR/ai_chan
USAGE
}

DRY_RUN=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -y|--yes) FORCE=1; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Opción desconocida: $1"; print_usage; exit 2 ;;
  esac
done

# Seguridad básica: asegurar que el directorio objetivo es el esperado
if [[ -z "$BASE" ]]; then
  echo "Ruta base vacía, abortando." >&2
  exit 2
fi

# Asegurarse de que el basename sea 'ai_chan' para reducir riesgo de borrados erróneos
if [[ "$(basename "$BASE")" != "ai_chan" ]]; then
  echo "Directorio objetivo inesperado: $BASE" >&2
  exit 2
fi

if [[ ! -d "$BASE" ]]; then
  echo "No existe el directorio: $BASE";
  echo "Nada que limpiar.";
  exit 0
fi

echo "Directorio objetivo: $BASE"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "--- DRY RUN: mostrar contenido que se borraría ---"
  # Listar con detalle, limitado a profundidad razonable
  find "$BASE" -mindepth 1 -maxdepth 4 -print
  echo "--- FIN DRY RUN ---"
  exit 0
fi

if [[ $FORCE -ne 1 ]]; then
  read -r -p "¿Borrar todo el contenido de $BASE ? [y/N] " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) echo "Abortado por el usuario."; exit 0 ;;
  esac
fi

# Ejecutar borrado seguro
echo "Borrando contenido de $BASE ..."
# Borrar contenido pero no el propio directorio para mantener la estructura
# Usamos globbing seguro
shopt -s dotglob || true
if [[ -d "$BASE" ]]; then
  rm -rf -- "$BASE"/* || true
fi

# Si el directorio quedó vacío, opcionalmente eliminarlo (comentado por seguridad)
# rmdir "$BASE" 2>/dev/null || true

echo "Limpieza completada."
