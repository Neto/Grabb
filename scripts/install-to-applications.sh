#!/bin/sh
# Substitui /Applications/Grabb.app pela build nova.
# Nunca cria "Grabb 2.app" nem copia para dentro do bundle antigo.
set -e

DEST="/Applications/Grabb.app"

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
  echo "Grabb.app não encontrado para instalar." >&2
  exit 1
fi

if [ ! -f "$APP/Contents/Info.plist" ]; then
  echo "Pacote inválido: $APP" >&2
  exit 1
fi

# Ferramentas (yt-dlp, ffmpeg, deno) vão dentro do .app.
HELPERS_SRC=""
if [ -n "${SRCROOT:-}" ] && [ -d "${SRCROOT}/Vendor/Helpers" ]; then
  HELPERS_SRC="${SRCROOT}/Vendor/Helpers"
elif [ -d "$(dirname "$0")/../Vendor/Helpers" ]; then
  HELPERS_SRC="$(cd "$(dirname "$0")/../Vendor/Helpers" && pwd)"
fi
if [ -n "$HELPERS_SRC" ] && [ -x "$HELPERS_SRC/yt-dlp.bundle/yt-dlp" ] && [ ! -x "$APP/Contents/Helpers/yt-dlp.bundle/yt-dlp" ]; then
  /bin/mkdir -p "$APP/Contents/Helpers"
  /usr/bin/rsync -a "$HELPERS_SRC/" "$APP/Contents/Helpers/"
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    ENT="${CODE_SIGN_ENTITLEMENTS:-}"
    if [ -n "${SRCROOT:-}" ] && [ -f "${SRCROOT}/Grabb/Grabb.entitlements" ]; then
      ENT="${SRCROOT}/Grabb/Grabb.entitlements"
    fi
    if [ -n "$ENT" ] && [ -f "$ENT" ]; then
      /usr/bin/codesign --force --deep --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --entitlements "$ENT" "$APP" >/dev/null 2>&1 || true
    else
      /usr/bin/codesign --force --deep --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$APP" >/dev/null 2>&1 || true
    fi
  fi
fi

/usr/bin/osascript -e 'quit app "Grabb"' >/dev/null 2>&1 || true
/usr/bin/killall Grabb >/dev/null 2>&1 || true

i=0
while /usr/bin/pgrep -x Grabb >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 25 ]; then
    /usr/bin/killall -9 Grabb >/dev/null 2>&1 || true
    break
  fi
  sleep 0.2
done
sleep 0.2

# Remove o bundle inteiro. cp -R em cima de um .app existente aninha Grabb.app/Grabb.app.
if [ -e "$DEST" ]; then
  /bin/rm -rf "$DEST" 2>/dev/null || true
fi
# Cópia instalada pelo .pkg pertence ao root: pede senha de administrador uma vez.
if [ -e "$DEST" ]; then
  /usr/bin/osascript -e 'do shell script "rm -rf /Applications/Grabb.app" with administrator privileges with prompt "O Grabb precisa remover a versão instalada pelo pacote para instalar a nova."' >/dev/null 2>&1 || true
fi
if [ -e "$DEST" ]; then
  echo "Não foi possível remover $DEST para substituir." >&2
  exit 1
fi

/usr/bin/ditto "$APP" "$DEST"
/usr/bin/xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
/usr/bin/touch "$DEST"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi

if [ -d "$DEST/Grabb.app" ]; then
  echo "Replace falhou: bundle aninhado em $DEST/Grabb.app" >&2
  exit 1
fi

echo "Substituído: $DEST"
