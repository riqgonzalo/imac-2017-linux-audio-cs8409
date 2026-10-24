#!/usr/bin/env bash
# Crea los accesos directos en el menú de aplicaciones (y en el Escritorio si existe)
# apuntando a la carpeta donde está este repositorio. No requiere sudo.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESK="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Escritorio")"
mkdir -p "$APPS"
chmod +x "$DIR"/*.sh
for tpl in "$DIR"/lanzadores/*.desktop.in; do
    name="$(basename "$tpl" .in)"
    sed "s|@DIR@|$DIR|g" "$tpl" > "$APPS/$name"
    chmod 755 "$APPS/$name"
    if [ -d "$DESK" ]; then
        cp "$APPS/$name" "$DESK/$name"
        chmod 755 "$DESK/$name"
        gio set "$DESK/$name" metadata::trusted true 2>/dev/null || true
    fi
    echo "Creado: $name"
done
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
echo "Listo. Busca «Instalador Audio Apple» en el menú de aplicaciones."
