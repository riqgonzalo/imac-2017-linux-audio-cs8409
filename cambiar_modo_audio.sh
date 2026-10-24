#!/bin/bash
# ==============================================================================
# Selector de Modo de Audio para Apple iMac (Altavoces / Auriculares)  v1.2.0
# ==============================================================================

PARAM="${CS8409_PARAM:-/sys/module/snd_hda_codec_cs8409/parameters/force_speakers}"
CONF="${CS8409_CONF:-/etc/modprobe.d/cs8409.conf}"

# Aplica el modo al momento (sysfs) y lo deja guardado para los próximos arranques.
guardar_modo() {
    local v="$1"

    if [ -e "$PARAM" ] && echo "$v" > "$PARAM" 2>/dev/null; then
        APLICADO_AHORA=1
    else
        APLICADO_AHORA=0
    fi

    mkdir -p "$(dirname "$CONF")"
    if grep -qs 'force_speakers=' "$CONF"; then
        sed -i "s/force_speakers=[0-9]*/force_speakers=$v/g" "$CONF"
    else
        # El archivo no existe o no tiene la opción: se añade sin borrar lo demás
        echo "options snd_hda_codec_cs8409 force_speakers=$v" >> "$CONF"
    fi
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\e[1;34mSolicitando permisos de administrador (sudo)...\e[0m"
        exec sudo bash "$0" "$@"
    fi

    if [ -e "$PARAM" ]; then
        MODO_ACTUAL=$(cat "$PARAM" 2>/dev/null)
    else
        MODO_ACTUAL="desconocido"
    fi

    echo -e "\e[1;34m============================================================\e[0m"
    echo -e "\e[1;32m       CONFIGURADOR DE MODO DE AUDIO APPLE (CS8409)\e[0m"
    echo -e "\e[1;34m============================================================\e[0m"
    case "$MODO_ACTUAL" in
        1) echo -e "Modo actual: \e[1;33mAltavoces Forzados (force_speakers=1)\e[0m\n" ;;
        0) echo -e "Modo actual: \e[1;33mDetección Automática (force_speakers=0)\e[0m\n" ;;
        *)
            if [ -d /sys/module/snd_hda_codec_cs8409 ]; then
                echo -e "\e[1;31m[!] El módulo cargado no tiene el parche del iMac (no existe force_speakers).\e[0m"
                echo -e "    Ejecuta primero instalar_audio_imac.sh. El modo se guardará igualmente.\n"
            else
                echo -e "\e[1;33m[i] El módulo snd_hda_codec_cs8409 no está cargado. El modo se aplicará al reiniciar.\e[0m\n"
            fi
            ;;
    esac
    echo "Selecciona el modo deseado:"
    echo -e "  \e[1;32m1)\e[0m Activar Detección Automática (Altavoces <-> Auriculares)"
    echo -e "  \e[1;37m2)\e[0m Forzar Altavoces Internos permanentemente"
    echo -e "  \e[1;31m3)\e[0m Salir"
    echo ""
    read -r -p "Opción [1-3]: " opcion

    case $opcion in
        1)
            guardar_modo 0
            echo -e "\n\e[1;32m[✓] ¡Detección automática ACTIVADA!\e[0m"
            echo "El sonido conmutará automáticamente entre altavoces y auriculares al conectar el cable jack."
            ;;
        2)
            guardar_modo 1
            echo -e "\n\e[1;32m[✓] ¡Altavoces internos FORZADOS!\e[0m"
            echo "Los altavoces internos permanecerán siempre activos."
            ;;
        *)
            echo "Saliendo sin cambios."
            exit 0
            ;;
    esac

    if [ "$APLICADO_AHORA" -eq 1 ]; then
        echo "Cambio aplicado al momento y guardado en $CONF."
        echo "(Si la salida no cambia enseguida, conecta/desconecta el jack o reinicia la reproducción.)"
    else
        echo -e "\e[1;33mGuardado en $CONF; se aplicará al reiniciar el equipo.\e[0m"
    fi

    echo ""
    read -r -p "Presiona Enter para cerrar..." _
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
