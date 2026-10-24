# 🔊 Audio del iMac 2017 en Linux — Cirrus Logic CS8409

**Solución completa para que funcionen los altavoces internos, los auriculares y el HDMI de los Apple iMac de 2017 (iMac18,1 · iMac18,2 · iMac18,3) en Linux.**

Incluye un driver parcheado basado en [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro), un **instalador universal con menú** (Fedora, Ubuntu/Debian, Arch, openSUSE y NixOS), compilación automática con **DKMS** para que sobreviva a las actualizaciones del kernel, un **selector de modo altavoces / auriculares** y la configuración de **PipeWire / WirePlumber** para usar los altavoces y el HDMI a la vez.

```bash
git clone https://github.com/riqgonzalo-lgtm/imac-2017-linux-audio-cs8409.git
cd imac-2017-linux-audio-cs8409
./instalar_audio_imac.sh        # elige la opción 1 (autodetectar)
```

---

## Índice

1. [El problema](#1-el-problema)
2. [¿Es mi equipo?](#2-es-mi-equipo)
3. [Por qué ocurre (causa raíz)](#3-por-qué-ocurre-causa-raíz)
4. [La solución: qué cambia este driver](#4-la-solución-qué-cambia-este-driver)
5. [Requisitos](#5-requisitos)
6. [Instalación](#6-instalación)
7. [El instalador, opción por opción](#7-el-instalador-opción-por-opción)
8. [Qué hace la instalación, paso a paso](#8-qué-hace-la-instalación-paso-a-paso)
9. [Archivos que crea o modifica en el sistema](#9-archivos-que-crea-o-modifica-en-el-sistema)
10. [Modo altavoces / auriculares (`force_speakers`)](#10-modo-altavoces--auriculares-force_speakers)
11. [Altavoces internos + HDMI al mismo tiempo](#11-altavoces-internos--hdmi-al-mismo-tiempo)
12. [NixOS](#12-nixos)
13. [Actualizaciones del kernel](#13-actualizaciones-del-kernel)
14. [Diagnóstico y solución de problemas](#14-diagnóstico-y-solución-de-problemas)
15. [Desinstalar](#15-desinstalar)
16. [Limitaciones conocidas](#16-limitaciones-conocidas)
17. [Estructura del repositorio](#17-estructura-del-repositorio)
18. [Créditos y licencia](#18-créditos-y-licencia)

---

## 1. El problema

Al instalar Linux en un iMac de 2017 aparece alguno de estos síntomas:

- 🔇 **Los altavoces internos no suenan**, aunque el control de volumen se mueve y las apps parecen reproducir.
- 🎧 El sistema dice que hay **auriculares conectados cuando no los hay**, y la salida queda fijada en «Auriculares».
- Solo aparece la salida **HDMI / DisplayPort**, o ninguna salida analógica.
- Al conectar o desconectar el jack no cambia nada.
- Tras actualizar el kernel, el sonido que se había conseguido **desaparece otra vez**.

## 2. ¿Es mi equipo?

| Modelo (identificador) | Equipo | Probado |
|---|---|---|
| `iMac18,1` | iMac 21,5" (2017) | ✅ Principal |
| `iMac18,2` | iMac 21,5" Retina 4K (2017) | Previsto (mismo hardware de audio) |
| `iMac18,3` | iMac 27" Retina 5K (2017) | Previsto (mismo hardware de audio) |
| MacBook Pro con CS8409 | MacBook Pro 2016–2017 | Soportado por el driver original |

Compruébalo así:

```bash
# Modelo del equipo
cat /sys/class/dmi/id/product_name          # → iMac18,1 / iMac18,2 / iMac18,3

# Chip de audio
grep -m1 Codec /proc/asound/card*/codec#*   # → Codec: Cirrus Logic CS8409

# Subsystem ID de Apple
grep -m1 "Subsystem Id" /proc/asound/card*/codec#*   # → 0x106b1000 / 0x106b0f00 / 0x106b0e00
```

Si el codec es **Cirrus Logic CS8409** y el subsystem empieza por `0x106b`, esta solución es para ti.

## 3. Por qué ocurre (causa raíz)

El audio de estos iMac está repartido en varios chips:

```
                ┌──────────────────────────────┐
  Intel HDA ───►│  Cirrus Logic CS8409         │  puente HDA ⇄ I²C/I²S
  (PCH, 00:1f.3)│  (codec "bridge")            │
                └───────┬───────────────┬──────┘
                        │ I²C / I²S     │ I²C / I²S
              ┌─────────▼──────┐  ┌─────▼───────────────────┐
              │ Cirrus CS42L83 │  │ Amplificadores TI       │
              │ codec del jack │  │ TAS5764x ("TAS57642")   │
              │ (auriculares,  │  │ → 4 altavoces internos  │
              │  micro, sensor)│  │   (2 tweeter + 2 woofer)│
              └────────────────┘  └─────────────────────────┘
```

1. **El kernel estándar no sabe programar el hardware de Apple.** El módulo `snd_hda_codec_cs8409` del kernel soporta placas Dell y de referencia de Cirrus, pero no la secuencia de arranque que Apple usa para los amplificadores y el codec del jack. Sin ella los amplificadores nunca se encienden.
2. **El driver de davidjo** ([snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)) reimplementa esa secuencia extrayéndola de macOS y funciona en MacBook Pro y en varios iMac.
3. **Pero en el iMac el sensor del jack se lee al revés.** El driver original asume que los iMac (`0x106b1000`, `0x106b0f00`, `0x106b0e00`) tienen el circuito de detección invertido y llama a `cs42l83_tip_sense(codec, 1)`. En estos equipos eso provoca un **falso positivo permanente de «auriculares conectados»**: el driver marca `jack_present = 1`, envía todo el audio a la salida de auriculares y **silencia los altavoces internos**.

## 4. La solución: qué cambia este driver

La carpeta [`snd_hda_macbookpro_imac/`](snd_hda_macbookpro_imac) es el driver de davidjo con **tres cambios**. Están también en un parche aparte: [`parches/imac-cs8409.patch`](parches/imac-cs8409.patch) (generado contra el commit `89b22ff` del original).

### 4.1 Sensor del jack sin invertir — `patch_cirrus/patch_cirrus_real84.h`

```diff
-        // apparently the imacs use an inverted circuit for physical sensing of jack being plugged in
-        if (codec->core.subsystem_id == 0x106b1000 || codec->core.subsystem_id == 0x106b0f00 || codec->core.subsystem_id == 0x106b0e00)
-                cs42l83_tip_sense(codec, 1);
-        else
-                cs42l83_tip_sense(codec, 0);
+        /* Do not invert tip sense (invert = 0).
+         * Inverting tip sense causes false positive headphone presence on iMacs,
+         * locking the audio subsystem to headphones and muting internal speakers.
+         */
+        cs42l83_tip_sense(codec, 0);
```

Es la corrección principal: con el sensor sin invertir, el driver ve el jack vacío, enciende los amplificadores y usa los altavoces.

### 4.2 Nuevo parámetro `force_speakers` — `patch_cirrus/cirrus_apple.h`

```c
static int force_speakers = 0;
module_param(force_speakers, int, 0644);
MODULE_PARM_DESC(force_speakers, "Force internal speakers active (1 = always force speakers, 0 = auto)");
```

Es una opción del módulo que se puede cambiar en caliente desde `/sys/module/snd_hda_codec_cs8409/parameters/force_speakers` (permisos `0644`):

| Valor | Comportamiento |
|---|---|
| `0` (por defecto) | **Automático**: altavoces sin jack, auriculares al conectar el jack. |
| `1` | **Altavoces forzados**: se ignora el jack. Es la salida de emergencia si en tu unidad el sensor sigue dando falsos positivos. |

Se consulta en todos los puntos donde el driver decide la salida:

| Archivo | Punto de decisión | Cambio |
|---|---|---|
| `cirrus_apple.h` | Respuesta al *pin sense* del jack | `jack_present` → `!force_speakers && jack_present` |
| `patch_cirrus_new84.h` | Preparación del stream de reproducción (2 sitios) | ídem |
| `patch_cirrus_real84.h` | Arranque: «auriculares ya conectados» | `retval & 0x80` → `!force_speakers && (retval & 0x80)` |
| `patch_cirrus_real84.h` | Interrupción de conexión del jack | no marca el jack si `force_speakers=1` |

### 4.3 `install.cirrus.driver.sh` termina con éxito en DKMS

```diff
-    ls -lA $update_dir
-    exit
+    ls -lA $update_dir 2>/dev/null || ls -lA /lib/modules/${UNAME}/extra 2>/dev/null || true
+    exit 0
```

En Fedora, DKMS instala el módulo en `/lib/modules/<kernel>/extra` y no en `updates/dkms`. El `ls` del original fallaba y el script devolvía error aunque la instalación hubiera ido bien.

## 5. Requisitos

- Un iMac 2017 (o MacBook Pro) con **CS8409** (ver [sección 2](#2-es-mi-equipo)).
- Una distribución **tradicional** (no inmutable) de estas familias:
  - **RPM**: Fedora, RHEL, CentOS, Rocky, AlmaLinux, openSUSE/SLES
  - **DEB**: Ubuntu, Debian, Linux Mint, Pop!_OS, elementary, Zorin
  - **Arch**: Arch Linux, Manjaro, EndeavourOS, Garuda
  - **NixOS** (genera un módulo declarativo)
- Conexión a Internet (para dependencias y, si hace falta, el driver original).
- `sudo`. El instalador pide la contraseña solo.
- **PipeWire + WirePlumber** para la parte de HDMI simultáneo (por defecto en las distros actuales).
- `konsole` solo para los accesos directos de escritorio. Los scripts funcionan en cualquier terminal.

## 6. Instalación

### Opción A: terminal

```bash
git clone https://github.com/riqgonzalo-lgtm/imac-2017-linux-audio-cs8409.git
cd imac-2017-linux-audio-cs8409
./instalar_audio_imac.sh
```

Elige **`1) Autodetectar e instalar automáticamente`**. Al terminar oirás un sonido de prueba. Si los módulos estaban en uso, el instalador ofrece reiniciar.

> **Importante:** no muevas ni borres la carpeta del repositorio antes de instalar. El instalador busca el driver parcheado en `./snd_hda_macbookpro_imac`. Tras la instalación el código queda copiado en `/usr/src/snd_hda_macbookpro-0.1` y la carpeta ya no es necesaria.

### Opción B: accesos directos de escritorio

```bash
./crear_lanzadores.sh
```

Crea en el menú de aplicaciones (y en el Escritorio) dos accesos que apuntan a la carpeta donde clonaste el repo:

- **Instalador Audio Apple (CS8409)**: abre el instalador en Konsole.
- **Modo de Audio Apple (Altavoces / Auriculares)**: abre el selector de modo.

## 7. El instalador, opción por opción

```
=============================================================================
      INSTALADOR UNIVERSAL DE AUDIO APPLE (CIRRUS CS8409 / TAS57642)
           Soporte probado para iMac18,1, iMac18,2, iMac18,3 y MBP
=============================================================================
 Kernel activo : 6.x.y
 Sistema       : Fedora Linux 4x (Workstation Edition)
-----------------------------------------------------------------------------
   1) Autodetectar e instalar automáticamente (Recomendado)
   2) Instalar en sistemas basados en RPM (Fedora, RHEL, CentOS, openSUSE)
   3) Instalar en sistemas basados en DEB (Ubuntu, Debian, Linux Mint, Pop!_OS)
   4) Instalar en sistemas basados en Arch (Arch Linux, Manjaro, EndeavourOS)
   5) Instalar / Generar módulo para Nix / NixOS
   6) Configurar conmutación independiente HDMI / Altavoces (WirePlumber)
   7) Diagnóstico de audio y prueba de altavoces
   8) Salir
```

| Opción | Función interna | Qué hace |
|---|---|---|
| **1** | `autodetectar_e_instalar` | Lee `/etc/os-release` (`ID` e `ID_LIKE`) y lanza el flujo RPM, DEB, Arch o Nix que corresponda. |
| **2** | `instalar_rpm` | Dependencias con `dnf` (o `zypper`), compilación DKMS, configuración e initramfs con `dracut`. |
| **3** | `instalar_deb` | Dependencias con `apt-get`, compilación DKMS, configuración e initramfs con `update-initramfs`. |
| **4** | `instalar_arch` | Dependencias con `pacman` (elige `linux-headers`, `-lts`, `-zen` o `-hardened` según tu kernel) e initramfs con `mkinitcpio -P`. |
| **5** | `instalar_nix` | Genera `/etc/nixos/cs8409-audio.nix` (ver [sección 12](#12-nixos)). |
| **6** | `configurar_dual_audio_hdmi_altavoces` | Solo la parte de PipeWire/WirePlumber y reinicia el audio del usuario. |
| **7** | `diagnostico_audio` | Muestra módulos cargados, parámetros, estado del jack y salidas de PipeWire, y reproduce un sonido de prueba. |
| **8** | — | Sale. |

## 8. Qué hace la instalación, paso a paso

Los flujos RPM, DEB y Arch siguen la misma secuencia:

### Paso 0: elevación a root
Si no se ejecuta como root, el script se relanza con `exec sudo bash "$0"`. También detecta el **usuario real** (`$SUDO_USER`) para configurar su PipeWire y su carpeta personal.

### Paso 1: dependencias

| Familia | Paquetes |
|---|---|
| Fedora / RHEL | `kernel-devel-$(uname -r) kernel-devel-matched kernel-headers gcc make patch git dkms alsa-utils wget psmisc` |
| openSUSE | `kernel-devel kernel-default-devel gcc make patch git dkms alsa-utils wget psmisc` |
| Debian / Ubuntu | `linux-headers-$(uname -r) build-essential dkms alsa-utils patch git wget psmisc` |
| Arch | `base-devel dkms alsa-utils wget patch git psmisc linux[-lts/-zen/-hardened]-headers` |

### Paso 2: código fuente del driver (`preparar_fuentes`)
Busca el driver parcheado en este orden y lo copia a **`/usr/src/snd_hda_macbookpro-0.1`**, la ruta que espera DKMS:

1. `./snd_hda_macbookpro_imac` (la carpeta de este repo), **lo normal**.
2. `~/snd_hda_macbookpro` del usuario, si contiene `patch_cirrus/cirrus_apple.h`.
3. **Respaldo**: descarga el driver original de GitHub y le aplica `parches/imac-cs8409.patch`. Si el original ha cambiado tanto que el parche no aplica, hace al menos la corrección del jack con `sed`.

### Paso 3: compilación con DKMS (`compilar_con_dkms`)
Quita cualquier registro anterior de `snd_hda_macbookpro/0.1` en DKMS y ejecuta `install.cirrus.driver.sh -i`. Ese script:

- descarga el código fuente del subsistema de sonido **exactamente de tu versión de kernel**;
- le aplica los parches de Apple de davidjo (más los de este repo);
- compila solo `snd-hda-codec-cs8409.ko`;
- lo registra en DKMS (`dkms.conf`, `AUTOINSTALL="yes"`), que lo instala en `/lib/modules/<kernel>/extra` o `updates/dkms`.

Funciona con kernels anteriores y posteriores a la reorganización del sonido de la 6.17: el script detecta la versión y usa `install.cirrus.driver.pre617.sh` si hace falta.

### Paso 4: persistencia (`configurar_modprobe_y_guard`)
- Escribe `/etc/modprobe.d/cs8409.conf` con `options snd_hda_codec_cs8409 force_speakers=0`.
- Instala `/usr/local/bin/check-cs8409-driver.sh`, que comprueba si existe el módulo para el kernel arrancado y, si falta, lo compila con `dkms install --force` y ejecuta `depmod`.
- Crea y habilita el servicio **`cs8409-audio-guard.service`** (oneshot, antes de `sound.target`) que lanza ese script en cada arranque.
- Habilita `dkms.service` si existe.

### Paso 5: perfiles de audio (`configurar_dual_audio_hdmi_altavoces`)
Configura ALSA Card Profile y WirePlumber para tener altavoces, HDMI y micrófono a la vez (ver [sección 11](#11-altavoces-internos--hdmi-al-mismo-tiempo)).

### Paso 6: initramfs
Regenera el initramfs para que arranque con el módulo nuevo: `dracut --force` (Fedora), `update-initramfs -u` (Debian/Ubuntu) o `mkinitcpio -P` (Arch).

### Paso 7: recarga en caliente y prueba (`reiniciar_modulos_y_probar`)
1. Guarda los volúmenes de ALSA (`alsactl store`).
2. Cierra PipeWire, WirePlumber y cualquier proceso que tenga abierto `/dev/snd/*`.
3. Descarga `snd_hda_intel` y `snd_hda_codec_cs8409` y los vuelve a cargar con `force_speakers=0`.
4. Restaura volúmenes, reinicia PipeWire del usuario, quita el silencio, pone el volumen al 100 %, selecciona el puerto **altavoces** y reproduce `complete.oga`.
5. Si los módulos no se pudieron descargar (estaban en uso), **pregunta si quieres reiniciar**.

## 9. Archivos que crea o modifica en el sistema

| Ruta | Propósito |
|---|---|
| `/usr/src/snd_hda_macbookpro-0.1/` | Código del driver para DKMS |
| `/lib/modules/<kernel>/extra/snd-hda-codec-cs8409.ko*` (o `updates/dkms/`) | Módulo compilado |
| `/etc/modprobe.d/cs8409.conf` | Parámetro `force_speakers` persistente |
| `/usr/local/bin/check-cs8409-driver.sh` | Script guardián |
| `/etc/systemd/system/cs8409-audio-guard.service` | Servicio guardián en el arranque |
| `/etc/alsa-card-profile/mixer/profile-sets/default.conf` | Copia del perfil por defecto |
| `/etc/alsa-card-profile/mixer/profile-sets/9999-custom.conf` | Perfil «Altavoces + HDMI + Micrófono» |
| `/etc/alsa-card-profile/mixer/paths/hdmi-output-{0,1,2}.conf` | HDMI sin depender del estado del conector |
| `/etc/wireplumber/wireplumber.conf.d/50-imac-audio.conf` | Perfil por defecto y nombres de las salidas |
| `~/.config/alsa-card-profile/…` y `~/.config/wireplumber/…` | Réplica en el perfil del usuario |
| `/etc/nixos/cs8409-audio.nix` | Solo en NixOS |
| `/var/lib/alsa/asound.state` | Volúmenes guardados por `alsactl` |

## 10. Modo altavoces / auriculares (`force_speakers`)

```bash
./cambiar_modo_audio.sh
```

```
============================================================
       CONFIGURADOR DE MODO DE AUDIO APPLE (CS8409)
============================================================
Modo actual: Detección Automática (force_speakers=0)

Selecciona el modo deseado:
  1) Activar Detección Automática (Altavoces <-> Auriculares)
  2) Forzar Altavoces Internos permanentemente
  3) Salir
```

El script:

1. lee el modo actual de `/sys/module/snd_hda_codec_cs8409/parameters/force_speakers`;
2. escribe el nuevo valor en ese mismo archivo, así que **el cambio se aplica al momento** sin reiniciar;
3. lo guarda en `/etc/modprobe.d/cs8409.conf` para que se mantenga tras reiniciar.

A mano sería así:

```bash
# Ver el modo actual
cat /sys/module/snd_hda_codec_cs8409/parameters/force_speakers
# Forzar altavoces ahora mismo
echo 1 | sudo tee /sys/module/snd_hda_codec_cs8409/parameters/force_speakers
# Hacerlo permanente
echo "options snd_hda_codec_cs8409 force_speakers=1" | sudo tee /etc/modprobe.d/cs8409.conf
```

> Si al cambiar en caliente la salida no conmuta enseguida, conecta y desconecta el jack o reinicia la reproducción. El driver evalúa el parámetro al recibir eventos del jack y al iniciar un stream.

## 11. Altavoces internos + HDMI al mismo tiempo

Por defecto, PipeWire ofrece **un perfil por tarjeta**: o salida analógica o HDMI. Como en el iMac ambos cuelgan de la misma controladora Intel HDA (`0000:00:1f.3`), conectar una pantalla externa puede «robar» el audio a los altavoces.

La opción 6 (que también forma parte de la instalación completa) crea:

**Un perfil combinado** (`9999-custom.conf`):

```ini
[Profile output:analog-stereo+output:hdmi-all+input:analog-stereo]
description = Altavoces internos + HDMI + Micrófono
output-mappings = analog-stereo hdmi-stereo hdmi-stereo-extra1 hdmi-stereo-extra2
input-mappings = analog-stereo
priority = 8000
skip-probe = yes
```

**Rutas HDMI** que no dependen del estado del conector (`state.unplugged = unknown`), para que las salidas HDMI no desaparezcan ni se apaguen.

**Una regla de WirePlumber** que fija ese perfil en la tarjeta, desactiva el cambio automático de perfil (`api.acp.auto-profile = false`) y pone nombres claros a cada salida:

| Nodo de PipeWire | Nombre visible |
|---|---|
| `alsa_output.pci-0000_00_1f.3.analog-stereo` | Altavoces internos (iMac) |
| `alsa_output.pci-0000_00_1f.3.hdmi-stereo` | Audio HDMI (Pantalla / Proyector) |
| `alsa_output.pci-0000_00_1f.3.hdmi-stereo-extra1` | Audio HDMI 2 (DisplayPort) |
| `alsa_output.pci-0000_00_1f.3.hdmi-stereo-extra2` | Audio HDMI 3 (Thunderbolt / DisplayPort) |

Así puedes elegir cada salida por separado en los ajustes de sonido de KDE o GNOME, o enviar apps distintas a salidas distintas.

## 12. NixOS

En NixOS no se compila nada a mano. La opción 5 genera **`/etc/nixos/cs8409-audio.nix`**, un módulo declarativo que:

- construye `snd-hda-codec-cs8409` desde `davidjo/snd_hda_macbookpro` para `config.boot.kernelPackages`;
- aplica la corrección del jack (`cs42l83_tip_sense(codec, 0)`) en `postPatch`;
- lo añade a `boot.extraModulePackages`;
- fija `options snd_hda_codec_cs8409 force_speakers=0`;
- instala el perfil combinado y la regla de WirePlumber con `environment.etc`.

Para activarlo:

```nix
# /etc/nixos/configuration.nix
imports = [ ./hardware-configuration.nix ./cs8409-audio.nix ];
```

```bash
sudo nixos-rebuild switch
```

> La primera vez fallará con un error de hash, porque se usa `lib.fakeSha256`. Copia el hash `got: sha256-…` que muestra Nix, ponlo en el campo `sha256` y vuelve a ejecutar `nixos-rebuild switch`. Ten en cuenta que el módulo de NixOS solo aplica la corrección del jack, no el parámetro `force_speakers`.

## 13. Actualizaciones del kernel

El módulo está compilado para un kernel concreto, así que hay dos protecciones para que el sonido no se pierda al actualizar:

1. **DKMS** (`AUTOINSTALL="yes"`): cuando el gestor de paquetes instala un kernel nuevo, DKMS recompila el módulo automáticamente, siempre que estén instaladas las cabeceras de ese kernel.
2. **`cs8409-audio-guard.service`**: en cada arranque comprueba que el módulo exista para el kernel actual y, si falta, lo compila antes de que arranque el sonido.

> En Fedora, `kernel-devel-matched` hace que las cabeceras se actualicen junto con el kernel. En Debian/Ubuntu instala el metapaquete de cabeceras (p. ej. `linux-headers-generic`) para el mismo efecto.

## 14. Diagnóstico y solución de problemas

La opción **7** del instalador lo muestra todo de una vez. A mano:

```bash
lsmod | grep -E "cs8409|snd_hda_intel"                       # ¿módulo cargado?
modinfo snd_hda_codec_cs8409 | grep -E "filename|parm"       # ¿es el de DKMS? ¿tiene force_speakers?
cat /sys/module/snd_hda_codec_cs8409/parameters/force_speakers
dkms status                                                   # snd_hda_macbookpro/0.1, <kernel>: installed
sudo dmesg | grep -iE "cs8409|cs42l83|tas57"                  # mensajes del driver
amixer -c 0 contents | grep -A2 -i "Headphone Jack"           # estado del jack según ALSA
pactl list sinks short                                        # salidas de PipeWire
systemctl status cs8409-audio-guard.service
```

| Síntoma | Causa probable | Solución |
|---|---|---|
| `modinfo` muestra un archivo en `kernel/sound/…` (no `extra` ni `updates`) | Se carga el módulo del kernel, no el parcheado | `sudo depmod -a` y reinicia. Comprueba `dkms status`. |
| `modinfo` no lista `force_speakers` | El módulo cargado no lleva el parche del iMac | Reinstala con la opción 1 desde la carpeta del repo. |
| `dkms status` vacío o «added» | La compilación falló | Instala las cabeceras de tu kernel exacto (`uname -r`) y vuelve a instalar. |
| Sigue diciendo «Auriculares» sin nada conectado | Falso positivo del sensor | `./cambiar_modo_audio.sh` → opción 2. |
| Sonido solo tras reiniciar | Los módulos estaban en uso al instalar | Normal: el instalador pide reiniciar. |
| Sin sonido tras actualizar el kernel | Faltaban las cabeceras del kernel nuevo | Instálalas y ejecuta `sudo /usr/local/bin/check-cs8409-driver.sh`. |
| El módulo no carga: «Key was rejected by service» | Secure Boot activo con un módulo sin firmar | Desactiva Secure Boot o firma el módulo (MOK). |
| No aparece el perfil «Altavoces internos + HDMI» | WirePlumber no recargado | `systemctl --user restart pipewire wireplumber`. |
| Volumen muy alto en `hw:0,0` | Ese dispositivo no tiene control de volumen | Usa siempre la salida por defecto de PipeWire. |

## 15. Desinstalar

No hay desinstalador automático. Estos son los pasos manuales:

```bash
sudo dkms remove -m snd_hda_macbookpro/0.1 --all
sudo rm -rf /usr/src/snd_hda_macbookpro-0.1
sudo systemctl disable --now cs8409-audio-guard.service
sudo rm -f /etc/systemd/system/cs8409-audio-guard.service /usr/local/bin/check-cs8409-driver.sh
sudo rm -f /etc/modprobe.d/cs8409.conf
sudo rm -f /etc/wireplumber/wireplumber.conf.d/50-imac-audio.conf \
           /etc/alsa-card-profile/mixer/profile-sets/9999-custom.conf \
           /etc/alsa-card-profile/mixer/profile-sets/default.conf \
           /etc/alsa-card-profile/mixer/paths/hdmi-output-{0,1,2}.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/50-imac-audio.conf \
      ~/.config/alsa-card-profile/mixer/profile-sets/{9999-custom,default}.conf \
      ~/.config/alsa-card-profile/mixer/paths/hdmi-output-{0,1,2}.conf
sudo systemctl daemon-reload
sudo depmod -a
# Regenera el initramfs: dracut --force | update-initramfs -u | mkinitcpio -P
```

Después reinicia y volverá a cargarse el módulo `snd_hda_codec_cs8409` del kernel.

## 16. Limitaciones conocidas

- **Distribuciones inmutables no soportadas** (Fedora Silverblue/Kinoite, Bazzite, openSUSE Aeon, etc.): `/usr` es de solo lectura y los paquetes se instalan con `rpm-ostree`. La compilación DKMS de este instalador no funciona ahí tal cual.
- Los nombres de nodo de PipeWire asumen la controladora en **`0000:00:1f.3`**, que es la del iMac 2017. En otro hardware habría que adaptarlos.
- **Micrófono**: según el autor del driver, la grabación tiene un nivel muy bajo (igual que en macOS) y la integración del micrófono no está completa.
- **Gestión de energía**: el driver mantiene los amplificadores siempre encendidos. La suspensión no está probada.
- El sonido no será idéntico al de macOS, que aplica filtros digitales propios a tweeters y woofers.
- `force_speakers` lo añade este repo: no existe en el driver original ni en el módulo de NixOS generado.
- El instalador **no tiene modo simulación**: instala paquetes y escribe en `/etc` y `/usr/src` directamente.

## 17. Estructura del repositorio

```
imac-2017-linux-audio-cs8409/
├── instalar_audio_imac.sh        # Instalador universal con menú
├── cambiar_modo_audio.sh         # Selector automático / altavoces forzados
├── crear_lanzadores.sh           # Crea los accesos directos del escritorio
├── lanzadores/
│   ├── Instalador_Audio_Apple.desktop.in
│   └── Modo_Audio_Apple.desktop.in
├── parches/
│   └── imac-cs8409.patch         # Cambios respecto a davidjo/snd_hda_macbookpro
├── snd_hda_macbookpro_imac/      # Driver completo ya parcheado (lo usa el instalador)
│   ├── install.cirrus.driver.sh
│   ├── install.cirrus.driver.pre617.sh
│   ├── dkms.conf
│   ├── patch_cirrus/             # Código del codec CS8409 + soporte Apple
│   └── ...
├── LICENSE                       # GPL-2.0
└── README.md
```

## 18. Créditos y licencia

- **Driver original:** [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro). Todo el trabajo de ingeniería inversa del CS8409, el CS42L83 y los amplificadores de Apple es suyo.
- **Corrección para iMac 2017, parámetro `force_speakers`, instalador universal, selector de modo y configuración de PipeWire:** [@riqgonzalo-lgtm](https://github.com/riqgonzalo-lgtm).

Como el driver deriva de código **GPL-2.0**, todo el repositorio se distribuye bajo la [GNU General Public License v2](LICENSE).

> ⚠️ Este software modifica módulos del kernel y la configuración del sistema de sonido. Se ofrece **sin garantía**. Úsalo bajo tu responsabilidad.
