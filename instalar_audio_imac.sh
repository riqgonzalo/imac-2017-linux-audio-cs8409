#!/bin/bash
# ==============================================================================
# INSTALADOR UNIVERSAL DE AUDIO APPLE (CIRRUS CS8409 / TI TAS57642)
# Compatible con: Apple iMac18,1, iMac18,2, iMac18,3 y MacBook Pro
# Plataformas soportadas: RPM (Fedora/RHEL/SUSE), DEB (Ubuntu/Debian/Mint),
#                         Arch Linux (Manjaro/EndeavourOS) y Nix / NixOS
# ==============================================================================
# Los errores se comprueban paso a paso (sin "set -e") para poder avisar con
# claridad y volver al menú en lugar de cerrar la ventana a mitad de camino.

VERSION="1.1.0"

# ------------------------------------------------------------------------------
# 1. Variables globales
# ------------------------------------------------------------------------------
KVER=$(uname -r)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SRC_DEST="/usr/src/snd_hda_macbookpro-0.1"
DESKTOP_SRC="$SCRIPT_DIR/snd_hda_macbookpro_imac"
PATCH_FILE="$SCRIPT_DIR/parches/imac-cs8409.patch"
LOG_FILE="${LOG_FILE:-/var/log/instalar_audio_imac.log}"
MODDIR="${MODDIR:-/lib/modules}"
VOLUMEN_PRUEBA="40%"
SONIDO_PRUEBA="/usr/share/sounds/freedesktop/stereo/complete.oga"

# Usuario real que lanzó el instalador (no root), para PipeWire y su carpeta personal
CURRENT_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
    CURRENT_USER=$(id -un 1000 2>/dev/null || echo "root")
fi
CURRENT_UID=$(id -u "$CURRENT_USER" 2>/dev/null || echo 0)
USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
FALLBACK_SRC="$USER_HOME/snd_hda_macbookpro"

# ------------------------------------------------------------------------------
# 2. Utilidades
# ------------------------------------------------------------------------------
ok()    { echo -e "\e[1;32m[✓] $*\e[0m"; }
info()  { echo -e "\e[1;34m--> $*\e[0m"; }
aviso() { echo -e "\e[1;33m[!] $*\e[0m"; }
error() { echo -e "\e[1;31m[✗] $*\e[0m"; }
pausa() { read -r -p "${1:-Presiona [Enter] para volver al menú...}" _; }

# Ejecuta un comando dentro de la sesión del usuario (PipeWire, pactl, systemctl --user).
como_usuario() {
    if [ "$CURRENT_UID" -eq 0 ]; then
        "$@"
        return
    fi
    runuser -u "$CURRENT_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/$CURRENT_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$CURRENT_UID/bus" \
        "$@"
}

# ¿Existe el módulo parcheado para el kernel indicado? (extra/ o updates/, cualquier compresión)
modulo_cs8409_instalado() {
    local k="${1:-$KVER}"
    find "$MODDIR/$k/extra" "$MODDIR/$k/updates" \
        -name 'snd-hda-codec-cs8409.ko*' 2>/dev/null | grep -q .
}

registrar() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo -e "\n===== $(date '+%Y-%m-%d %H:%M:%S') · v$VERSION · kernel $KVER · $* =====" >> "$LOG_FILE"
}

fallo_instalacion() {
    echo ""
    error "LA INSTALACIÓN NO SE COMPLETÓ: $1"
    echo "    Revisa el registro completo en: $LOG_FILE"
    echo "    No se han recargado los módulos de audio; tu sistema sigue como estaba."
    pausa
    return 1
}

