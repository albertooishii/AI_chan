#!/usr/bin/env bash
set -euo pipefail

# Normaliza imports a los modelos canónicos y reemplaza uses de models.AiImage -> AiImage
# Ejecuta desde la raíz del repo: ./scripts/normalize-models.sh

DRY_RUN=false
COMMIT_CHANGES=true

echo "PWD=$(pwd)"

# Buscar archivos que importen package:ai_chan/core/models/ fuera de lib/core/models
FILES=$(git grep -l "package:ai_chan/core/models/" -- ':!lib/core/models/*' || true)

if [ -z "$FILES" ]; then
  echo "No se encontraron archivos para procesar."
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  echo "Dry run: archivos detectados:";
  echo "$FILES";
  exit 0
fi

echo "Archivos a procesar:";
printf "%s\n" $FILES

MODIFIED=()

for f in $FILES; do
  echo "\nProcesando: $f"
  # 1) Reemplazar index.dart -> models.dart
  perl -0777 -pe 's/package:ai_chan\/core\/models\/index\.dart/package:ai_chan\/core\/models.dart/g' -i "$f" || true
  # 2) Reemplazar package:ai_chan/core/models/<file>.dart -> barrel
  perl -0777 -pe 's/package:ai_chan\/core\/models\/[a-z0-9_]+\.dart/package:ai_chan\/core\/models.dart/g' -i "$f" || true
  # 3) Quitar alias imports 'as models' en el barrel
  sed -E -i "s/import +(['\"]package:ai_chan\/core\/models\.dart['\"]) +as +models;/import \1;/g" "$f" || true
  # 4) Reemplazar usos puntuales models.AiImage -> AiImage
  sed -E -i 's/\bmodels\.AiImage\b/AiImage/g' "$f" || true
  # 5) Si hay still references to 'package:ai_chan/core/models/index.dart' replace them
  sed -E -i "s/package:ai_chan\/core\/models\/index\.dart/package:ai_chan\/core\/models.dart/g" "$f" || true

  # Record if file changed
  if ! git diff --quiet -- "$f"; then
    MODIFIED+=("$f")
    git add "$f"
    echo " -> Modificado: $f"
  else
    echo " -> Sin cambios: $f"
  fi
done

if [ "${#MODIFIED[@]}" -eq 0 ]; then
  echo "No hubo archivos modificados."
else
  echo "\nArchivos modificados:"; printf "%s\n" "${MODIFIED[@]}"
fi

# Ejecutar análisis y tests enfocados
echo "\nEjecutando flutter analyze..."
flutter analyze || ( echo "Analyzer falló"; exit 1 )

echo "\nEjecutando tests enfocados..."
flutter test test/core/ai_image_test.dart test/migration/import_sanity_test.dart test/chat/chat_provider_test.dart -r expanded || ( echo "Tests fallaron"; exit 1 )

if [ "$COMMIT_CHANGES" = true ]; then
  if [ "${#MODIFIED[@]}" -gt 0 ]; then
    git commit -m "chore(migration): normalize core model imports and replace models.AiImage usages" || echo "No se pudo commitear (tal vez nada que commitear)"
    echo "Cambios commiteados."
  fi
fi

echo "Script terminado."
