# Historial de versiones

## [1.1.0] — 2026-10-24

### Corregido
- **Ya no informa éxito si la compilación falla.** Se comprueba el código de salida de `install.cirrus.driver.sh` y que exista `snd-hda-codec-cs8409.ko*`. Si algo falla, se muestra «LA INSTALACIÓN NO SE COMPLETÓ», no se tocan los módulos de audio y se vuelve al menú.
- **No cierra programas a la fuerza.** Se eliminaron `killall -9 pipewire`, `fuser -k -9 /dev/snd/*` y `rmmod -f`. PipeWire se detiene con `systemctl --user` y, si otro programa usa el audio, se muestra su nombre y se pide reiniciar.
- **Volumen de prueba al 40 %** (antes al 100 %), y se quitó el respaldo `aplay -D plughw:0,0`, que no tiene control de volumen.
- **El servicio guardián ya no puede trabar el arranque.** Ahora se ejecuta en segundo plano tras tener red (`After=network-online.target`, `WantedBy=multi-user.target`) con prioridad baja, no se ejecuta si faltan las cabeceras y nunca falla. Al reinstalar se borra el enlace antiguo de `basic.target`.
- El guardián detecta también módulos `.ko.zst` en `updates/dkms`.
- `cambiar_modo_audio.sh` guarda el modo aunque `cs8409.conf` exista sin la línea `force_speakers`, y avisa si el módulo cargado no tiene el parche.
- Reinstalar ya no vuelve a poner `force_speakers=0` si habías elegido forzar los altavoces.
- Las órdenes de audio del usuario se ejecutan en su sesión real (`runuser` con `XDG_RUNTIME_DIR`). Con `su -` podían fallar sin avisar.
- El modo de respaldo (descarga del driver original) aplica `parches/imac-cs8409.patch` en vez de un `sed` que rompía los `exit 1`.
- Se detectan el usuario real y su carpeta personal; antes el usuario `imac` y la ruta `/home/imac` estaban fijos.
- El módulo de NixOS ya no fija `force_speakers`, porque el driver original no tiene ese parámetro.

### Añadido
- Opción **8) Desinstalar el controlador** en el menú.
- Aviso de duración («5–20 minutos») antes de descargar y compilar, y registro completo en `/var/log/instalar_audio_imac.log`.
- Comprobación previa de las cabeceras del kernel.
- Detección de sistemas inmutables (rpm-ostree) con un mensaje claro.
- Diagnóstico ampliado: archivo del módulo, presencia del parche, DKMS y estado del guardián.
- El menú vuelve a mostrarse después de cada opción.
- Pruebas sin hardware: `bash pruebas/test_scripts.sh` (19 comprobaciones).
- `crear_lanzadores.sh` y plantillas `.desktop` portables.

## [1.0.0] — 2026-10-24
- Primera versión publicada: driver parcheado para iMac 2017 (tip-sense sin invertir + `force_speakers`), instalador universal RPM/DEB/Arch/NixOS, selector de modo y perfil PipeWire altavoces + HDMI.
