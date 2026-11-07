#!/bin/sh
# Empacota yt-dlp, ffmpeg, ffprobe e deno em Vendor/Helpers (arm64, sem Homebrew no Mac de destino).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPERS="$ROOT/Vendor/Helpers"
mkdir -p "$HELPERS/lib"

if [ -x "$HELPERS/ffmpeg" ] && [ -x "$HELPERS/ffprobe" ] && [ -x "$HELPERS/yt-dlp.bundle/yt-dlp" ] && [ -x "$HELPERS/deno" ]; then
  echo "Helpers já existem em $HELPERS ($(du -sh "$HELPERS" | awk '{print $1}'))"
  exit 0
fi

if [ ! -x /opt/homebrew/opt/ffmpeg/bin/ffmpeg ]; then
  echo "ffmpeg do Homebrew não encontrado. Rode: brew install ffmpeg" >&2
  exit 1
fi
if [ ! -x /opt/homebrew/opt/deno/bin/deno ]; then
  echo "deno do Homebrew não encontrado. Rode: brew install deno" >&2
  exit 1
fi
if ! command -v dylibbundler >/dev/null 2>&1; then
  echo "Instale dylibbundler: brew install dylibbundler" >&2
  exit 1
fi

cp /opt/homebrew/opt/ffmpeg/bin/ffmpeg /opt/homebrew/opt/ffmpeg/bin/ffprobe "$HELPERS/"
chmod u+w "$HELPERS/ffmpeg" "$HELPERS/ffprobe"
dylibbundler -od -b -x "$HELPERS/ffmpeg" -d "$HELPERS/lib" -p @executable_path/lib/ >/dev/null
dylibbundler -od -b -x "$HELPERS/ffprobe" -d "$HELPERS/lib" -p @executable_path/lib/ >/dev/null

cp /opt/homebrew/opt/deno/bin/deno "$HELPERS/deno.tmp"
mv -f "$HELPERS/deno.tmp" "$HELPERS/deno"

# O binário oficial (yt-dlp_macos) é um PyInstaller onefile: se autoextrai pra /tmp a cada
# execução, ~7s de startup toda vez só nisso. Montamos onedir (já descompactado) localmente —
# mesma versão do yt-dlp, mesmo conteúdo, só não precisa mais extrair nada em runtime.
if [ ! -x /opt/homebrew/bin/python3.11 ]; then
  echo "python3.11 do Homebrew não encontrado. Rode: brew install python@3.11" >&2
  exit 1
fi
YT_BUILD_VENV="/tmp/grabb-ytdlp-build-venv"
YT_BUILD_WORK="/tmp/grabb-ytdlp-build-work"
YT_BUILD_OUT="/tmp/grabb-ytdlp-build-out"
rm -rf "$YT_BUILD_VENV" "$YT_BUILD_WORK" "$YT_BUILD_OUT"
/opt/homebrew/bin/python3.11 -m venv "$YT_BUILD_VENV"
"$YT_BUILD_VENV/bin/pip" install --quiet --upgrade pip
"$YT_BUILD_VENV/bin/pip" install --quiet pyinstaller yt-dlp
YTDLP_MAIN="$("$YT_BUILD_VENV/bin/python3" -c "import yt_dlp, os; print(os.path.join(os.path.dirname(yt_dlp.__file__), '__main__.py'))")"
"$YT_BUILD_VENV/bin/pyinstaller" --onedir --name yt-dlp \
  --distpath "$YT_BUILD_OUT" --workpath "$YT_BUILD_WORK" --noconfirm "$YTDLP_MAIN" >/dev/null
rm -rf "$HELPERS/yt-dlp.bundle"
cp -R "$YT_BUILD_OUT/yt-dlp" "$HELPERS/yt-dlp.bundle"
rm -rf "$YT_BUILD_VENV" "$YT_BUILD_WORK" "$YT_BUILD_OUT"
# A extensão .bundle (+ Info.plist) é obrigatória: é o que faz o codesign do app, mais tarde,
# tratar essa pasta como um pacote já assinado em vez de tentar validar o conteúdo de
# _internal/ por dentro (e falhar com "code object is not signed at all").
cat > "$HELPERS/yt-dlp.bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>yt-dlp</string>
  <key>CFBundleIdentifier</key><string>com.mentorneto.ytdlp</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
</dict>
</plist>
PLIST
chmod +x "$HELPERS/yt-dlp.bundle/yt-dlp" "$HELPERS/deno" "$HELPERS/ffmpeg" "$HELPERS/ffprobe"

echo "Helpers prontos em $HELPERS ($(du -sh "$HELPERS" | awk '{print $1}'))"
