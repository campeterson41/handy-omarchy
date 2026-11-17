#!/usr/bin/env bash
# Handy dictation for Omarchy: local speech to text, a recording indicator in the
# top bar, terminal-aware paste, and optional LLM cleanup.
# Everything installs under your home folder. No sudo. Undo with ./uninstall.sh
set -euo pipefail

HANDY_VERSION="0.10.0"
SHA_amd64="20661c16b0b9e1b7dc5020be463f2b17f654bfeaf0ba1d7032bc4b77b268ec6c"
SHA_aarch64="e76ee45a404009319046878e314e94a7f431b3808179b3b05a410477154d8aa6"
MODEL_ID="handy-computer/parakeet-tdt-0.6b-v3-gguf/parakeet-tdt-0.6b-v3-Q8_0.gguf"
MODEL_FILE="parakeet-tdt-0.6b-v3-Q8_0.gguf"
MODEL_URL="https://huggingface.co/handy-computer/parakeet-tdt-0.6b-v3-gguf/resolve/85ac09ea12fc4b1112fa76810059364bc6adc9de/$MODEL_FILE"
MODEL_SHA="5859f77944efcd8eafa23a6350731960b2b55b2203df51f319665c807d802cc7"

CLEANUP=0; CLEANUP_MODEL="anthropic/claude-haiku-5.5"; BINDS=1; F9=1; TAKE_F9=0; MODEL=1; BAR_SECTION="center"
usage() {
  cat <<'U'
Usage: ./install.sh [options]

  --with-cleanup        Also install the LLM cleanup bridge (needs an OpenRouter API key)
  --cleanup-model ID    OpenRouter model for cleanup (default anthropic/claude-haiku-5.5)
  --bar-section NAME    Bar section for the widget: left, center or right (default center)
  --no-binds            Do not add any shortcuts
  --no-f9               Add only Super+Ctrl+X, leave F9 alone
  --take-f9             Use F9 for hold-to-talk even if something else has it
  --no-model            Do not download the Parakeet model (pick one inside Handy instead)
  -h, --help            Show this help
U
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-cleanup) CLEANUP=1 ;;
    --cleanup-model) CLEANUP_MODEL="${2:?missing model id}"; shift ;;
    --bar-section) BAR_SECTION="${2:?missing section}"; shift ;;
    --no-binds) BINDS=0 ;;
    --no-f9) F9=0 ;;
    --take-f9) TAKE_F9=1 ;;
    --no-model) MODEL=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
case "$BAR_SECTION" in left|center|right) ;; *) echo "--bar-section must be left, center or right" >&2; exit 2 ;; esac

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/.local/share/handy"
DATA="$HOME/.local/share/com.pais.handy"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"
PLUGIN="$HOME/.config/omarchy/plugins/handy.dictation"
say() { printf '\n==> %s\n' "$*"; }

# ---- checks ---------------------------------------------------------------
case "$(uname -m)" in
  x86_64) ARCH=amd64; SHA="$SHA_amd64" ;;
  aarch64) ARCH=aarch64; SHA="$SHA_aarch64" ;;
  *) echo "Unsupported CPU: $(uname -m)" >&2; exit 1 ;;
