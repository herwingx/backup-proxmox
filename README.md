# 🔄 Proxmox Smart Backup

> **Sistema de respaldo híbrido e inteligente para Proxmox VE** — Backups automáticos locales, rotación inteligente y sincronización segura a Google Drive con notificaciones en tiempo real.

[![Proxmox](https://img.shields.io/badge/Proxmox-E57000?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Security](https://img.shields.io/badge/Security-Age%20Encryption-101010?style=flat-square&logo=letsencrypt&logoColor=white)](https://github.com/FiloSottile/age)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

<p align="center">
  <img src="https://raw.githubusercontent.com/herwingx/assets/main/proxmox-backup-banner.png" alt="Proxmox Smart Backup Architecture" width="800"/>
  <!-- Placeholder image, replace with actual screenshot/diagram if available -->
</p>

---

## ✨ Características

| Característica          | Descripción                                                                                             |
| :---------------------- | :------------------------------------------------------------------------------------------------------ |
| 💾 **Backup Local**      | Ejecución diaria de `vzdump` para VMs y Contenedores LXC con rotación configurable (Default: 3 copias). |
| ☁️ **Sync Híbrido**      | Estrategia inteligente: Configs se suben a diario, Backups pesados cada 3 días a Google Drive. Sistema *Stateful* para asegurar intervalos precisos. |
| 🛡️ **Tolerancia a Fallos**| `rclone` verifica integridad antes de limpiar. Manejo de señales (`traps`) para alertar sobre cancelaciones o cierres inesperados. |
| 🔐 **Zero Knowledge**    | Gestión de secretos segura usando `age` para encriptar tokens y credenciales en el repositorio.         |
| 📱 **Alertas Real-Time** | Notificaciones detalladas por Telegram al iniciar, completar o fallar un respaldo.                      |
| 🤖 **Automatización**    | Instalador interactivo que configura Cronjobs, Logrotate y dependencias automáticamente. Logs limpios (`cron` mode). |
| 📦 **Dependencias Auto** | Integración nativa con `dotfiles` para el manejo de `rclone` y credenciales de nube.                    |

---

## 🚀 Inicio Rápido

### Requisitos Previos

- **Proxmox VE** 7.x o superior.
- **Acceso Root** al servidor.
- **[dotfiles](https://github.com/herwingx/dotfiles)** ejecutado (Recomendado para instalar `age`, `rclone` y configurar `gdrive`).

### 1. Clonar el repositorio

```bash
cd /root/development
git clone https://github.com/herwingx/backup-proxmox.git
cd backup-proxmox
```

### 2. Configurar Secretos

Gestionamos las credenciales de forma segura. Copia la plantilla y configura tus tokens.

```bash
cp .env.example .env
nano .env
```

Variables principales (`.env`):
```env
TELEGRAM_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyZ"
TELEGRAM_CHAT_ID="987654321"
```

Encripta tus secretos para mantenerlos seguros (opcional pero recomendado):
```bash
./scripts/manage_secrets.sh encrypt
# Te pedirá una passphrase. ¡Guárdala bien!
```

### 3. Instalación Automática

El script instalará las herramientas en `/usr/local/bin` y configurará el Cronjob.

```bash
sudo ./install.sh
```

El asistente verificará:
- [x] Dependencias (`age`, `rclone`).
- [x] Configuración de Google Drive (`rclone config`).
- [x] Desencriptado de secretos (si usaste `manage_secrets`).
- [x] Prueba de conexión con Telegram.

---

## 🏗️ Arquitectura

### 🗺️ Panorama General

El sistema sigue un flujo de respaldo híbrido priorizando la velocidad local y la seguridad en la nube.

```mermaid
flowchart TD
    %% Defines Styles
    classDef server fill:#f9f9f9,stroke:#333,stroke-width:2px;
    classDef cloud fill:#e1f5fe,stroke:#0277bd,stroke-width:2px;
    classDef storage fill:#fff3e0,stroke:#ef6c00,stroke-width:2px;
    classDef bot fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5;

    subgraph Proxmox_Server [🖥️ Proxmox VE Server]
        direction TB
        VMs[📦 VMs & LXC]:::server
        VZDump[⚙️ VZDump Tool]:::server
        LocalStore[📂 /mnt/backups/dump]:::storage
        Script[📜 Smart Backup Script]:::server
        
        VMs -->|Snapshot Diario| VZDump
        VZDump -->|Genera .zst| LocalStore
        Script -.->|Controla| VZDump
    end

    subgraph Cloud [☁️ Nube]
        GDrive[Google Drive]:::cloud
    end

    Telegram[📱 Telegram Bot]:::bot

    LocalStore -->|"Sync Encriptado (rclone)"| GDrive
    Script -->|Notificación| Telegram

    Note[📝 Estrategia de Subida:<br/>- Configs: Diario<br/>- VMs: Cada 3 Días]
    Script -.- Note
```

### 🔄 Flujo de Ejecución

Detalle del proceso paso a paso ejecutado por el cronjob.

```mermaid
sequenceDiagram
    autonumber
    participant Cron as ⏰ Cronjob
    participant Script as 📜 Backup Script
    participant PVE as 🖥️ Proxmox VE
    participant Local as 📂 Disco Local
    participant Cloud as ☁️ Google Drive
    participant TG as 📱 Telegram

    Cron->>Script: Ejecuta (3:00 AM)
    Script->>TG: 🔔 Notificación de Inicio
    
    loop Por cada VM/LXC
        Script->>PVE: vzdump (Snapshot Mode)
        PVE-->>Local: Guardar archivo .zst
        Script->>Local: Rotar Backups (Mantener 3)
    end

    rect rgb(240, 248, 255)
    note right of Script: Sincronización Inteligente
    alt Solo Configs (Días 1, 2)
        Script->>Cloud: rclone copy (Configs)
    else Full Backup (Día 3)
        Script->>Cloud: rclone copy (VMs + Configs)
        Script->>Cloud: [Si copy = OK] rclone delete (Antiguos)
    end
    end

    Script->>TG: ✅ Reporte de Éxito
    
    opt Error Crítico / Cancelación (Trap)
        Script->>TG: ❌ Alerta de Fallo + Logs
    end
```

---

## 📦 Opciones de Despliegue

| Método         | Archivo Principal   | Uso Ideal                                                   |
| :------------- | :------------------ | :---------------------------------------------------------- |
| **Instalador** | `install.sh`        | **Producción**. Configura todo el entorno, logs y cronjobs. |
| **Manual**     | `scripts/backup.sh` | **Debug/Dev**. Ejecución directa para pruebas puntuales.    |

## 🔧 Comandos Útiles

```bash
# Ejecutar backup manualmente (Trigger inmediato)
proxmox-backup

# Ver logs en tiempo real
tail -f /var/log/proxmox-backup/backup-$(date +%F).log

# Editar configuración de entorno
nano /etc/proxmox-backup/config.env

# Gestionar secretos (Encriptar/Desencriptar)
./scripts/manage_secrets.sh help
```

## 📚 Documentación

| Documento                                                | Descripción                              |
| :------------------------------------------------------- | :--------------------------------------- |
| [`install.sh`](install.sh)                               | Script de instalación e idempotencia.    |
| [`scripts/backup.sh`](scripts/backup.sh)                 | Lógica principal de respaldo y rotación. |
| [`scripts/manage_secrets.sh`](scripts/manage_secrets.sh) | Utilidad para encriptar `.env` con age.  |

## 🛠️ Stack Tecnológico

**Core**
- **Bash**: Scripting avanzado con manejo de errores y señales.
- **Proxmox API / VZDump**: Herramientas nativas de virtualización.

**Seguridad & Almacenamiento**
- **Age**: Encriptación moderna para secretos.
- **Rclone**: Sincronización cloud agnóstica (Google Drive configurado por defecto).

**Notificaciones**
- **Telegram Bot API**: Alertas instantáneas.

## 🔒 Seguridad & Estabilidad

- ✅ **Tolerancia a Fallos en la Nube**: Las rutinas de limpieza en Google Drive (`rclone delete`) **nunca** se ejecutan si la subida previa de datos falla, evitando escenarios críticos donde se puedan perder los respaldos en la nube debido a cortes de conexión.
- ✅ **Ciclos de Nube Basados en Estado**: El script utiliza un archivo de control de estado local para determinar las frecuencias de subida, previniendo los fallos lógicos en los cálculos modulares durante los cambios de año bisiesto.
- ✅ **Protección contra Cierres (Traps)**: Si el script o el servidor se detienen repentinamente, el sistema interceptará las señales (`SIGINT`, `SIGTERM`, etc.) y enviará una alerta de emergencia garantizada por Telegram, lo cual eleva la confiabilidad.
- ✅ **Secretos Encriptados**: Las credenciales nunca se suben en texto plano al repositorio (uso de `.env.age`).
- ✅ **Permisos Restrictivos**: Los archivos de configuración en `/etc/proxmox-backup` tienen permisos `600` (solo root).
- ✅ **Logs Limpios y Rotativos**: Los logs en Cron ignoran los colores ANSI, facilitando la lectura. Además, `logrotate` mantiene un histórico de 7 días comprimido.

## 🤝 Contribuir

1. Fork del repositorio.
2. Crea una rama para tu feature: `git checkout -b feat/nueva-funcionalidad`.
3. Commit de tus cambios: `git commit -m 'feat: añade soporte para AWS S3'`.
4. Push a la rama: `git push origin feat/nueva-funcionalidad`.
5. Abre un Pull Request.

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver [LICENSE](LICENSE) para más detalles.
