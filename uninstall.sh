#!/usr/bin/env bash
# Remove everything install.sh added. Your Handy data (history, model) and the
# cleanup dictionary are kept unless you pass --purge.
set -euo pipefail
PURGE=0; [[ "${1:-}" == "--purge" ]] && PURGE=1
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITS="$HOME/.config/systemd/user"

systemctl --user disable --now handy-bar.service handy.service handy-cleanup.service 2>/dev/null || true
rm -f "$UNITS/handy.service" "$UNITS/handy-bar.service" "$UNITS/handy-cleanup.service"
rm -rf "$UNITS/handy-cleanup.service.d"
systemctl --user daemon-reload

python3 "$SRC/scripts/bar-layout.py" remove || true
rm -rf "$HOME/.config/omarchy/plugins/handy.dictation"

main="$HOME/.config/hypr/hyprland.lua"
if [[ -f "$main" ]] && grep -q -- '-- handy-omarchy$' "$main"; then
  cp "$main" "$main.bak-handy-omarchy-$(date +%Y%m%d%H%M%S)"
  sed -i '/-- handy-omarchy$/d' "$main"
  rm -f "$HOME/.config/hypr/handy-binds.lua"
fi
hyprctl reload >/dev/null 2>&1 || true

rm -f "$HOME/.local/bin/handy" "$HOME/.local/bin/handy-toggle" "$HOME/.local/bin/handy-paste"
rm -f "$HOME/.local/share/applications/handy.desktop"
rm -rf "$HOME/.local/share/handy"
rm -f "${XDG_RUNTIME_DIR:-/nonexistent}"/handy-bar.json "${XDG_RUNTIME_DIR:-/nonexistent}"/handy-cleanup-stage.json \
      "${XDG_RUNTIME_DIR:-/nonexistent}"/handy-last-paste.json "${XDG_RUNTIME_DIR:-/nonexistent}"/handy-paste.lock

if [[ $PURGE == 1 ]]; then
  rm -rf "$HOME/.local/share/com.pais.handy" "$HOME/.config/handy-omarchy"
  secret-tool clear service handy-omarchy account openrouter 2>/dev/null || true
  echo "Removed Handy, its data, the model, the cleanup dictionary and the stored API key."
else
  echo "Removed Handy and the bar widget. Kept ~/.local/share/com.pais.handy (history, model) and ~/.config/handy-omarchy (cleanup dictionary)."
  echo "Run ./uninstall.sh --purge to remove that and the stored API key too."
fi