esac
need=(omarchy-shell hyprctl systemctl python3 curl sha256sum wtype wl-copy wl-paste parec pactl journalctl)
[[ $CLEANUP == 1 ]] && need+=(node secret-tool)
missing=()
for c in "${need[@]}"; do command -v "$c" >/dev/null || missing+=("$c"); done
if (( ${#missing[@]} )); then
  echo "Missing commands: ${missing[*]}" >&2
  echo "This setup targets Omarchy 4 (Hyprland with omarchy-shell). On Omarchy, install what is missing with pacman, for example:" >&2
  echo "  sudo pacman -S --needed wtype wl-clipboard libpulse nodejs libsecret" >&2
  exit 1
fi
if [[ -e "$BIN/handy" ]] && ! grep -q 'handy.dictation' "$BIN/handy" 2>/dev/null; then
  echo "$BIN/handy already exists and was not installed by this script. Move it away first." >&2; exit 1
fi

# ---- Handy itself ---------------------------------------------------------
mkdir -p "$APP" "$DATA/models" "$BIN" "$UNITS" "$PLUGIN" "$HOME/.local/share/applications"
if [[ "$(cat "$APP/.version" 2>/dev/null)" != "$HANDY_VERSION" || ! -x "$APP/squashfs-root/AppRun" ]]; then
  say "Downloading Handy $HANDY_VERSION"
  image="$APP/Handy-$HANDY_VERSION.AppImage"
  curl -fL --progress-bar -o "$image.part" \
    "https://github.com/cjpais/Handy/releases/download/v$HANDY_VERSION/Handy_${HANDY_VERSION}_${ARCH}.AppImage"
  echo "$SHA  $image.part" | sha256sum -c --quiet - || { echo "Handy download failed its checksum" >&2; exit 1; }
  mv "$image.part" "$image"; chmod +x "$image"
  say "Unpacking Handy"
  systemctl --user stop handy.service 2>/dev/null || true
  rm -rf "$APP/squashfs-root.new"
  (cd "$APP" && mkdir squashfs-root.new && cd squashfs-root.new && "$image" --appimage-extract >/dev/null && mv squashfs-root ../squashfs-root.unpacked)
  rm -rf "$APP/squashfs-root" "$APP/squashfs-root.new"
  mv "$APP/squashfs-root.unpacked" "$APP/squashfs-root"
  echo "$HANDY_VERSION" > "$APP/.version"
else
  say "Handy $HANDY_VERSION is already unpacked"
fi

if [[ $MODEL == 1 ]]; then
  if [[ -f "$DATA/models/$MODEL_FILE" ]] && echo "$MODEL_SHA  $DATA/models/$MODEL_FILE" | sha256sum -c --quiet - 2>/dev/null; then
    say "Parakeet model is already downloaded"
  else
    say "Downloading the Parakeet TDT 0.6B v3 model (about 705 MB)"
    curl -fL --progress-bar -C - -o "$DATA/models/$MODEL_FILE.part" "$MODEL_URL"
    echo "$MODEL_SHA  $DATA/models/$MODEL_FILE.part" | sha256sum -c --quiet - || { echo "Model download failed its checksum" >&2; exit 1; }
    mv "$DATA/models/$MODEL_FILE.part" "$DATA/models/$MODEL_FILE"
  fi
fi

# ---- files ----------------------------------------------------------------
say "Installing launcher, paste helper, bar widget and services"
install -m 755 "$SRC/bin/handy" "$BIN/handy"
install -m 755 "$SRC/bin/handy-paste" "$BIN/handy-paste"
if [[ $CLEANUP == 1 ]]; then flag="--toggle-post-process"; else flag="--toggle-transcription"; fi
printf '#!/usr/bin/env bash\n# Start or stop a dictation. Written by handy-omarchy install.sh.\nexec "$HOME/.local/bin/handy" %s\n' "$flag" > "$BIN/handy-toggle"
chmod 755 "$BIN/handy-toggle"
install -m 644 "$SRC/share/bar-status.py" "$APP/bar-status.py"
install -m 644 "$SRC/plugin/handy.dictation/manifest.json" "$SRC/plugin/handy.dictation/Dictation.qml" "$PLUGIN/"
install -m 644 "$SRC/sounds/custom_start.wav" "$SRC/sounds/custom_stop.wav" "$DATA/"
install -m 644 "$SRC/systemd/handy.service" "$SRC/systemd/handy-bar.service" "$UNITS/"
cat > "$HOME/.local/share/applications/handy.desktop" <<D
[Desktop Entry]
Name=Handy
Comment=Local dictation
Exec=$BIN/handy
Icon=$APP/squashfs-root/usr/share/icons/hicolor/128x128/apps/handy.png
Type=Application
Categories=Utility;Accessibility;
Terminal=false
D

# ---- settings (Handy must be stopped or it overwrites them) -----------------
say "Applying Handy settings"
systemctl --user stop handy.service 2>/dev/null || true
if pgrep -u "$USER" -f "$APP/squashfs-root" >/dev/null; then
  echo "Handy is running outside systemd. Quit it from its tray icon, then run this installer again." >&2; exit 1
fi
settings_args=(--model-id "$MODEL_ID")
[[ $CLEANUP == 1 ]] && settings_args+=(--cleanup-model "$CLEANUP_MODEL")
python3 "$SRC/scripts/apply-settings.py" "${settings_args[@]}"

# ---- optional cleanup bridge ------------------------------------------------
if [[ $CLEANUP == 1 ]]; then
  say "Installing the cleanup bridge"
  install -m 644 "$SRC/share/cleanup-bridge.cjs" "$APP/cleanup-bridge.cjs"
  install -m 644 "$SRC/systemd/handy-cleanup.service" "$UNITS/"
  mkdir -p "$UNITS/handy-cleanup.service.d"
  printf '[Service]\nEnvironment=HANDY_CLEANUP_MODEL=%s\n' "$CLEANUP_MODEL" > "$UNITS/handy-cleanup.service.d/model.conf"
  if secret-tool lookup service handy-omarchy account openrouter >/dev/null 2>&1; then
    echo "OpenRouter key found in the keyring."
  elif [[ -t 0 ]]; then
    echo "Paste your OpenRouter API key (input is hidden). It is stored in your OS keyring only."
    secret-tool store --label="OpenRouter key for Handy cleanup" service handy-omarchy account openrouter
  else
    echo "No OpenRouter key stored yet. Until you add one, dictation pastes the raw transcript. Add it with:"
    echo "  secret-tool store --label='OpenRouter key for Handy cleanup' service handy-omarchy account openrouter"
  fi
fi

# ---- shortcuts --------------------------------------------------------------
if [[ $BINDS == 1 ]]; then
  say "Adding shortcuts"
  binds="$HOME/.config/hypr/handy-binds.lua"
  if [[ -e "$binds" ]]; then
    echo "Keeping your existing $binds"
  else
    # Never take F9 away from something that already uses it.
    if [[ $F9 == 1 && $TAKE_F9 == 0 ]] && hyprctl -j binds 2>/dev/null | python3 -c 'import json,sys; sys.exit(0 if any(b.get("key")=="F9" and b.get("modmask")==0 for b in json.load(sys.stdin)) else 1)' 2>/dev/null; then
      F9=0
      echo "F9 is already bound (Omarchy binds it to Voxtype dictation), so it was left alone."
      echo "Use Super+Ctrl+X, or delete $binds and run ./install.sh --take-f9 to hold F9 to talk."
    fi
    install -m 644 "$SRC/hypr/handy-binds.lua" "$binds"
    if [[ $F9 == 0 ]]; then sed -i '/\[f9\]/d' "$binds"; fi
  fi
  main="$HOME/.config/hypr/hyprland.lua"
  if [[ ! -f "$main" ]]; then
    echo "No $main found. Load $binds from your Hyprland config yourself."
  elif grep -q 'handy-binds.lua' "$main"; then
    echo "hyprland.lua already loads handy-binds.lua"
  else
    cp "$main" "$main.bak-handy-omarchy-$(date +%Y%m%d%H%M%S)"
    printf '\npcall(dofile, os.getenv("HOME") .. "/.config/hypr/handy-binds.lua") -- handy-omarchy\n' >> "$main"
  fi
  hyprctl reload >/dev/null 2>&1 || echo "Could not reload Hyprland from here. Run: hyprctl reload"
fi

# ---- bar and services -------------------------------------------------------
say "Adding the dictation widget to the bar"
python3 "$SRC/scripts/bar-layout.py" add "$BAR_SECTION"

say "Starting services"
systemctl --user daemon-reload
[[ $CLEANUP == 1 ]] && systemctl --user enable --now handy-cleanup.service
systemctl --user enable handy.service handy-bar.service
systemctl --user restart handy.service
systemctl --user restart handy-bar.service
if ! omarchy-shell handy.dictation status >/dev/null 2>&1; then
  omarchy-restart-shell >/dev/null 2>&1 || echo "Restart the bar to load the widget: omarchy-restart-shell"
fi

cat <<DONE

Done. Press Super+Ctrl+X to start and again to stop$([[ $BINDS == 1 && $F9 == 1 ]] && echo ", or hold F9 and talk").
A red dot and live waveform appear in the top bar while recording, then a
spinner until the text is pasted. The widget is hidden when idle.

  Settings and dictionary:  run "handy" (or open Handy from the launcher)
  Shortcuts:                ~/.config/hypr/handy-binds.lua
  Logs:                     journalctl --user -u handy -u handy-bar -f
  Remove everything:        ./uninstall.sh
DONE
