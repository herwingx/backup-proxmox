#!/bin/bash

# ==============================================================================
#  PROXMOX SMART BACKUP SYSTEM (FINAL VISUAL)
# ==============================================================================
#  Características:
#  1. Local: Mantiene últimos 3 backups (Gestionado por Proxmox).
#  2. Nube:  Sube cada 3 días. BORRA los viejos, dejando SOLO EL MÁS NUEVO.
#  3. Visual: Muestra progreso detallado para no parecer "congelado".
# ==============================================================================

# --- [1] CONFIGURACIÓN DE RUTAS Y DISCOS ---
BACKUP_DIR="/mnt/backups"
DATA_DIR="/mnt/data"
# ID exacto en Datacenter > Storage (Debe tener Retention: Keep Last=3)
PROXMOX_STORAGE_ID="backups-vms" 

# --- [2] CONFIGURACIÓN DE CLOUD (RCLONE) ---
RCLONE_REMOTE="gdrive" 
GDRIVE_ROOT="Server Backups"
GDRIVE_SYSTEM="Proxmox System"
GDRIVE_DATA="Proxmox Data"

# --- [3] CONFIGURACIÓN DE FRECUENCIA ---
CLOUD_SYNC_DAYS=3 

# --- [4] CONFIGURACIÓN DE TELEGRAM ---
CONFIG_FILE="/etc/proxmox-backup/config.env"
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""

# Cargar configuración si existe
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# --- VARIABLES DE SISTEMA ---
HOST_NAME=$(hostname)
DATE=$(date +%F)           # Ej: 2025-12-26 (Para logs y configs)
PVE_DATE=$(date +%Y_%m_%d) # Ej: 2025_12_26 (Formato OBLIGATORIO para VZDump)
DAY_OF_YEAR=$(date +%j)
START_TIME=$(date +%s)
BACKUP_STATUS="SUCCESS"
CLOUD_OK=true
ERROR_MSG=""

# --- ESTILOS Y COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' 

log_header() {
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${BLUE} ➤ $1 ${NC}"
    echo -e "${BLUE}============================================================${NC}"
}
log_info() { echo -e "${CYAN}ℹ INFO:${NC} $1"; }
log_step() { echo -e "${YELLOW}➜ $1${NC}"; }
log_success() { echo -e "${GREEN}✔ OK:${NC} $1"; }
log_error() { echo -e "${RED}✖ ERROR:${NC} $1"; BACKUP_STATUS="FAILED"; ERROR_MSG="$1"; }

