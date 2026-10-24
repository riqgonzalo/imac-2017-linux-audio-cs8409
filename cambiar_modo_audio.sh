#!/bin/bash
# ==============================================================================
# Selector de Modo de Audio para Apple iMac (Altavoces / Auriculares)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;34mSolicitando permisos de administrador (sudo)...\e[0m"
    exec sudo bash "$0" "$@"
fi

MODO_ACTUAL=$(cat /sys/module/snd_hda_codec_cs8409/parameters/force_speakers 2>/dev/null || echo "desconocido")

echo -e "\e[1;34m============================================================\e[0m"
echo -e "\e[1;32m       CONFIGURADOR DE MODO DE AUDIO APPLE (CS8409)\e[0m"
echo -e "\e[1;34m============================================================\e[0m"
echo -e "Modo actual: \e[1;33m$([ "$MODO_ACTUAL" = "1" ] && echo "Altavoces Forzados (force_speakers=1)" || echo "Detección Automática (force_speakers=0)")\e[0m\n"
echo "Selecciona el modo deseado:"
echo -e "  \e[1;32m1)\e[0m Activar Detección Automática (Altavoces <-> Auriculares)"
echo -e "  \e[1;37m2)\e[0m Forzar Altavoces Internos permanentemente"
echo -e "  \e[1;31m3)\e[0m Salir"
echo ""
read -p "Opción [1-3]: " opcion

case $opcion in
    1)
        echo 0 > /sys/module/snd_hda_codec_cs8409/parameters/force_speakers 2>/dev/null || true
        sed -i 's/force_speakers=1/force_speakers=0/g' /etc/modprobe.d/cs8409.conf 2>/dev/null || echo "options snd_hda_codec_cs8409 force_speakers=0" > /etc/modprobe.d/cs8409.conf
        echo -e "\n\e[1;32m[✓] ¡Detección automática ACTIVADA!\e[0m"
        echo "Ahora el sonido conmutará automáticamente entre altavoces y auriculares al conectar el cable jack."
        ;;
    2)
        echo 1 > /sys/module/snd_hda_codec_cs8409/parameters/force_speakers 2>/dev/null || true
        sed -i 's/force_speakers=0/force_speakers=1/g' /etc/modprobe.d/cs8409.conf 2>/dev/null || echo "options snd_hda_codec_cs8409 force_speakers=1" > /etc/modprobe.d/cs8409.conf
        echo -e "\n\e[1;32m[✓] ¡Altavoces internos FORZADOS!\e[0m"
        echo "Los altavoces internos permanecerán siempre activos."
        ;;
    *)
        echo "Saliendo sin cambios."
        exit 0
        ;;
esac

echo ""
read -p "Presiona Enter para cerrar..." dummy
