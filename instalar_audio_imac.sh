#!/bin/bash
# ==============================================================================
# INSTALADOR UNIVERSAL DE AUDIO APPLE (CIRRUS CS8409 / TI TAS57642)
# Compatible con: Apple iMac18,1, iMac18,2, iMac18,3 y MacBook Pro
# Plataformas soportadas: RPM (Fedora/RHEL/SUSE), DEB (Ubuntu/Debian/Mint),
#                         Arch Linux (Manjaro/EndeavourOS) y Nix / NixOS
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# 1. Petición y Elevación Automática de SUDO
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;34m============================================================\e[0m"
    echo -e "\e[1;33m [!] Este instalador requiere privilegios de administrador (root).\e[0m"
    echo -e "\e[1;34m============================================================\e[0m"
    echo -e "Solicitando elevación con sudo...\n"
    exec sudo bash "$0" "$@"
fi

# Variables globales
KVER=$(uname -r)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SRC_DEST="/usr/src/snd_hda_macbookpro-0.1"
DESKTOP_SRC="$SCRIPT_DIR/snd_hda_macbookpro_imac"
PATCH_FILE="$SCRIPT_DIR/parches/imac-cs8409.patch"

# Usuario real que lanzó el instalador (no root), para PipeWire y su carpeta personal
CURRENT_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
    CURRENT_USER=$(id -un 1000 2>/dev/null || echo "root")
fi
USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
FALLBACK_SRC="$USER_HOME/snd_hda_macbookpro"

# ------------------------------------------------------------------------------
# 2. Funciones de Preparación de Código Fuente Parcheado
# ------------------------------------------------------------------------------
preparar_fuentes() {
    echo -e "\n\e[1;34m--> Preparando código fuente del controlador con correcciones de hardware...\e[0m"
    mkdir -p "$SRC_DEST"

    if [ -d "$DESKTOP_SRC" ] && [ -f "$DESKTOP_SRC/patch_cirrus/cirrus_apple.h" ]; then
        echo "Copiando fuentes parcheadas desde: $DESKTOP_SRC"
        cp -r "$DESKTOP_SRC"/* "$SRC_DEST"/
    elif [ -d "$FALLBACK_SRC" ] && [ -f "$FALLBACK_SRC/patch_cirrus/cirrus_apple.h" ]; then
        echo "Copiando fuentes parcheadas desde: $FALLBACK_SRC"
        cp -r "$FALLBACK_SRC"/* "$SRC_DEST"/
    else
        echo "Descargando controlador oficial y aplicando parches para iMac..."
        wget -qO- https://github.com/davidjo/snd_hda_macbookpro/archive/refs/heads/master.tar.gz | tar -xz -C /tmp
        cp -r /tmp/snd_hda_macbookpro-master/* "$SRC_DEST"/
        rm -rf /tmp/snd_hda_macbookpro-master
        
        # Aplicar el parche del iMac (tip-sense sin invertir + parámetro force_speakers)
        if [ -f "$PATCH_FILE" ] && (cd "$SRC_DEST" && patch -p1 --forward < "$PATCH_FILE"); then
            echo "Parche iMac aplicado correctamente."
        else
            echo "[!] El parche no aplica sobre esta versión; aplicando solo la corrección del jack."
            sed -i 's/cs42l83_tip_sense(codec, 1);/cs42l83_tip_sense(codec, 0);/g' "$SRC_DEST/patch_cirrus/patch_cirrus_real84.h"
            # Solo los 'exit' sueltos: no tocar 'exit 1' (romperia el manejo de errores)
            sed -i 's/^\([[:space:]]*\)exit$/\1exit 0/' "$SRC_DEST/install.cirrus.driver.sh" 2>/dev/null || true
        fi
    fi

    # Asegurar permisos correctos
    chown -R root:root "$SRC_DEST"
    chmod -R 755 "$SRC_DEST"
    echo -e "\e[1;32m[✓] Fuentes del controlador listas en $SRC_DEST\e[0m"
}

configurar_modprobe_y_guard() {
    echo -e "\n\e[1;34m--> Configurando persistencia y parámetros del controlador...\e[0m"
    mkdir -p /etc/modprobe.d

    cat << 'EOF' > /etc/modprobe.d/cs8409.conf
# Configuración para Apple Cirrus Logic CS8409 + TAS57642
# force_speakers=0 activa la detección automática de auriculares y altavoces internos
options snd_hda_codec_cs8409 force_speakers=0
EOF
    echo -e "\e[1;32m[✓] Archivo /etc/modprobe.d/cs8409.conf configurado.\e[0m"

    # Servicio de guardia para persistencia tras actualizaciones del kernel
    mkdir -p /usr/local/bin
    cat << 'EOF' > /usr/local/bin/check-cs8409-driver.sh
#!/bin/bash
KVER=$(uname -r)
HAS_MODULE=0

if [ -f "/lib/modules/$KVER/extra/snd-hda-codec-cs8409.ko.xz" ] || \
   [ -f "/lib/modules/$KVER/extra/snd-hda-codec-cs8409.ko" ] || \
   [ -f "/lib/modules/$KVER/extra/snd-hda-codec-cs8409.ko.zst" ] || \
   [ -f "/lib/modules/$KVER/updates/dkms/snd-hda-codec-cs8409.ko.xz" ] || \
   [ -f "/lib/modules/$KVER/updates/dkms/snd-hda-codec-cs8409.ko" ]; then
    HAS_MODULE=1
fi

if [ $HAS_MODULE -eq 0 ]; then
    echo "[CS8409-Guard] Controlador Apple no encontrado para kernel $KVER. Compilando con DKMS..."
    dkms install -m snd_hda_macbookpro/0.1 -k "$KVER" --force || true
    depmod -a "$KVER"
fi
EOF
    chmod 755 /usr/local/bin/check-cs8409-driver.sh

    cat << 'EOF' > /etc/systemd/system/cs8409-audio-guard.service
[Unit]
Description=Guardian de persistencia para audio Apple CS8409
DefaultDependencies=no
After=local-fs.target
Before=sound.target basic.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-cs8409-driver.sh
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable cs8409-audio-guard.service 2>/dev/null || true
    systemctl enable dkms.service 2>/dev/null || true
    echo -e "\e[1;32m[✓] Servicio guardián de persistencia systemd activado.\e[0m"
}

configurar_dual_audio_hdmi_altavoces() {
    echo -e "\n\e[1;34m--> Configurando soporte simultáneo para Altavoces internos y HDMI/DisplayPort...\e[0m"

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
    if [ -d "$USER_HOME" ]; then
        mkdir -p "$USER_HOME/.config/alsa-card-profile/mixer/profile-sets"
        mkdir -p "$USER_HOME/.config/alsa-card-profile/mixer/paths"
        mkdir -p "$USER_HOME/.config/wireplumber/wireplumber.conf.d"

        cp /etc/alsa-card-profile/mixer/profile-sets/default.conf "$USER_HOME/.config/alsa-card-profile/mixer/profile-sets/" 2>/dev/null || true
        cp /etc/alsa-card-profile/mixer/profile-sets/9999-custom.conf "$USER_HOME/.config/alsa-card-profile/mixer/profile-sets/"
        cp /etc/alsa-card-profile/mixer/paths/hdmi-output-*.conf "$USER_HOME/.config/alsa-card-profile/mixer/paths/"
        cp /etc/wireplumber/wireplumber.conf.d/50-imac-audio.conf "$USER_HOME/.config/wireplumber/wireplumber.conf.d/"
        rm -f "$USER_HOME/.config/wireplumber/wireplumber.conf.d/50-hdmi-auto.conf"

        chown -R "$CURRENT_USER:$CURRENT_USER" "$USER_HOME/.config/alsa-card-profile" "$USER_HOME/.config/wireplumber" 2>/dev/null || true
    fi

    echo -e "\e[1;32m[✓] Soporte dual simultáneo Altavoces / HDMI configurado exitosamente.\e[0m"
}

compilar_con_dkms() {
    echo -e "\n\e[1;34m--> Compilando e integrando módulo con DKMS para kernel $KVER...\e[0m"
    cd "$SRC_DEST"

    if dkms status | grep -q "snd_hda_macbookpro"; then
        echo "Eliminando registro anterior en DKMS..."
        dkms remove -m snd_hda_macbookpro/0.1 -k "$KVER" --force 2>/dev/null || true
    fi

    ./install.cirrus.driver.sh -i -k "$KVER" || true
    echo -e "\e[1;32m[✓] Compilación DKMS finalizada.\e[0m"
}

reiniciar_modulos_y_probar() {
    echo -e "\n\e[1;34m--> Aplicando recarga en caliente y probando sonido...\e[0m"
    mkdir -p /var/lib/alsa
    alsactl store 2>/dev/null || true

    killall -9 pipewire wireplumber pipewire-pulse 2>/dev/null || true
    fuser -k -9 /dev/snd/* 2>/dev/null || true
    sleep 1

    RELOAD_OK=0
    if modprobe -r snd_hda_intel snd_hda_codec_cs8409 2>/dev/null || rmmod -f snd_hda_intel snd_hda_codec_cs8409 2>/dev/null; then
        sleep 1
        modprobe snd_hda_codec_cs8409 force_speakers=0
        modprobe snd_hda_intel
        echo -e "\e[1;32m[✓] Módulos de audio recargados exitosamente.\e[0m"
        sleep 1
        alsactl restore 2>/dev/null || true
        RELOAD_OK=1
    else
        echo -e "\e[1;33m[i] Los controladores están en uso en este arranque. Se requerirá reiniciar.\e[0m"
    fi

    # Reiniciar servidor de sonido del usuario
    su - "$CURRENT_USER" -c "systemctl --user restart pipewire wireplumber" 2>/dev/null || true
    sleep 2

    echo -e "\e[1;32m--> Enviando tono de prueba a los altavoces internos...\e[0m"
    su - "$CURRENT_USER" -c "pactl set-sink-mute alsa_output.pci-0000_00_1f.3.analog-stereo 0 2>/dev/null || true"
    su - "$CURRENT_USER" -c "pactl set-sink-volume alsa_output.pci-0000_00_1f.3.analog-stereo 100% 2>/dev/null || true"
    su - "$CURRENT_USER" -c "pactl set-sink-port alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-speaker 2>/dev/null || true"
    su - "$CURRENT_USER" -c "pw-play /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || aplay -D plughw:0,0 /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true"

    echo ""
    echo -e "\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"
    echo "Estado de DKMS:"
    dkms status 2>/dev/null || true
    echo ""

    if [ $RELOAD_OK -eq 0 ]; then
        echo -e "\e[1;33mPara activar completamente los amplificadores de hardware TAS57642,\e[0m"
        echo -e "\e[1;33mte recomendamos reiniciar el equipo ahora.\e[0m"
        read -p "¿Deseas reiniciar el sistema ahora? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            reboot
        fi
    fi
}

# ------------------------------------------------------------------------------
# 3. Flujos por Familia de Distribución
# ------------------------------------------------------------------------------

instalar_rpm() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Instalando para Familia RPM (Fedora / RHEL / openSUSE)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"

    if command -v dnf &>/dev/null; then
        echo "Instalando paquetes con DNF..."
        dnf install -y kernel-devel-$KVER kernel-devel-matched kernel-headers gcc make patch git dkms alsa-utils wget psmisc
    elif command -v zypper &>/dev/null; then
        echo "Instalando paquetes con Zypper..."
        zypper install -y kernel-devel kernel-default-devel gcc make patch git dkms alsa-utils wget psmisc
    else
        echo "No se encontró dnf ni zypper, intentando continuar..."
    fi

    preparar_fuentes
    compilar_con_dkms
    configurar_modprobe_y_guard
    configurar_dual_audio_hdmi_altavoces

    echo -e "\n\e[1;34m--> Actualizando initramfs con dracut...\e[0m"
    dracut --force --kver "$KVER" 2>/dev/null || dracut --force || true

    reiniciar_modulos_y_probar
}

instalar_deb() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Instalando para Familia DEB (Ubuntu / Debian / Linux Mint)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"

    echo "Actualizando índices de paquetes e instalando dependencias..."
    apt-get update -y
    apt-get install -y linux-headers-$KVER build-essential dkms alsa-utils patch git wget psmisc

    preparar_fuentes
    compilar_con_dkms
    configurar_modprobe_y_guard
    configurar_dual_audio_hdmi_altavoces

    echo -e "\n\e[1;34m--> Actualizando initramfs con update-initramfs...\e[0m"
    update-initramfs -u -k "$KVER" 2>/dev/null || update-initramfs -u || true

    reiniciar_modulos_y_probar
}

instalar_arch() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Instalando para Familia Arch (Arch / Manjaro / EndeavourOS)\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"

    # Detectar paquete de cabeceras correspondiente
    HEADER_PKG="linux-headers"
    if [[ "$KVER" == *"lts"* ]]; then
        HEADER_PKG="linux-lts-headers"
    elif [[ "$KVER" == *"zen"* ]]; then
        HEADER_PKG="linux-zen-headers"
    elif [[ "$KVER" == *"hardened"* ]]; then
        HEADER_PKG="linux-hardened-headers"
    fi

    echo "Instalando cabeceras ($HEADER_PKG) y utilidades con Pacman..."
    pacman -Sy --needed --noconfirm base-devel dkms alsa-utils wget patch git psmisc "$HEADER_PKG"

    preparar_fuentes
    compilar_con_dkms
    configurar_modprobe_y_guard
    configurar_dual_audio_hdmi_altavoces

    echo -e "\n\e[1;34m--> Actualizando initramfs con mkinitcpio...\e[0m"
    mkinitcpio -P || true

    reiniciar_modulos_y_probar
}

instalar_nix() {
    echo -e "\n\e[1;32m============================================================\e[0m"
    echo -e "\e[1;32m Configuración para Nix / NixOS\e[0m"
    echo -e "\e[1;32m============================================================\e[0m"

    NIX_MODULE="/etc/nixos/cs8409-audio.nix"
    echo -e "Generando módulo declarativo de NixOS en: \e[1;33m$NIX_MODULE\e[0m"
    mkdir -p /etc/nixos

    cat << 'EOF' > "$NIX_MODULE"
# Módulo de Audio Apple Cirrus CS8409 para NixOS
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
  boot.extraModprobeConfig = ''
    options snd_hda_codec_cs8409 force_speakers=0
  '';

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

    echo -e "\e[1;32m[✓] Archivo $NIX_MODULE generado con éxito.\e[0m"
    echo ""
    echo -e "\e[1;33mInstrucciones para activar en NixOS:\e[0m"
    echo "1. Agrega './cs8409-audio.nix' a los 'imports' en /etc/nixos/configuration.nix:"
    echo "     imports = [ ./hardware-configuration.nix ./cs8409-audio.nix ];"
    echo "2. Aplica la configuración ejecutando: sudo nixos-rebuild switch"
    echo ""
    read -p "Presiona [Enter] para volver al menú principal..."
}

diagnostico_audio() {
    echo -e "\n\e[1;34m============================================================\e[0m"
    echo -e "\e[1;32m Diagnóstico y Prueba de Audio del iMac\e[0m"
    echo -e "\e[1;34m============================================================\e[0m"
    echo "Kernel: $KVER"
    echo "Módulo CS8409 cargado:"
    lsmod | grep -E "cs8409|snd_hda_intel" || echo "  [!] Módulo no cargado actualmente"
    echo ""
    echo "Parámetros del módulo en memoria:"
    cat /sys/module/snd_hda_codec_cs8409/parameters/* 2>/dev/null || echo "  [i] Sin parámetros en sysfs"
    echo ""
    echo "Estado de conectores ALSA (amixer):"
    amixer -c 0 contents 2>/dev/null | grep -A 2 -i "Headphone Jack" || echo "  [i] Tarjeta ALSA no accesible"
    echo ""
    echo "Salidas de PipeWire / PulseAudio:"
    pactl list sinks short 2>/dev/null || true
    echo ""
    echo "Enviando señal de prueba de audio..."
    su - "$CURRENT_USER" -c "pactl set-sink-mute alsa_output.pci-0000_00_1f.3.analog-stereo 0 2>/dev/null || true"
    su - "$CURRENT_USER" -c "pactl set-sink-volume alsa_output.pci-0000_00_1f.3.analog-stereo 100% 2>/dev/null || true"
    su - "$CURRENT_USER" -c "pactl set-sink-port alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-speaker 2>/dev/null || true"
    su - "$CURRENT_USER" -c "pw-play /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || aplay -D plughw:0,0 /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true"
    echo ""
    read -p "Presiona [Enter] para volver al menú principal..."
}

autodetectar_e_instalar() {
    echo -e "\n\e[1;34m--> Detectando distribución instalada...\e[0m"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi

    echo "ID detectado: $DISTRO_ID ($DISTRO_LIKE)"

    if [[ "$DISTRO_ID" =~ (fedora|rhel|centos|rocky|almalinux|sles|opensuse) ]] || [[ "$DISTRO_LIKE" =~ (fedora|rhel) ]]; then
        instalar_rpm
    elif [[ "$DISTRO_ID" =~ (ubuntu|debian|linuxmint|pop|elementary|zorin) ]] || [[ "$DISTRO_LIKE" =~ debian ]]; then
        instalar_deb
    elif [[ "$DISTRO_ID" =~ (arch|manjaro|endeavouros|garuda) ]] || [[ "$DISTRO_LIKE" =~ arch ]]; then
        instalar_arch
    elif [ -f /etc/NIXOS ] || command -v nixos-rebuild &>/dev/null; then
        instalar_nix
    else
        echo -e "\e[1;33m[!] No se pudo determinar automáticamente la distribución.\e[0m"
        echo "Por favor seleccione manualmente su familia de distribución en el menú."
        read -p "Presiona [Enter] para continuar..."
    fi
}

# ------------------------------------------------------------------------------
# 4. Menú Principal Interactivo
# ------------------------------------------------------------------------------
mostrar_menu() {
    clear
    echo -e "\e[1;34m=============================================================================\e[0m"
    echo -e "\e[1;32m      INSTALADOR UNIVERSAL DE AUDIO APPLE (CIRRUS CS8409 / TAS57642)\e[0m"
    echo -e "\e[1;36m           Soporte probado para iMac18,1, iMac18,2, iMac18,3 y MBP\e[0m"
    echo -e "\e[1;34m=============================================================================\e[0m"
    echo -e " Kernel activo : \e[1;33m$KVER\e[0m"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e " Sistema       : \e[1;33m$PRETTY_NAME\e[0m"
    fi
    echo -e "\e[1;34m-----------------------------------------------------------------------------\e[0m"
    echo -e " Selecciona una opción:"
    echo ""
    echo -e "   \e[1;32m1)\e[0m \e[1;32mAutodetectar e instalar automáticamente (Recomendado)\e[0m"
    echo -e "   \e[1;37m2)\e[0m Instalar en sistemas basados en \e[1;33mRPM\e[0m (Fedora, RHEL, CentOS, openSUSE)"
    echo -e "   \e[1;37m3)\e[0m Instalar en sistemas basados en \e[1;33mDEB\e[0m (Ubuntu, Debian, Linux Mint, Pop!_OS)"
    echo -e "   \e[1;37m4)\e[0m Instalar en sistemas basados en \e[1;33mArch\e[0m (Arch Linux, Manjaro, EndeavourOS)"
    echo -e "   \e[1;37m5)\e[0m Instalar / Generar módulo para \e[1;33mNix / NixOS\e[0m"
    echo -e "   \e[1;36m6)\e[0m Configurar conmutación independiente HDMI / Altavoces (WirePlumber)"
    echo -e "   \e[1;37m7)\e[0m Diagnóstico de audio y prueba de altavoces"
    echo -e "   \e[1;31m8)\e[0m Salir"
    echo ""
    echo -e "\e[1;34m-----------------------------------------------------------------------------\e[0m"
    read -p "Ingresa tu opción [1-8]: " opcion

    case $opcion in
        1) autodetectar_e_instalar ;;
        2) instalar_rpm ;;
        3) instalar_deb ;;
        4) instalar_arch ;;
        5) instalar_nix ;;
        6) 
            configurar_dual_audio_hdmi_altavoces
            su - "$CURRENT_USER" -c "systemctl --user restart pipewire wireplumber" 2>/dev/null || true
            echo -e "\n\e[1;32m[✓] Configuración aplicada y servicios de sonido reiniciados.\e[0m"
            read -p "Presiona [Enter] para volver al menú..."
            mostrar_menu
            ;;
        7) diagnostico_audio ;;
        8) echo -e "\nSaliendo del instalador. ¡Que disfrutes del sonido!\n"; exit 0 ;;
        *) echo -e "\e[1;31mOpción no válida.\e[0m"; sleep 1; mostrar_menu ;;
    esac
}

# Ejecutar el menú principal
mostrar_menu