# --- FUNCIÓN DE TELEGRAM ---
send_telegram() {
    local MESSAGE="$1"
    
    # Solo enviar si Telegram está configurado
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 0
    fi
    
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$MESSAGE" \
        -d parse_mode="Markdown" > /dev/null 2>&1
}
# ==============================================================================
#  INICIO DEL PROCESO
# ==============================================================================
clear
echo -e "${BLUE}"
cat << "EOF"
  ╔════════════════════════════════════════════════════════════════════╗
  ║                                                                    ║
  ║   ____  ____   _____  ____  __  _____  ____  __                    ║
  ║  |  _ \|  _ \ / _ \ \/ /  \/  |/ _ \ \/ /  | __ )  __ _  ___ ___   ║
  ║  | |_) | |_) | | | \  /| |\/| | | | \  /   |  _ \ / _` |/ __/ __|  ║
  ║  |  __/|  _ <| |_| /  \| |  | | |_| /  \   | |_) | (_| | (__\__ \  ║
  ║  |_|   |_| \_\\___/_/\_\_|  |_|\___/_/\_\  |____/ \__,_|\___|___/  ║
  ║                                                                    ║
EOF
echo -e "  ║              ${GREEN}★ SMART BACKUP SYSTEM v2.0 ★${BLUE}                      ║"
cat << "EOF"
  ╚════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo "Iniciando Protocolo de Respaldo para: $HOST_NAME"
echo "Fecha: $DATE | Día del año: $DAY_OF_YEAR"
echo "Estrategia Nube: Subir CADA $CLOUD_SYNC_DAYS DÍAS y mantener SOLO EL ÚLTIMO."

# ------------------------------------------------------------------------------
# FASE 1: BACKUP LOCAL (SIEMPRE SE EJECUTA)
# ------------------------------------------------------------------------------

# 1.1 RESPALDO DE CONFIGURACIÓN DEL HOST
log_header "[1/5] Respaldo de Configuración del Host (Local)"

CONFIG_DEST="$BACKUP_DIR/host-configs"
mkdir -p "$CONFIG_DEST"
FILES_TO_BACKUP="/etc/pve /etc/network/interfaces /etc/hosts /etc/fstab /etc/vzdump.conf /etc/samba/smb.conf /root/.ssh /root/.bashrc"

log_step "Comprimiendo archivos críticos..."
tar -czf "$CONFIG_DEST/host-config-$HOST_NAME-$DATE.tar.gz" $FILES_TO_BACKUP --warning=no-file-changed 2>/dev/null

if [ $? -eq 0 ]; then
    log_success "Configs guardadas: host-config-$HOST_NAME-$DATE.tar.gz"
else
    log_error "Error al comprimir configs del host."
fi

# 1.2 RESPALDO DE VMS Y LXC
log_header "[2/5] Ejecutando VZDump (VMs y Contenedores)"
log_info "Storage: $PROXMOX_STORAGE_ID | Compresión: ZSTD"
log_step "Iniciando copias de seguridad... (Esto puede tardar varios minutos)"
log_step "Por favor, espera a que termine cada máquina:"

# NOTA: Se eliminó '--quiet' para que veas el progreso en tiempo real
vzdump --all \
    --mode snapshot \
    --compress zstd \
    --storage "$PROXMOX_STORAGE_ID" 

if [ $? -eq 0 ]; then
    log_success "Todas las VMs han sido respaldadas localmente."
else
    log_error "VZDump reportó errores. Revisa la salida de arriba."
fi

# ------------------------------------------------------------------------------
# FASE 2: SINCRONIZACIÓN A LA NUBE (CONDICIONAL)
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# FASE 2: CLOUD CONFIGS (SIEMPRE SE EJECUTA)
# ------------------------------------------------------------------------------
log_header "[3/5] Respaldo de Configs a Nube (Diario)"

# 2.1 SUBIR CONFIGS
log_info "Destino: $GDRIVE_ROOT/$GDRIVE_SYSTEM/Configs"
if rclone copy "$CONFIG_DEST/host-config-$HOST_NAME-$DATE.tar.gz" \
    "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM/Configs" 2>&1; then
    log_success "Configs subidas a Drive."
else
    log_error "Error al subir configs a Drive."
    CLOUD_OK=false
fi

# 2.2 LIMPIEZA DE CONFIGS ANTIGUAS
log_step "Mantenimiento: Dejando solo la versión más reciente..."
rclone delete "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM/Configs" \
    --min-age 1d \
    --include "*.tar.gz" 2>&1

if [ $? -eq 0 ]; then
    log_success "Configs antiguas eliminadas."
else
    log_error "Error al limpiar configs antiguas."
fi


# ------------------------------------------------------------------------------
# FASE 3: CLOUD VMS & DATA (CADA 3 DÍAS)
# ------------------------------------------------------------------------------
log_header "[4/5] Verificación de Ciclo de Nube (VMs y Data)"

if [ $((DAY_OF_YEAR % CLOUD_SYNC_DAYS)) -eq 0 ]; then
    
    echo -e "${GREEN}★ HOY TOCA SINCRONIZACIÓN COMPLETA (VMs + DATA) ★${NC}"
    
    # ---------------------------------------------------------
    # 3.1 SUBIR VMS (Mantiene SOLO EL ÚLTIMO en Drive)
    # ---------------------------------------------------------
    log_info "Destino: $GDRIVE_ROOT/$GDRIVE_SYSTEM"
    log_step "Subiendo backups de VMs hoy ($PVE_DATE)..."
    
    # Subir Dumps
    if rclone copy "$BACKUP_DIR/dump" "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM" \
        --transfers=4 \
        --progress \
        --include "*$PVE_DATE*" \
        --include "*.log" 2>&1; then
        log_success "Backups de VMs subidos a Drive."
    else
        log_error "Error al subir backups a Drive."
        CLOUD_OK=false
    fi

    # Limpieza Agresiva de VMs
    log_header "LIMPIEZA DE VMS ANTIGUAS"
    log_step "Eliminando versiones antiguas en Drive..."
    
    rclone delete "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM" \
        --min-age 1d \
        --include "*.zst" \
        --include "*.log" \
        --include "*.vma.zst" \
        --include "*.tar.zst" \
        --verbose

    log_success "Historial de VMs limpiado (Solo queda el de hoy)."

    # ---------------------------------------------------------
    # 3.2 SUBIR DATOS
    # ---------------------------------------------------------
    log_header "[5/5] Sincronizando Datos (/mnt/data)"
    log_info "Destino: $GDRIVE_ROOT/$GDRIVE_DATA"
    log_step "Escaneando cambios..."

    if rclone sync "$DATA_DIR" "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_DATA" \
        --transfers=8 \
        --progress \
        --fast-list \
        --exclude ".Trash/**" \
        --exclude "lost+found/**" \
        --exclude ".DS_Store" 2>&1; then
        log_success "Datos sincronizados a Drive."
    else
        log_error "Error al sincronizar datos a Drive."
        CLOUD_OK=false
    fi

else
    echo -e "${YELLOW}SKIP: Hoy no toca subida masiva (VMs/Data).${NC}"
    echo "Se han subido las Configs, pero las VMs se mantienen localmente."
    echo "Próxima subida masiva: En $((CLOUD_SYNC_DAYS - (DAY_OF_YEAR % CLOUD_SYNC_DAYS))) día(s)."
fi

# ==============================================================================
#  RESUMEN FINAL
# ==============================================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$(($ELAPSED / 60))
ELAPSED_SEC=$(($ELAPSED % 60))

echo -e "\n${BLUE}============================================================${NC}"
echo -e "${GREEN} PROCESO COMPLETADO EN ${ELAPSED_MIN} MIN Y ${ELAPSED_SEC} SEG.${NC}"
echo -e "${BLUE}============================================================${NC}"

# --- NOTIFICACIÓN POR TELEGRAM ---
if [ "$BACKUP_STATUS" == "SUCCESS" ]; then
    CLOUD_STATUS=""
    # Lógica de Estado de Nube
    if [ "$CLOUD_OK" = true ]; then
        if [ $((DAY_OF_YEAR % CLOUD_SYNC_DAYS)) -eq 0 ]; then
            CLOUD_STATUS="☁️ Drive: ✅ Configs + VMs (Completo)"
        else
            NEXT_CLOUD=$((CLOUD_SYNC_DAYS - (DAY_OF_YEAR % CLOUD_SYNC_DAYS)))
            CLOUD_STATUS="☁️ Drive: ✅ Solo Configs
⏳ VMs: En ${NEXT_CLOUD} día(s)"
        fi
    else
        CLOUD_STATUS="☁️ Drive: ❌ Fallo en subida"
    fi

    TELEGRAM_MSG="✅ *Backup Completado*

🖥️ Host: \`$HOST_NAME\`
📅 Fecha: $DATE
⏱️ Duración: ${ELAPSED_MIN}m ${ELAPSED_SEC}s

📦 Local: Guardado
$CLOUD_STATUS

_Proxmox Smart Backup System_"

else
    TELEGRAM_MSG="❌ *Backup Fallido*

🖥️ Host: \`$HOST_NAME\`
📅 Fecha: $DATE
⏱️ Duración: ${ELAPSED_MIN}m ${ELAPSED_SEC}s

⚠️ Error: $ERROR_MSG

_Revisa los logs en /var/log/proxmox-backup/_"
fi

send_telegram "$TELEGRAM_MSG"
