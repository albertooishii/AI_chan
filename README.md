# AI-chan

Asistente conversacional con llamadas de voz Realtime y chat.

## Configuración (.env)

Crea un archivo `.env` en la raíz con:

```
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=AIza...
# Opcional: clave de respaldo si la primaria no tiene cuota o retorna 403/429
GEMINI_API_KEY_FALLBACK=AIza...

# Voz por defecto
OPENAI_VOICE=sage
```

Notas:
- `.env` ya está ignorado en `.gitignore`.
- Si `GEMINI_API_KEY` falla por cuota/permisos (401/403/429), el código reintenta automáticamente con `GEMINI_API_KEY_FALLBACK` si está definida.

## Desarrollo

1. Instala dependencias: `flutter pub get`
2. Ejecuta: `flutter run`

Requiere Flutter estable y un dispositivo/emulador activo.
