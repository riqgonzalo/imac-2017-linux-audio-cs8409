#!/bin/bash
# Pruebas sin hardware: cargan las funciones de los scripts con comandos simulados.
# Uso: bash pruebas/test_scripts.sh
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
pasa=0; falla=0
check() { if [ "$1" = "$2" ]; then echo "  ✔ $3"; pasa=$((pasa+1)); else echo "  ✖ $3 (esperado '$2', obtenido '$1')"; falla=$((falla+1)); fi; }

echo "== cambiar_modo_audio.sh"
export CS8409_PARAM="$S/param" CS8409_CONF="$S/cs8409.conf"
source "$REPO/cambiar_modo_audio.sh"
rm -f "$CS8409_CONF"; echo 0 > "$CS8409_PARAM"
guardar_modo 1
check "$(cat $CS8409_PARAM)" "1" "aplica al momento en sysfs"
check "$(grep -c 'force_speakers=1' $CS8409_CONF)" "1" "crea el conf si no existe"
printf '# solo comentario\n' > "$CS8409_CONF"; guardar_modo 0
check "$(grep -c 'force_speakers=0' $CS8409_CONF)" "1" "añade la opción si el conf no la tiene (bug v1.0)"
check "$(grep -c 'solo comentario' $CS8409_CONF)" "1" "conserva el resto del conf"
guardar_modo 1
check "$(grep -c 'force_speakers' $CS8409_CONF)" "1" "no duplica la línea al cambiar"
rm -f "$CS8409_PARAM"; guardar_modo 0
check "$APLICADO_AHORA" "0" "sin módulo: avisa que se aplicará al reiniciar"

echo "== instalar_audio_imac.sh"
export MODDIR="$S/modules" LOG_FILE="$S/install.log"
source "$REPO/instalar_audio_imac.sh"
KVER="9.9.9-test"; SRC_DEST="$S/src"; pausa() { :; }; dkms() { :; }; depmod() { :; }
mkdir -p "$SRC_DEST"
# a) sin cabeceras
compilar_con_dkms >/dev/null 2>&1; check "$?" "1" "falla si faltan las cabeceras del kernel"
mkdir -p "$MODDIR/$KVER/build"
# b) script de compilación con error
printf '#!/bin/bash\necho compilando; exit 3\n' > "$SRC_DEST/install.cirrus.driver.sh"; chmod +x "$SRC_DEST/install.cirrus.driver.sh"
compilar_con_dkms >/dev/null 2>&1; check "$?" "1" "detecta error del script de compilación (v1.0 decía ÉXITO)"
# c) script dice éxito pero no hay módulo
printf '#!/bin/bash\nexit 0\n' > "$SRC_DEST/install.cirrus.driver.sh"
compilar_con_dkms >/dev/null 2>&1; check "$?" "1" "detecta que no se generó el .ko"
# d) éxito real
mkdir -p "$MODDIR/$KVER/updates/dkms"; touch "$MODDIR/$KVER/updates/dkms/snd-hda-codec-cs8409.ko.zst"
compilar_con_dkms >/dev/null 2>&1; check "$?" "0" "éxito cuando existe el módulo (.ko.zst en updates/dkms)"
check "$(grep -c compilando $LOG_FILE)" "1" "la salida de compilación queda en el log"
# e) un fallo de compilación NO recarga módulos ni muestra 'COMPLETADA'
preparar_fuentes() { return 0; }; compilar_con_dkms() { return 1; }
reiniciar_modulos_y_probar() { echo RECARGA; }; configurar_modprobe_y_guard() { echo GUARD; }
out=$(pasos_comunes 'true' 2>&1)
check "$(echo "$out" | grep -c 'RECARGA\|GUARD')" "0" "tras un fallo no toca módulos ni configuración"
check "$(echo "$out" | grep -c 'NO SE COMPLETÓ')" "1" "muestra mensaje de fallo claro"
# f) programas usando el audio: se listan, no se matan
unset -f reiniciar_modulos_y_probar; source "$REPO/instalar_audio_imac.sh"; KVER="9.9.9-test"; pausa() { :; }
alsactl() { :; }; como_usuario() { :; }; sleep() { :; }; dkms() { :; }
fuser() { echo " 4242 4343"; }; ps() { echo "4242 firefox"; }
modprobe() { echo "MODPROBE $*" >> "$S/modprobe.log"; }; killall() { echo KILL >> "$S/modprobe.log"; }
reiniciar_modulos_y_probar <<< "n" > "$S/out_f.txt" 2>&1
check "$(grep -c firefox $S/out_f.txt)" "1" "lista los programas que usan el audio"
check "$( [ -f $S/modprobe.log ] && grep -c 'KILL\|MODPROBE -r' $S/modprobe.log || echo 0)" "0" "no mata procesos ni descarga módulos en uso"
check "$RELOAD_OK" "0" "pide reinicio en ese caso"
# g) volumen de prueba
check "$VOLUMEN_PRUEBA" "40%" "volumen de prueba moderado"
check "$(grep -v '^ *#' $REPO/instalar_audio_imac.sh | grep -c 'plughw')" "0" "ya no usa plughw (sin control de volumen)"
check "$(grep -v '^ *#' $REPO/instalar_audio_imac.sh | grep -c 'killall\|fuser -k\|rmmod -f')" "0" "sin killall/fuser -k/rmmod -f"
echo; echo "RESULTADO: $pasa correctas, $falla fallidas"
[ "$falla" -eq 0 ]
