

# OpenClaw One-Click Installer (CN + Global)

Por Douhao / Autor: Douhao  
Blog: https://www.youdiandou.store  
Tienda: https://key.apointfun.com
---

## Solo necesitas estos dos bloques

## ¿Qué ejecutar en Linux / macOS / WSL2?

```bash
curl -fsSL "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh" | PROFILE=auto bash
/usr/local/bin/openclaw onboard --install-daemon || openclaw onboard --install-daemon
openclaw --version
```

---

## ¿Qué ejecutar en Windows?

> Se recomienda ejecutar con **PowerShell como administrador**.

### PowerShell (recomendado)

```powershell
curl.exe -L "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1" -o .\openclaw-install-optimized.ps1
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto
openclaw onboard --install-daemon
openclaw --version
```

> Si aparece el mensaje de que `openclaw` no se encuentra, cierra y vuelve a abrir PowerShell antes de ejecutar.

### CMD (alternativa)

```cmd
powershell -ExecutionPolicy Bypass -Command "curl.exe -L https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1 -o openclaw-install-optimized.ps1 && powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto"
set "PATH=C:\Program Files\nodejs;%APPDATA%\npm;%PATH%"
"%APPDATA%\npm\openclaw.cmd" onboard --install-daemon
"%APPDATA%\npm\openclaw.cmd" --version
```

---

## Otros (consultar solo si es necesario)

### Red inestable / GitHub inaccesible

1) Usar jsDelivr:

```bash
# Linux/macOS/WSL2
curl -fsSL "https://cdn.jsdelivr.net/gh/AlexLing6er/openclaw-cn-installer@main/scripts/openclaw-install-optimized.sh" | PROFILE=auto bash
```

```powershell
# Windows
curl.exe -L "https://cdn.jsdelivr.net/gh/AlexLing6er/openclaw-cn-installer@main/scripts/openclaw-install-optimized.ps1" -o .\openclaw-install-optimized.ps1
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto
```

2) Si aún no funciona, usar el oficial:

```powershell
iwr -useb https://openclaw.ai/install.ps1 | iex
openclaw onboard --install-daemon
```

### Instalar plugins comunes (opcional)

```bash
# Feishu
openclaw plugins install @m1heng-clawd/feishu

# WeCom (WeChat Empresarial)
openclaw plugins install @wecom/wecom-openclaw-plugin

# DingTalk
openclaw plugins install @dingtalk-real-ai/dingtalk-connector
```

### Actualizar OpenClaw (recomendado)

#### Linux / macOS / WSL2
```bash
npm i -g openclaw
openclaw --version
```

#### Windows (PowerShell)
```powershell
npm i -g openclaw
openclaw --version
```

### Desinstalar OpenClaw

#### Linux / macOS / WSL2
```bash
npm uninstall -g openclaw
which openclaw || echo "openclaw removed"
```

#### Windows (PowerShell)
```powershell
npm uninstall -g openclaw
where openclaw
```

### Lógica de enrutamiento (automática)
- Con proxy: prioridad a los repositorios oficiales
- Sin proxy + fuera de China: prioridad a los repositorios oficiales
- Sin proxy + dentro de China: prioridad a los repositorios espejo

### Notas de compatibilidad con Linux
- El script detectará la versión de CMake; si es inferior a 3.19 (como la 3.16 común en Ubuntu 20.04), intentará actualizarla automáticamente para evitar fallos en la compilación de `node-llama-cpp`.
- El script instalará `git` automáticamente (para evitar el error `spawn git ENOENT` al descargar dependencias de npm).
- Después de la instalación, se corregirá automáticamente la variable PATH del prefijo de npm; si el shell no se ha actualizado, reinicia la sesión o ejecuta `source ~/.bashrc`.

### Notas de seguridad
- El objetivo del script es instalar OpenClaw; no modifica el firewall, SSH ni servicios críticos del sistema.
- Por defecto, se ejecutará una limpieza segura (`CLEANUP=1`): limpiará la caché de npm y la caché de paquetes del sistema para reducir el uso de disco y mantener la compatibilidad.
- Por defecto **no** se ejecutará `apt autoremove` (para evitar eliminar accidentalmente software o kernels no instalados por este script). Si deseas habilitarlo, establece `CLEANUP_AUTOREMOVE=1`.
- Para desactivar la limpieza: establece `CLEANUP=0`.
- Si solo deseas una vista previa sin realizar cambios (Linux/macOS/WSL2):

```bash
curl -fsSL "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh" | CHECK_ONLY=1 PROFILE=auto bash
```
