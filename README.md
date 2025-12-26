# 🛡️ Proxmox Hybrid Backup System

> **Sistema Inteligente de Respaldos para Proxmox VE** — Automatización completa con estrategia híbrida: Local Diario (Retención 3) + Nube cada 3 días (Solo última versión).

[![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE%208.x-E57000?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Rclone](https://img.shields.io/badge/Rclone-Cloud%20Sync-3492FF?style=flat-square&logo=rclone&logoColor=white)](https://rclone.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

<p align="center">
  <img src="docs/preview.png" alt="Proxmox Backup Preview" width="800"/>
</p>

---

## ✨ Características

| Característica             | Descripción                                                                       |
| :------------------------- | :-------------------------------------------------------------------------------- |
| 🖥️ **Backup de VMs/LXC**    | Respaldo automático de todas las máquinas virtuales y contenedores con VZDump     |
| 📁 **Configs del Host**     | Compresión de archivos críticos: `/etc/pve`, interfaces de red, fstab, samba, SSH |
| ☁️ **Sync a Google Drive**  | Sincronización programada cada N días usando Rclone                               |
| 🔄 **Rotación Inteligente** | Local: últimos 3 backups / Nube: solo el más reciente                             |
| 🎨 **Interfaz Visual**      | Progreso detallado con colores y estados claros                                   |
| ⏱️ **Cron Ready**           | Diseñado para ejecución automática via crontab                                    |

---

## 🏗️ Arquitectura de Hardware

El sistema depende de una estructura de discos específica. Es vital mantener este orden para que los scripts funcionen.

| Disco             | Ruta de Montaje | Sistema de Archivos | Función                                             |
| :---------------- | :-------------- | :------------------ | :-------------------------------------------------- |
| **sda** (SSD)     | `/` (LVM)       | ext4/LVM            | Sistema Operativo Proxmox y Discos Virtuales de VMs |
| **sdb** (HDD 1TB) | `/mnt/data`     | ext4                | Datos persistentes (Samba, Nextcloud, Docker vols)  |
| **sdc** (HDD 1TB) | `/mnt/backups`  | ext4                | Almacenamiento temporal de Backups (VZDump)         |

### Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────┐
│                    PROXMOX VE HOST                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   VM 100    │    │   VM 101    │    │  LXC 200    │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         └──────────────────┼──────────────────┘             │
│                            ▼                                │
│                    ┌───────────────┐                        │
│                    │   VZDump      │                        │
│                    │  (snapshot)   │                        │
│                    └───────┬───────┘                        │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              /mnt/backups (LOCAL)                    │   │
│  │  ├── dump/ (VMs .vma.zst, LXC .tar.zst)             │   │
│  │  └── host-configs/ (host-config-*.tar.gz)           │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │ Cada 3 días                    │
│                            ▼                                │
│                    ┌───────────────┐                        │
│                    │    Rclone     │                        │
│                    └───────┬───────┘                        │
└────────────────────────────┼────────────────────────────────┘
                             ▼
              ┌──────────────────────────────────┐
              │       GOOGLE DRIVE               │
              │  Server Backups/                 │
              │  ├── Proxmox System/ (backups)   │
              │  └── Proxmox Data/ (sync data)   │
              └──────────────────────────────────┘
```

---

## 🚀 Inicio Rápido

### Requisitos

- **Proxmox VE 7.x / 8.x**
- **Rclone** configurado con acceso a Google Drive
- **Storage** configurado en Proxmox con `Retention: Keep Last = 3`

### 1. Clonar el repositorio

```bash
git clone https://github.com/herwingx/backup-proxmox.git
cd backup-proxmox
```

### 2. Copiar script al sistema

```bash
cp backups-vms.sh /usr/local/bin/
chmod +x /usr/local/bin/backups-vms.sh
```

### 3. Configurar variables

Edita las variables al inicio del script:

```bash
# --- [1] CONFIGURACIÓN DE RUTAS Y DISCOS ---
BACKUP_DIR="/mnt/backups"          # Directorio de backups locales
DATA_DIR="/mnt/data"               # Directorio de datos a sincronizar
PROXMOX_STORAGE_ID="backups-vms"   # ID del storage en Proxmox

# --- [2] CONFIGURACIÓN DE CLOUD (RCLONE) ---
RCLONE_REMOTE="backup_proxmox"     # Nombre del remote en rclone
GDRIVE_ROOT="Server Backups"       # Carpeta raíz en Google Drive

# --- [3] CONFIGURACIÓN DE FRECUENCIA ---
CLOUD_SYNC_DAYS=3                  # Subir a la nube cada N días
```

### 4. Automatizar con Cron

```bash
# Editar crontab del root
sudo crontab -e

# Ejecutar diariamente a las 02:00 AM
0 2 * * * /usr/local/bin/backups-vms.sh >> /var/log/proxmox-backup.log 2>&1
```

---

## ⚙️ Configuración Inicial (Bare Metal)

Si estás reinstalando el servidor desde cero, sigue estos pasos en orden.

### A. Montaje de Discos (Fstab)

Proxmox no monta automáticamente discos secundarios tras una reinstalación.

```bash
# 1. Crear directorios
mkdir -p /mnt/data /mnt/backups

# 2. Identificar UUIDs de los discos
blkid
# Copia los UUID de tus discos de 1TB

# 3. Editar /etc/fstab
nano /etc/fstab
```

Agregar al final de `/etc/fstab`:

```ini
# Montaje Datos
UUID="TU-UUID-DE-SDB" /mnt/data ext4 defaults 0 2
# Montaje Backups
UUID="TU-UUID-DE-SDC" /mnt/backups ext4 defaults 0 2
```

```bash
# 4. Montar todo
mount -a
```

### B. Configuración de Rclone

```bash
# Instalar
apt install rclone -y

# Configurar remote
rclone config
# Name: backup_proxmox (Debe coincidir con el script)
# Storage: Google Drive
# Auth: Seguir pasos de autorización

# Verificar acceso
rclone lsd backup_proxmox:
```

### C. Configuración de Proxmox Storage

Para que `vzdump` funcione, Proxmox debe conocer el disco de backups:

1. Ir a **Web UI > Datacenter > Storage > Add > Directory**
2. Configurar:
   - **ID:** `backups-vms` ⚠️ (Nombre exacto)
   - **Directory:** `/mnt/backups`
   - **Content:** `VZDump backup file`
   - **Retention:** `Keep Last = 3`

---

## 📦 Estrategia de Rotación

| Ubicación                  | Retención            | Gestión                        |
| :------------------------- | :------------------- | :----------------------------- |
| **Local** (`/mnt/backups`) | Últimos 3 backups    | Proxmox Storage (Keep Last=3)  |
| **Nube** (Google Drive)    | Solo el más reciente | Script elimina backups > 1 día |

### Lógica del Script

| Frecuencia      | Acción                                                                                                                        |
| :-------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| **Diariamente** | Backup local de todas las VMs y LXC en `/mnt/backups`. Proxmox borra automáticamente los más viejos de 3 días                 |
| **Cada 3 días** | Detecta la fecha, sube a Google Drive SOLO los backups de HOY, luego borra todo lo que tenga más de 24 horas (`--min-age 1d`) |

---

## 🆘 Disaster Recovery

### Caso A: Restaurar un archivo o VM (Fallo leve)

Si borraste algo por error y el disco local `/mnt/backups` funciona:

1. Ir a **Proxmox Web UI > Storage `backups-vms`**
2. Seleccionar el Backup > Click **Restore**

### Caso B: Fallo de Disco Local (Fallo medio)

Si `/mnt/backups` murió, hay que traer la copia de la nube:

```bash
# Bajar backup de sistema
rclone copy "backup_proxmox:Server Backups/Proxmox System" /var/lib/vz/dump

# Restaurar VM (Ej. ID 105)
qmrestore /var/lib/vz/dump/vzdump-qemu-105-xxxx.zst 105

# Restaurar LXC (Ej. ID 200)
pct restore 200 /var/lib/vz/dump/vzdump-lxc-200-xxxx.tar.zst
```

### Caso C: Muerte Total del Servidor (Catastrófico)

El disco `sda` murió. Tienes una instalación limpia de Proxmox:

```bash
# 1. Montar discos sdb y sdc (Ver Sección Configuración Inicial A)
mkdir -p /mnt/data /mnt/backups
# Editar /etc/fstab con UUIDs
mount -a

# 2. Instalar y configurar Rclone (Ver Sección Configuración Inicial B)
apt install rclone -y
rclone config

# 3. Restaurar Configuración del Host
# Si el disco local de backups también falló, descargar de la nube:
rclone copy "backup_proxmox:Server Backups/Proxmox System/Configs" /tmp/configs/

# Descomprimir
tar -xzvf /tmp/configs/host-config-*.tar.gz -C /tmp/restore/

# Restaurar archivos críticos
cp /tmp/restore/etc/network/interfaces /etc/network/
cp /tmp/restore/etc/hosts /etc/
cp /tmp/restore/etc/fstab /etc/

# Reiniciar red
systemctl restart networking

# 4. Restaurar VMs desde Drive
rclone copy "backup_proxmox:Server Backups/Proxmox System" /var/lib/vz/dump
qmrestore /var/lib/vz/dump/vzdump-qemu-*.zst <VMID>
```

---

## 📂 Estructura en Google Drive

```
Server Backups/
├── Proxmox System/           # Backups de VMs (.zst) y Configs (.tar.gz)
│   ├── vzdump-qemu-100-*.vma.zst
│   ├── vzdump-lxc-200-*.tar.zst
│   └── Configs/
│       └── host-config-pve-*.tar.gz
└── Proxmox Data/             # Espejo exacto de /mnt/data
    └── (Sincronización incremental de Samba/Nextcloud)
```

> 📘 **Nota:** La carpeta `Proxmox System` solo contiene la versión del último ciclo de subida. Los archivos antiguos se eliminan automáticamente.

---

## 🔧 Archivos Respaldados del Host

| Archivo                   | Descripción                        |
| :------------------------ | :--------------------------------- |
| `/etc/pve`                | Configuración del cluster Proxmox  |
| `/etc/network/interfaces` | Configuración de red               |
| `/etc/hosts`              | Hosts del sistema                  |
| `/etc/fstab`              | Puntos de montaje                  |
| `/etc/vzdump.conf`        | Configuración de VZDump            |
| `/etc/samba/smb.conf`     | Configuración de Samba (si existe) |
| `/root/.ssh`              | Claves SSH del root                |
| `/root/.bashrc`           | Aliases y configuración de bash    |

---

## 🐛 Troubleshooting

### VZDump falla con errores de storage

```bash
# Verificar que el storage existe y tiene espacio
pvesm status
df -h /mnt/backups
```

### Rclone no conecta con Google Drive

```bash
# Verificar configuración
rclone listremotes
rclone lsd backup_proxmox:

# Re-autenticar si el token expiró
rclone config reconnect backup_proxmox:
```

### El script no sube a la nube

```bash
# Verificar el día del año y la frecuencia
echo "Día del año: $(date +%j)"
echo "Frecuencia: cada 3 días"
echo "¿Toca hoy? $(($(date +%j) % 3))"  # 0 = sí toca
```

---

## 🛠️ Stack Tecnológico

**Core**
- [Bash](https://www.gnu.org/software/bash/): Shell scripting
- [VZDump](https://pve.proxmox.com/wiki/Backup_and_Restore): Herramienta nativa de Proxmox

**Cloud**
- [Rclone](https://rclone.org/): Sincronización con Google Drive

**Compresión**
- [ZSTD](https://facebook.github.io/zstd/): Compresión rápida y eficiente

---

## 🔒 Seguridad

- ✅ El script debe ejecutarse como **root** para acceder a VZDump
- ✅ Las credenciales de Rclone se almacenan en `~/.config/rclone/rclone.conf`
- ✅ Los backups en la nube pueden cifrarse usando `rclone crypt`
- ✅ Nunca se suben archivos `.env` o secretos al repositorio

---

## 🤝 Contribuir

1. Fork del repositorio
2. Crear rama: `git checkout -b feat/nueva-feature`
3. Commit: `git commit -m "feat: descripción"`
4. Push: `git push origin feat/nueva-feature`
5. Crear Pull Request

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver [LICENSE](LICENSE) para más detalles.

---

<p align="center">
  <sub>Hecho con ❤️ para la comunidad de Proxmox Homelab</sub>
</p>