# ------------------------------------------------------------------------------
# 3. Código fuente parcheado
# ------------------------------------------------------------------------------
preparar_fuentes() {
    info "Preparando código fuente del controlador con correcciones de hardware..."

    # Quitar un registro DKMS anterior antes de reemplazar el código fuente
    if dkms status 2>/dev/null | grep -q "snd_hda_macbookpro"; then
        echo "Eliminando registro anterior en DKMS para el kernel $KVER..."
        dkms remove -m snd_hda_macbookpro/0.1 -k "$KVER" --force >> "$LOG_FILE" 2>&1 || true
    fi
    rm -rf "$SRC_DEST"
    mkdir -p "$SRC_DEST"

    if [ -d "$DESKTOP_SRC" ] && [ -f "$DESKTOP_SRC/patch_cirrus/cirrus_apple.h" ]; then
        echo "Copiando fuentes parcheadas desde: $DESKTOP_SRC"
        cp -r "$DESKTOP_SRC"/. "$SRC_DEST"/
    elif [ -d "$FALLBACK_SRC" ] && [ -f "$FALLBACK_SRC/patch_cirrus/cirrus_apple.h" ]; then
        echo "Copiando fuentes parcheadas desde: $FALLBACK_SRC"
        cp -r "$FALLBACK_SRC"/. "$SRC_DEST"/
    else
        echo "Descargando controlador oficial y aplicando parches para iMac..."
        local tmp
        tmp=$(mktemp -d)
        if ! wget -qO- https://github.com/davidjo/snd_hda_macbookpro/archive/refs/heads/master.tar.gz | tar -xz -C "$tmp"; then
            rm -rf "$tmp"
            error "No se pudo descargar el controlador desde GitHub (¿hay conexión a Internet?)."
            return 1
        fi
        cp -r "$tmp"/snd_hda_macbookpro-master/. "$SRC_DEST"/
        rm -rf "$tmp"

        # Aplicar el parche del iMac (tip-sense sin invertir + parámetro force_speakers)
        if [ -f "$PATCH_FILE" ] && (cd "$SRC_DEST" && patch -p1 --forward < "$PATCH_FILE") >> "$LOG_FILE" 2>&1; then
            echo "Parche iMac aplicado correctamente."
        else
            aviso "El parche no aplica sobre esta versión; aplicando solo la corrección del jack."
            sed -i 's/cs42l83_tip_sense(codec, 1);/cs42l83_tip_sense(codec, 0);/g' "$SRC_DEST/patch_cirrus/patch_cirrus_real84.h"
            # Solo los 'exit' sueltos: no tocar 'exit 1' (rompería el manejo de errores)
            sed -i 's/^\([[:space:]]*\)exit$/\1exit 0/' "$SRC_DEST/install.cirrus.driver.sh" 2>/dev/null || true
        fi
    fi

    if [ ! -x "$SRC_DEST/install.cirrus.driver.sh" ] && [ ! -f "$SRC_DEST/install.cirrus.driver.sh" ]; then
        error "El código fuente copiado está incompleto (falta install.cirrus.driver.sh)."
        return 1
    fi

    chown -R root:root "$SRC_DEST"
    chmod -R u+rwX,go+rX "$SRC_DEST"
    chmod 755 "$SRC_DEST"/*.sh
    ok "Fuentes del controlador listas en $SRC_DEST"
}

# ------------------------------------------------------------------------------
# 4. Compilación con DKMS (con comprobación real del resultado)
# ------------------------------------------------------------------------------
compilar_con_dkms() {
    info "Compilando e integrando módulo con DKMS para kernel $KVER..."
    if [ ! -e "$MODDIR/$KVER/build" ]; then
        error "No están instaladas las cabeceras del kernel $KVER ($MODDIR/$KVER/build)."
        echo "    Si acabas de actualizar el kernel, reinicia primero y vuelve a ejecutar el instalador."
        return 1
    fi
    aviso "Se descargará el código fuente del kernel $KVER (150–250 MB) y se compilará el módulo."
    aviso "Puede tardar entre 5 y 20 minutos según tu conexión. No cierres esta ventana."
    echo "    Progreso detallado: $LOG_FILE"
    echo ""

    local rc
    (cd "$SRC_DEST" && ./install.cirrus.driver.sh -i -k "$KVER") 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]}

    if [ "$rc" -ne 0 ]; then
        error "El script de compilación terminó con error (código $rc)."
        return 1
    fi
    if ! modulo_cs8409_instalado "$KVER"; then
        error "La compilación terminó pero no se encontró snd-hda-codec-cs8409.ko para $KVER."
        return 1
    fi
    depmod -a "$KVER"
    ok "Módulo compilado e instalado: $(find "$MODDIR/$KVER/extra" "$MODDIR/$KVER/updates" -name 'snd-hda-codec-cs8409.ko*' 2>/dev/null | head -1)"
}

# ------------------------------------------------------------------------------
# 5. Persistencia: modprobe + guardián tras actualizaciones del kernel
# ------------------------------------------------------------------------------
configurar_modprobe_y_guard() {
    info "Configurando persistencia y parámetros del controlador..."
    mkdir -p /etc/modprobe.d

    # Conservar el modo elegido por el usuario si ya existía
    local modo=0
    if grep -qs 'force_speakers=1' /etc/modprobe.d/cs8409.conf; then
        modo=1
    fi
    cat << EOF > /etc/modprobe.d/cs8409.conf
# Configuración para Apple Cirrus Logic CS8409 + TAS57642
# force_speakers=0 activa la detección automática de auriculares y altavoces internos
# force_speakers=1 fuerza siempre los altavoces internos (cámbialo con cambiar_modo_audio.sh)
options snd_hda_codec_cs8409 force_speakers=$modo
EOF
    ok "Archivo /etc/modprobe.d/cs8409.conf configurado (force_speakers=$modo)."

    # Quitar el enlace de la versión anterior (WantedBy=basic.target) antes de reescribir
    systemctl disable cs8409-audio-guard.service >/dev/null 2>&1 || true

    mkdir -p /usr/local/bin
    cat << 'EOF' > /usr/local/bin/check-cs8409-driver.sh
#!/bin/bash
# Guardián del audio Apple CS8409: si el kernel arrancado no tiene el módulo
# parcheado, lo compila con DKMS. Nunca bloquea el arranque ni falla el servicio.
KVER=$(uname -r)

if find "/lib/modules/$KVER/extra" "/lib/modules/$KVER/updates" \
        -name 'snd-hda-codec-cs8409.ko*' 2>/dev/null | grep -q .; then
    exit 0
fi

if [ ! -e "/lib/modules/$KVER/build" ]; then
    echo "[CS8409-Guard] Faltan las cabeceras del kernel $KVER (kernel-devel / linux-headers). Instálalas y reinicia."
    exit 0
fi

echo "[CS8409-Guard] Controlador Apple no encontrado para el kernel $KVER. Compilando con DKMS..."
if dkms install -m snd_hda_macbookpro/0.1 -k "$KVER" --force; then
    depmod -a "$KVER"
    echo "[CS8409-Guard] Módulo compilado. Reinicia el equipo para activar el audio de Apple."
else
    echo "[CS8409-Guard] La compilación falló. Revisa: journalctl -u cs8409-audio-guard"
fi
exit 0
EOF
    chmod 755 /usr/local/bin/check-cs8409-driver.sh

    # Se ejecuta en segundo plano tras tener red: no retrasa el arranque ni el escritorio
    cat << 'EOF' > /etc/systemd/system/cs8409-audio-guard.service
[Unit]
Description=Guardián del audio Apple CS8409 (recompila el módulo con DKMS si falta)
Wants=network-online.target
After=network-online.target dkms.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-cs8409-driver.sh
Nice=19
IOSchedulingClass=idle
TimeoutStartSec=30min

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable cs8409-audio-guard.service >/dev/null 2>&1 || true
    systemctl enable dkms.service >/dev/null 2>&1 || true
    ok "Servicio guardián de persistencia systemd activado."
}

# ------------------------------------------------------------------------------
# 6. PipeWire / WirePlumber: altavoces internos + HDMI simultáneos
# ------------------------------------------------------------------------------
configurar_dual_audio_hdmi_altavoces() {
    info "Configurando soporte simultáneo para Altavoces internos y HDMI/DisplayPort..."

    # 1. Configuración de perfil ACP multicanal (Sistema)
    mkdir -p /etc/alsa-card-profile/mixer/profile-sets
    mkdir -p /etc/alsa-card-profile/mixer/paths

    if [ -f /usr/share/alsa-card-profile/mixer/profile-sets/default.conf ]; then
        cp /usr/share/alsa-card-profile/mixer/profile-sets/default.conf /etc/alsa-card-profile/mixer/profile-sets/default.conf
    fi

    cat << 'EOF' > /etc/alsa-card-profile/mixer/profile-sets/9999-custom.conf
# Perfil multicanal simultáneo para Apple iMac (Altavoces internos + HDMI independientes)
[Profile output:analog-stereo+output:hdmi-all+input:analog-stereo]
description = Altavoces internos + HDMI + Micrófono
output-mappings = analog-stereo hdmi-stereo hdmi-stereo-extra1 hdmi-stereo-extra2
input-mappings = analog-stereo
priority = 8000
skip-probe = yes
EOF

    for i in 0 1 2; do
        cat << EOF > /etc/alsa-card-profile/mixer/paths/hdmi-output-$i.conf
.include /usr/share/alsa-card-profile/mixer/paths/hdmi-output-$i.conf

[Jack HDMI/DP]
state.unplugged = unknown

[Jack HDMI]
state.unplugged = unknown
EOF
    done

    # 2. Configuración de WirePlumber para nombrar y exponer las salidas (Sistema)
    mkdir -p /etc/wireplumber/wireplumber.conf.d
    cat << 'EOF' > /etc/wireplumber/wireplumber.conf.d/50-imac-audio.conf
monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "~alsa_card.pci-0000_00_1f.3*"
      }
    ]
    actions = {
      update-props = {
        device.profile = "output:analog-stereo+output:hdmi-all+input:analog-stereo"
        api.acp.auto-profile = false
      }
    }
  },
  {
    matches = [
      {
        node.name = "alsa_output.pci-0000_00_1f.3.analog-stereo"
      }
    ]
    actions = {
      update-props = {
        node.description = "Altavoces internos (iMac)"
      }
    }
  },
  {
    matches = [
      {
        node.name = "alsa_output.pci-0000_00_1f.3.hdmi-stereo"
      }
    ]
    actions = {
      update-props = {
        node.description = "Audio HDMI (Pantalla / Proyector)"
      }
    }
  },
  {
    matches = [
      {
        node.name = "alsa_output.pci-0000_00_1f.3.hdmi-stereo-extra1"
      }
    ]
    actions = {
      update-props = {
        node.description = "Audio HDMI 2 (DisplayPort)"
      }
    }
  },
  {
    matches = [
      {
        node.name = "alsa_output.pci-0000_00_1f.3.hdmi-stereo-extra2"
      }
    ]
    actions = {
      update-props = {
        node.description = "Audio HDMI 3 (Thunderbolt / DisplayPort)"
      }
    }
  }
]
EOF

    # 3. Réplica en el perfil de usuario para asegurar compatibilidad inmediata
    if [ "$CURRENT_UID" -ne 0 ] && [ -d "$USER_HOME" ]; then
        mkdir -p "$USER_HOME/.config/alsa-card-profile/mixer/profile-sets"
        mkdir -p "$USER_HOME/.config/alsa-card-profile/mixer/paths"
        mkdir -p "$USER_HOME/.config/wireplumber/wireplumber.conf.d"

        cp /etc/alsa-card-profile/mixer/profile-sets/default.conf "$USER_HOME/.config/alsa-card-profile/mixer/profile-sets/" 2>/dev/null || true
        cp /etc/alsa-card-profile/mixer/profile-sets/9999-custom.conf "$USER_HOME/.config/alsa-card-profile/mixer/profile-sets/"
        cp /etc/alsa-card-profile/mixer/paths/hdmi-output-*.conf "$USER_HOME/.config/alsa-card-profile/mixer/paths/"
        cp /etc/wireplumber/wireplumber.conf.d/50-imac-audio.conf "$USER_HOME/.config/wireplumber/wireplumber.conf.d/"
        rm -f "$USER_HOME/.config/wireplumber/wireplumber.conf.d/50-hdmi-auto.conf"

        chown -R "$CURRENT_USER:" "$USER_HOME/.config/alsa-card-profile" "$USER_HOME/.config/wireplumber" 2>/dev/null || true
    fi

    ok "Soporte dual simultáneo Altavoces / HDMI configurado exitosamente."
}

# ------------------------------------------------------------------------------
# 7. Servidor de sonido y prueba
# ------------------------------------------------------------------------------
detener_audio_usuario() {
    como_usuario systemctl --user stop \
        pipewire.socket pipewire-pulse.socket \
        wireplumber.service pipewire-pulse.service pipewire.service >/dev/null 2>&1 || true
}

iniciar_audio_usuario() {
    como_usuario systemctl --user start \
        pipewire.socket pipewire-pulse.socket \
        pipewire.service wireplumber.service pipewire-pulse.service >/dev/null 2>&1 || true
}

probar_altavoces() {
    local sink
    sink=$(como_usuario pactl list sinks short 2>/dev/null | awk '$2 ~ /analog-stereo/ {print $2; exit}')
    [ -z "$sink" ] && sink="@DEFAULT_SINK@"
    echo "Salida de prueba: $sink (volumen $VOLUMEN_PRUEBA)"
    como_usuario pactl set-sink-mute "$sink" 0 2>/dev/null || true
    como_usuario pactl set-sink-volume "$sink" "$VOLUMEN_PRUEBA" 2>/dev/null || true
    como_usuario pactl set-sink-port "$sink" analog-output-speaker 2>/dev/null || true
    # Nunca se usa hw:/plughw: directamente: no tienen control de volumen y suenan al máximo
    como_usuario pw-play "$SONIDO_PRUEBA" 2>/dev/null || como_usuario paplay "$SONIDO_PRUEBA" 2>/dev/null || \
        aviso "No se pudo reproducir el sonido de prueba."
}

reiniciar_modulos_y_probar() {
    info "Aplicando recarga en caliente de los módulos de audio..."
    mkdir -p /var/lib/alsa
    alsactl store 2>/dev/null || true

    echo "Deteniendo el servidor de sonido de $CURRENT_USER (PipeWire / WirePlumber)..."
    detener_audio_usuario
    sleep 1

    # No se cierra ningún programa a la fuerza: si algo sigue usando el audio, se avisa
    local pids
    pids=$(fuser /dev/snd/* 2>/dev/null | grep -oE '[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')

    RELOAD_OK=0
    if [ -n "$pids" ]; then
        aviso "Estos programas siguen usando el audio y no se cerrarán:"
        ps -o pid=,comm= -p "$pids" 2>/dev/null | sed 's/^/      /'
        echo "    El nuevo controlador se activará al reiniciar el equipo."
    elif modprobe -r snd_hda_intel snd_hda_codec_cs8409 2>/dev/null; then
        sleep 1
        if modprobe snd_hda_codec_cs8409 && modprobe snd_hda_intel; then
            ok "Módulos de audio recargados exitosamente."
            sleep 1
            alsactl restore 2>/dev/null || true
            RELOAD_OK=1
        else
            aviso "No se pudieron volver a cargar los módulos; se activarán al reiniciar."
            modprobe snd_hda_intel 2>/dev/null || true
        fi
    else
        aviso "Los controladores están en uso en este arranque. Se requerirá reiniciar."
    fi

    iniciar_audio_usuario
    sleep 2

    if [ "$RELOAD_OK" -eq 1 ]; then
        info "Enviando tono de prueba a los altavoces internos..."
        probar_altavoces
    fi

    echo ""
    echo -e "\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m ¡INSTALACIÓN COMPLETADA!\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"
    echo "Estado de DKMS:"
    dkms status 2>/dev/null || true
    echo ""

    if [ "$RELOAD_OK" -eq 0 ]; then
        echo -e "\e[1;33mPara activar el nuevo controlador y los amplificadores TAS57642\e[0m"
        echo -e "\e[1;33mes necesario reiniciar el equipo.\e[0m"
        read -r -p "¿Deseas reiniciar el sistema ahora? (s/n): " -n 1
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            systemctl reboot
        fi
    fi
    pausa
}

# ------------------------------------------------------------------------------
# 8. Flujos por Familia de Distribución
# ------------------------------------------------------------------------------
pasos_comunes() {
    # $1 = comando para regenerar el initramfs
    preparar_fuentes                     || { fallo_instalacion "no se pudo preparar el código fuente"; return 1; }
    compilar_con_dkms                    || { fallo_instalacion "la compilación del módulo falló"; return 1; }
    configurar_modprobe_y_guard
    configurar_dual_audio_hdmi_altavoces

    info "Actualizando initramfs..."
    eval "$1" >> "$LOG_FILE" 2>&1 || aviso "No se pudo regenerar el initramfs (no suele ser crítico)."

    reiniciar_modulos_y_probar
}

instalar_rpm() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Instalando para Familia RPM (Fedora / RHEL / openSUSE)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"
    registrar "RPM"

    local base="kernel-devel-$KVER kernel-headers gcc make patch git dkms alsa-utils wget psmisc"
    if command -v dnf &>/dev/null; then
        echo "Instalando paquetes con DNF..."
        # shellcheck disable=SC2086
        dnf install -y $base kernel-devel-matched || dnf install -y $base \
            || { fallo_instalacion "no se pudieron instalar las dependencias con DNF"; return 1; }
    elif command -v zypper &>/dev/null; then
        echo "Instalando paquetes con Zypper..."
        zypper install -y kernel-devel kernel-default-devel gcc make patch git dkms alsa-utils wget psmisc \
            || { fallo_instalacion "no se pudieron instalar las dependencias con Zypper"; return 1; }
    else
        aviso "No se encontró dnf ni zypper; se intentará continuar con lo que haya instalado."
    fi

    pasos_comunes 'dracut --force --kver "$KVER" || dracut --force'
}

instalar_deb() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Instalando para Familia DEB (Ubuntu / Debian / Linux Mint)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"
    registrar "DEB"

    echo "Actualizando índices de paquetes e instalando dependencias..."
    apt-get update -y
    apt-get install -y "linux-headers-$KVER" build-essential dkms alsa-utils patch git wget psmisc \
        || { fallo_instalacion "no se pudieron instalar las dependencias con APT"; return 1; }

    pasos_comunes 'update-initramfs -u -k "$KVER" || update-initramfs -u'
}

instalar_arch() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Instalando para Familia Arch (Arch / Manjaro / EndeavourOS)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"
    registrar "Arch"

    # Detectar paquete de cabeceras correspondiente
    local header_pkg="linux-headers"
    if [[ "$KVER" == *"lts"* ]]; then
        header_pkg="linux-lts-headers"
    elif [[ "$KVER" == *"zen"* ]]; then
        header_pkg="linux-zen-headers"
    elif [[ "$KVER" == *"hardened"* ]]; then
        header_pkg="linux-hardened-headers"
    fi

    echo "Instalando cabeceras ($header_pkg) y utilidades con Pacman..."
    pacman -Sy --needed --noconfirm base-devel dkms alsa-utils wget patch git psmisc "$header_pkg" \
        || { fallo_instalacion "no se pudieron instalar las dependencias con Pacman"; return 1; }

    pasos_comunes 'mkinitcpio -P'
}

instalar_nix() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Configuración para Nix / NixOS (experimental)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"

    NIX_MODULE="/etc/nixos/cs8409-audio.nix"
    echo -e "Generando módulo declarativo de NixOS en: \e[1;33m$NIX_MODULE\e[0m"
    mkdir -p /etc/nixos

    cat << 'EOF' > "$NIX_MODULE"
# Módulo de Audio Apple Cirrus CS8409 para NixOS (experimental)
{ config, pkgs, lib, ... }:

let
  cs8409-driver = config.boot.kernelPackages.callPackage ({ stdenv, lib, fetchFromGitHub, kernel }:
    stdenv.mkDerivation {
      pname = "snd-hda-codec-cs8409";
      version = "0.1";
      src = fetchFromGitHub {
        owner = "davidjo";
        repo = "snd_hda_macbookpro";
        rev = "master";
        sha256 = lib.fakeSha256; # Ejecutar nixos-rebuild para obtener el hash exacto
      };
      hardeningDisable = [ "pic" ];
      nativeBuildInputs = kernel.moduleBuildDependencies;
      postPatch = ''
        sed -i 's/cs42l83_tip_sense(codec, 1);/cs42l83_tip_sense(codec, 0);/g' patch_cirrus/patch_cirrus_real84.h
      '';
      buildPhase = ''
        make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
          CFLAGS_MODULE="-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function" \
          M=$PWD/build/hda modules
      '';
      installPhase = ''
        install -D -m 644 build/hda/codecs/cirrus/snd-hda-codec-cs8409.ko $out/lib/modules/${kernel.modDirVersion}/extra/snd-hda-codec-cs8409.ko
      '';
    }) {};
in {
  boot.extraModulePackages = [ cs8409-driver ];

  # Soporte dual simultáneo para Altavoces internos y HDMI
  environment.etc."alsa-card-profile/mixer/profile-sets/9999-custom.conf".text = ''
    [Profile output:analog-stereo+output:hdmi-all+input:analog-stereo]
    description = Altavoces internos + HDMI + Micrófono
    output-mappings = analog-stereo hdmi-stereo hdmi-stereo-extra1 hdmi-stereo-extra2
    input-mappings = analog-stereo
    priority = 8000
    skip-probe = yes
  '';

  environment.etc."wireplumber/wireplumber.conf.d/50-imac-audio.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [ { "device.name" = "~alsa_card.pci-0000_00_1f.3*"; } ];
        actions = {
          update-props = {
            "device.profile" = "output:analog-stereo+output:hdmi-all+input:analog-stereo";
            "api.acp.auto-profile" = false;
          };
        };
      }
    ];
  '';
}
EOF

    ok "Archivo $NIX_MODULE generado con éxito."
    echo ""
    echo -e "\e[1;33mInstrucciones para activar en NixOS:\e[0m"
    echo "1. Agrega './cs8409-audio.nix' a los 'imports' en /etc/nixos/configuration.nix:"
    echo "     imports = [ ./hardware-configuration.nix ./cs8409-audio.nix ];"
    echo "2. Aplica la configuración ejecutando: sudo nixos-rebuild switch"
    echo ""
    aviso "Módulo experimental: no incluye force_speakers ni se ha probado en NixOS."
    pausa
}

# ------------------------------------------------------------------------------
# 9. Diagnóstico y desinstalación
# ------------------------------------------------------------------------------
diagnostico_audio() {
    echo -e "\n\e[1;34m============================================================\e[0m"
    echo -e "\e[1;32m Diagnóstico y Prueba de Audio del iMac\e[0m"
    echo -e "\e[1;34m============================================================\e[0m"
    echo "Kernel: $KVER    Usuario: $CURRENT_USER"
    echo ""
    echo "Módulo CS8409 cargado:"
    lsmod | grep -E "cs8409|snd_hda_intel" || echo "  [!] Módulo no cargado actualmente"
    echo ""
    echo "Archivo del módulo en uso:"
    modinfo -n snd_hda_codec_cs8409 2>/dev/null || echo "  [!] modinfo no encuentra snd_hda_codec_cs8409"
    if modinfo snd_hda_codec_cs8409 2>/dev/null | grep -q force_speakers; then
        echo "  Parche iMac: presente (tiene force_speakers)"
    else
        echo "  [!] Parche iMac: AUSENTE (el módulo no tiene force_speakers)"
    fi
    echo ""
    echo "Parámetros del módulo en memoria:"
    grep -H . /sys/module/snd_hda_codec_cs8409/parameters/* 2>/dev/null || echo "  [i] Sin parámetros en sysfs"
    echo ""
    echo "DKMS:"
    dkms status 2>/dev/null | grep -i macbookpro || echo "  [!] snd_hda_macbookpro no está registrado en DKMS"
    echo ""
    echo "Servicio guardián:"
    echo "  $(systemctl is-enabled cs8409-audio-guard.service 2>/dev/null || echo 'no instalado')"
    echo ""
    echo "Estado de conectores ALSA (amixer):"
    amixer -c 0 contents 2>/dev/null | grep -A 2 -i "Headphone Jack" || echo "  [i] Tarjeta ALSA no accesible"
    echo ""
    echo "Salidas de PipeWire / PulseAudio:"
    como_usuario pactl list sinks short 2>/dev/null || echo "  [i] No se pudo consultar PipeWire"
    echo ""
    read -r -p "¿Reproducir un sonido de prueba a volumen $VOLUMEN_PRUEBA? (s/n): " -n 1
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        probar_altavoces
    fi
    echo ""
    pausa
}

desinstalar() {
    echo -e "\n\e[1;31m============================================================\e[0m"
    echo -e "\e[1;31m Desinstalar el controlador de audio Apple CS8409\e[0m"
    echo -e "\e[1;31m============================================================\e[0m"
    echo "Se eliminarán el módulo DKMS, el servicio guardián y la configuración de audio."
    echo "Tras reiniciar se usará el módulo snd_hda_codec_cs8409 original del kernel."
    read -r -p "¿Continuar? (s/n): " -n 1
    echo
    [[ $REPLY =~ ^[Ss]$ ]] || { echo "Cancelado."; pausa; return 0; }
    registrar "desinstalar"

    dkms remove -m snd_hda_macbookpro/0.1 --all >> "$LOG_FILE" 2>&1 || true
    rm -rf "$SRC_DEST"
    systemctl disable --now cs8409-audio-guard.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/cs8409-audio-guard.service /usr/local/bin/check-cs8409-driver.sh
    rm -f /etc/modprobe.d/cs8409.conf
    rm -f /etc/wireplumber/wireplumber.conf.d/50-imac-audio.conf \
          /etc/alsa-card-profile/mixer/profile-sets/9999-custom.conf \
          /etc/alsa-card-profile/mixer/profile-sets/default.conf \
          /etc/alsa-card-profile/mixer/paths/hdmi-output-{0,1,2}.conf
    if [ "$CURRENT_UID" -ne 0 ] && [ -d "$USER_HOME" ]; then
        rm -f "$USER_HOME/.config/wireplumber/wireplumber.conf.d/50-imac-audio.conf" \
              "$USER_HOME"/.config/alsa-card-profile/mixer/profile-sets/{9999-custom,default}.conf \
              "$USER_HOME"/.config/alsa-card-profile/mixer/paths/hdmi-output-{0,1,2}.conf
    fi
    systemctl daemon-reload 2>/dev/null || true
    depmod -a

    info "Regenerando initramfs..."
    if command -v dracut &>/dev/null; then
        dracut --force >> "$LOG_FILE" 2>&1 || true
    elif command -v update-initramfs &>/dev/null; then
        update-initramfs -u >> "$LOG_FILE" 2>&1 || true
    elif command -v mkinitcpio &>/dev/null; then
        mkinitcpio -P >> "$LOG_FILE" 2>&1 || true
    fi

    ok "Desinstalación completada. Reinicia el equipo para terminar."
    pausa
}

autodetectar_e_instalar() {
    info "Detectando distribución instalada..."
    local distro_id="unknown" distro_like=""
    if [ -f /etc/os-release ]; then
        distro_id=$(. /etc/os-release; echo "${ID:-unknown}")
        distro_like=$(. /etc/os-release; echo "${ID_LIKE:-}")
    fi

    echo "ID detectado: $distro_id ($distro_like)"

    if [ -e /run/ostree-booted ]; then
        error "Sistema inmutable (rpm-ostree) detectado: este instalador no es compatible."
        echo "    Fedora Silverblue/Kinoite, Bazzite y similares tienen /usr de solo lectura."
        pausa
        return 1
    fi

    if [[ "$distro_id" =~ (fedora|rhel|centos|rocky|almalinux|sles|opensuse) ]] || [[ "$distro_like" =~ (fedora|rhel|suse) ]]; then
        instalar_rpm
    elif [[ "$distro_id" =~ (ubuntu|debian|linuxmint|pop|elementary|zorin) ]] || [[ "$distro_like" =~ debian ]]; then
        instalar_deb
    elif [[ "$distro_id" =~ (arch|manjaro|endeavouros|garuda) ]] || [[ "$distro_like" =~ arch ]]; then
        instalar_arch
    elif [ -f /etc/NIXOS ] || command -v nixos-rebuild &>/dev/null; then
        instalar_nix
    else
        aviso "No se pudo determinar automáticamente la distribución."
        echo "Por favor seleccione manualmente su familia de distribución en el menú."
        pausa
    fi
}

# ------------------------------------------------------------------------------
# 10. Menú Principal Interactivo
# ------------------------------------------------------------------------------
mostrar_menu() {
    clear
    echo -e "\e[1;34m=============================================================================\e[0m"
    echo -e "\e[1;32m      INSTALADOR UNIVERSAL DE AUDIO APPLE (CIRRUS CS8409 / TAS57642)  v$VERSION\e[0m"
    echo -e "\e[1;36m           Soporte probado para iMac18,1, iMac18,2, iMac18,3 y MBP\e[0m"
    echo -e "\e[1;34m=============================================================================\e[0m"
    echo -e " Kernel activo : \e[1;33m$KVER\e[0m"
    if [ -f /etc/os-release ]; then
        echo -e " Sistema       : \e[1;33m$(. /etc/os-release; echo "$PRETTY_NAME")\e[0m"
    fi
    echo -e " Usuario       : \e[1;33m$CURRENT_USER\e[0m"
    echo -e "\e[1;34m-----------------------------------------------------------------------------\e[0m"
    echo -e " Selecciona una opción:"
    echo ""
    echo -e "   \e[1;32m1)\e[0m \e[1;32mAutodetectar e instalar automáticamente (Recomendado)\e[0m"
    echo -e "   \e[1;37m2)\e[0m Instalar en sistemas basados en \e[1;33mRPM\e[0m (Fedora, RHEL, CentOS, openSUSE)"
    echo -e "   \e[1;37m3)\e[0m Instalar en sistemas basados en \e[1;33mDEB\e[0m (Ubuntu, Debian, Linux Mint, Pop!_OS)"
    echo -e "   \e[1;37m4)\e[0m Instalar en sistemas basados en \e[1;33mArch\e[0m (Arch Linux, Manjaro, EndeavourOS)"
    echo -e "   \e[1;37m5)\e[0m Generar módulo para \e[1;33mNix / NixOS\e[0m (experimental)"
    echo -e "   \e[1;36m6)\e[0m Configurar conmutación independiente HDMI / Altavoces (WirePlumber)"
    echo -e "   \e[1;37m7)\e[0m Diagnóstico de audio y prueba de altavoces"
    echo -e "   \e[1;35m8)\e[0m Desinstalar el controlador"
    echo -e "   \e[1;31m9)\e[0m Salir"
    echo ""
    echo -e "\e[1;34m-----------------------------------------------------------------------------\e[0m"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\e[1;34m============================================================\e[0m"
        echo -e "\e[1;33m [!] Este instalador requiere privilegios de administrador (root).\e[0m"
        echo -e "\e[1;34m============================================================\e[0m"
        echo -e "Solicitando elevación con sudo...\n"
        exec sudo bash "$0" "$@"
    fi

    while true; do
        mostrar_menu
        read -r -p "Ingresa tu opción [1-9]: " opcion
        case $opcion in
            1) autodetectar_e_instalar ;;
            2) instalar_rpm ;;
            3) instalar_deb ;;
            4) instalar_arch ;;
            5) instalar_nix ;;
            6)
                configurar_dual_audio_hdmi_altavoces
                detener_audio_usuario
                iniciar_audio_usuario
                ok "Configuración aplicada y servicios de sonido reiniciados."
                pausa
                ;;
            7) diagnostico_audio ;;
            8) desinstalar ;;
            9) echo -e "\nSaliendo del instalador. ¡Que disfrutes del sonido!\n"; exit 0 ;;
            *) error "Opción no válida."; sleep 1 ;;
        esac
    done
}

# Permite cargar las funciones con "source" (pruebas) sin abrir el menú
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
