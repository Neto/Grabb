#!/bin/sh
# Copia yt-dlp, ffmpeg, ffprobe e deno (Vendor/Helpers) para dentro do app recém-buildado.
# Não toca em /Applications.
set -e

if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${FULL_PRODUCT_NAME:-}" ]; then
  APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
  case "${TARGET_BUILD_DIR}" in
    *Index.noindex*|*Preview*|*Previews*)
      exit 0
      ;;
  esac
else
  APP="${1:-}"
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "Grabb.app não encontrado para empacotar helpers." >&2
  exit 1
fi

if [ ! -f "$APP/Contents/Info.plist" ]; then
  echo "Pacote inválido: $APP" >&2
  exit 1
fi

HELPERS_SRC=""
if [ -n "${SRCROOT:-}" ] && [ -d "${SRCROOT}/Vendor/Helpers" ]; then
  HELPERS_SRC="${SRCROOT}/Vendor/Helpers"
elif [ -d "$(dirname "$0")/../Vendor/Helpers" ]; then
  HELPERS_SRC="$(cd "$(dirname "$0")/../Vendor/Helpers" && pwd)"
fi
if [ -n "$HELPERS_SRC" ] && [ -x "$HELPERS_SRC/yt-dlp.bundle/yt-dlp" ]; then
  /bin/mkdir -p "$APP/Contents/Helpers"
  /usr/bin/rsync -a --delete "$HELPERS_SRC/" "$APP/Contents/Helpers/"
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    HELPERS_ENT=""
    if [ -n "${SRCROOT:-}" ] && [ -f "${SRCROOT}/scripts/helpers.entitlements" ]; then
      HELPERS_ENT="${SRCROOT}/scripts/helpers.entitlements"
    elif [ -f "$(dirname "$0")/helpers.entitlements" ]; then
      HELPERS_ENT="$(dirname "$0")/helpers.entitlements"
    fi
    # Assina as .dylib do ffmpeg/ffprobe primeiro, com o mesmo Team ID — sem isso, hardened
    # runtime recusa carregá-las (Team ID diferente do binário que as carrega).
    if [ -d "$APP/Contents/Helpers/lib" ]; then
      find "$APP/Contents/Helpers/lib" -name '*.dylib' -print0 | xargs -0 -I{} /usr/bin/codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY}" {} >/dev/null 2>&1 || true
    fi
    # yt-dlp (PyInstaller) e deno (V8/JIT) travam sob hardened runtime sem permissão de JIT —
    # assina os dois com entitlements próprios, nunca com --deep a partir do app (que aplicaria
    # os entitlements do app, sem allow-jit, e quebraria o solver de desafio JS do YouTube).
    # yt-dlp agora é uma pasta onedir (yt-dlp.bundle/, com Info.plist) em vez de onefile — onefile
    # se autoextrai a cada execução (~7s de startup toda chamada); onedir já vem descompactado.
    # A extensão .bundle é obrigatória: sem ela o codesign do app tenta validar o conteúdo de
    # _internal/ (centenas de .so + um .zip) por dentro e falha; com ela, trata a pasta como um
    # pacote já assinado e só confere o selo. Ordem: binários de _internal primeiro (exceto o
    # Python.framework, que é assinado como framework à parte), depois a pasta .bundle inteira.
    if [ -d "$APP/Contents/Helpers/yt-dlp.bundle" ] && [ -n "$HELPERS_ENT" ]; then
      find "$APP/Contents/Helpers/yt-dlp.bundle/_internal" -type f -perm -111 -print0 | while IFS= read -r -d '' f; do
        case "$f" in
          */Python.framework/*) ;;
          *)
            case "$(/usr/bin/file -b "$f")" in
              Mach-O*)
                /usr/bin/codesign --force --options runtime --entitlements "$HELPERS_ENT" --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$f" >/dev/null 2>&1 || true
                ;;
            esac
            ;;
        esac
      done
      if [ -d "$APP/Contents/Helpers/yt-dlp.bundle/_internal/Python.framework" ]; then
        /usr/bin/codesign --force --options runtime --entitlements "$HELPERS_ENT" --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$APP/Contents/Helpers/yt-dlp.bundle/_internal/Python.framework" >/dev/null 2>&1 || true
      fi
      /usr/bin/codesign --force --options runtime --entitlements "$HELPERS_ENT" --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$APP/Contents/Helpers/yt-dlp.bundle" >/dev/null 2>&1 || true
    fi
    if [ -x "$APP/Contents/Helpers/deno" ] && [ -n "$HELPERS_ENT" ]; then
      /usr/bin/codesign --force --options runtime --entitlements "$HELPERS_ENT" --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$APP/Contents/Helpers/deno" >/dev/null 2>&1 || true
    fi
    for b in ffmpeg ffprobe; do
      if [ -x "$APP/Contents/Helpers/$b" ]; then
        /usr/bin/codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$APP/Contents/Helpers/$b" >/dev/null 2>&1 || true
      fi
    done
  fi
fi

echo "Helpers embutidos em: $APP/Contents/Helpers"
