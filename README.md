# 🔄 Proxmox Smart Backup

> **Sistema de respaldo híbrido para Proxmox VE** — Backups automáticos locales y sincronización inteligente a Google Drive con notificaciones por Telegram.

[![Proxmox](https://img.shields.io/badge/Proxmox-E57000?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Shell](https://img.shields.io/badge/Shell-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

---

## ✨ Características

| Característica         | Descripción                                       |
| :--------------------- | :------------------------------------------------ |
| 💾 **Backup Local**     | VZDump diario de VMs/LXC con rotación de 3 copias |
| ☁️ **Sync Híbrido**     | Configs diarias / VMs cada 3 días a Google Drive  |
| 📱 **Notificaciones**   | Alertas por Telegram al completar o fallar        |
| 🔐 **Secretos Seguros** | Credenciales encriptadas con age                  |
| ⏰ **Automatizado**     | Cronjob configurable (default: 3:00 AM)           |
| 📋 **Logs**             | Registro diario con rotación automática           |

---

## 🚀 Inicio Rápido

### Requisitos

- Proxmox VE 7.x o superior
- **[dotfiles](https://github.com/herwingx/dotfiles)** ejecutado previamente (instala `age`, `rclone` y configura Google Drive)

### 1. Preparar el servidor (dotfiles)

```bash
# En el servidor Proxmox, primero ejecutar dotfiles
git clone https://github.com/herwingx/dotfiles.git
cd dotfiles
./install.sh
# Seleccionar opción 6 (Paquetes) → instala age y rclone
# Seleccionar opción 16 (Configurar rclone) → configura Google Drive
```

### 2. Clonar este repositorio

```bash
git clone https://github.com/herwingx/backup-proxmox.git
cd backup-proxmox
```

### 3. Configurar secretos de Telegram

```bash
# Copiar plantilla
cp .env.example .env

# Editar con tus credenciales de Telegram
nano .env
```

Variables a configurar (`.env`):
```env
# Telegram (solo se necesitan estas, rclone viene de dotfiles)
TELEGRAM_TOKEN="tu_token_de_botfather"
TELEGRAM_CHAT_ID="tu_chat_id"
```

```bash
# Encriptar secretos
./manage_secrets.sh encrypt
# Ingresa tu passphrase (recuérdala para la instalación)
```

### 4. Instalar

```bash
./install.sh
```

El instalador:
- ✅ Verifica que `age` y `rclone` estén instalados (desde dotfiles)
- ✅ Verifica que `rclone` tenga configurado `gdrive` (desde dotfiles)
- ✅ Desencripta los secretos de Telegram del repo
- ✅ Instala el script en `/usr/local/bin/`
- ✅ Configura el cronjob
- ✅ Envía notificación de prueba a Telegram

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PROXMOX VE SERVER                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐ │
│  │   VMs/LXC   │───▶│   VZDump     │───▶│  /mnt/backups (local)  │ │
│  └─────────────┘    └──────────────┘    └───────────┬────────────┘ │
│                                                     │              │
│                                          Cada 3 días│              │
│                                                     ▼              │
│                                         ┌───────────────────────┐  │
│                                         │       rclone          │  │
│                                         └───────────┬───────────┘  │
│                                                     │              │
└─────────────────────────────────────────────────────┼──────────────┘
                                                      │
                                                      ▼
                                          ┌───────────────────────┐
                                          │    Google Drive       │
                                          │  "Server Backups/"    │
                                          └───────────────────────┘
```

---

## 📁 Estructura de Archivos

```
backup-proxmox/
├── .env.age            # 🔐 Secretos encriptados (seguro para Git)
├── .env.example        # 📄 Plantilla de configuración
├── .gitignore
├── backups-vms.sh      # 📦 Script principal de backup
├── install.sh          # 🚀 Instalador automático
├── manage_secrets.sh   # 🔑 Gestión de secretos con age
├── README.md
└── docs/
```

### Archivos en el servidor (post-instalación)

```
/usr/local/bin/backups-vms.sh     # Script de backup
/etc/proxmox-backup/config.env    # Configuración (permisos 600)
/root/.config/rclone/rclone.conf  # Config de rclone
/var/log/proxmox-backup/          # Logs diarios
```

---

## 🔐 Gestión de Secretos

Los secretos se encriptan con [age](https://github.com/FiloSottile/age) usando passphrase:

| Comando                       | Descripción                     |
| :---------------------------- | :------------------------------ |
| `./manage_secrets.sh encrypt` | Encripta `.env` → `.env.age`    |
| `./manage_secrets.sh decrypt` | Desencripta `.env.age` → `.env` |
| `./manage_secrets.sh edit`    | Edita y re-encripta             |

---

## 📱 Configurar Telegram

1. Busca **@BotFather** en Telegram
2. Envía `/newbot` y sigue las instrucciones
3. Copia el **token** que te da
4. Busca **@userinfobot** y envía cualquier mensaje
5. Copia tu **Chat ID**

---

## ☁️ Configurar Google Drive

En tu PC local (no en el servidor):

```bash
# Instalar rclone si no lo tienes
# Windows: winget install Rclone.Rclone
# Mac: brew install rclone
# Linux: apt install rclone

# Autorizar Google Drive
rclone authorize "drive"
```

Se abrirá el navegador. Autoriza y copia el JSON que aparezca:

```json
{"access_token":"ya29.xxx","token_type":"Bearer","refresh_token":"1//xxx","expiry":"..."}
```

Pega ese JSON en tu `.env` como `RCLONE_TOKEN`.

---

## 🔧 Comandos Útiles

```bash
# Ejecutar backup manualmente
/usr/local/bin/backups-vms.sh

# Ver cronjobs
crontab -l

# Ver logs de hoy
tail -f /var/log/proxmox-backup/backup-$(date +%F).log

# Editar configuración
nano /etc/proxmox-backup/config.env

# Reinstalar (actualiza scripts y hora)
cd /tmp/backup-proxmox && ./install.sh
```

---

## 📊 Estrategia de Retención

| Ubicación / Tipo    | Frecuencia      | Retención en Nube   |
| :------------------ | :-------------- | :------------------ |
| **Local** (Todo)    | Diario          | Últimos 3 (Proxmox) |
| **Nube** (Configs)  | **Diario**      | Solo última versión |
| **Nube** (VMs/Data) | **Cada 3 días** | Solo última versión |

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver [LICENSE](LICENSE) para más detalles.
