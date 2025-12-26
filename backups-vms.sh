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
RCLONE_REMOTE="backup_proxmox" 
GDRIVE_ROOT="Server Backups"
GDRIVE_SYSTEM="Proxmox System"
GDRIVE_DATA="Proxmox Data"

# --- [3] CONFIGURACIÓN DE FRECUENCIA ---
CLOUD_SYNC_DAYS=3 

# --- VARIABLES DE SISTEMA ---
HOST_NAME=$(hostname)
DATE=$(date +%F)           # Ej: 2025-12-26 (Para logs y configs)
PVE_DATE=$(date +%Y_%m_%d) # Ej: 2025_12_26 (Formato OBLIGATORIO para VZDump)
DAY_OF_YEAR=$(date +%j)
START_TIME=$(date +%s)

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
log_error() { echo -e "${RED}✖ ERROR:${NC} $1"; }

# ==============================================================================
#  INICIO DEL PROCESO
# ==============================================================================
clear
echo -e "${BLUE}"
echo "   ___  ___  _____  __  __ __  __  ___  _  __ "
echo "  | _ \| _ \/ _ \ \/ / |  \/  |/ _ \| |/ / "
echo "  |  _/|   / (_) >  <  | |\/| | (_) |   <  "
echo "  |_|  |_|_\\\___/_/\_\ |_|  |_|\___/|_|\_\ "
echo -e "${NC}"
echo "Iniciando Protocolo de Respaldo para: $HOST_NAME"
echo "Fecha: $DATE | Día del año: $DAY_OF_YEAR"
echo "Estrategia Nube: Subir CADA $CLOUD_SYNC_DAYS DÍAS y mantener SOLO EL ÚLTIMO."

# ------------------------------------------------------------------------------
# FASE 1: BACKUP LOCAL (SIEMPRE SE EJECUTA)
# ------------------------------------------------------------------------------

# 1.1 RESPALDO DE CONFIGURACIÓN DEL HOST
log_header "[1/4] Respaldo de Configuración del Host (Local)"

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
log_header "[2/4] Ejecutando VZDump (VMs y Contenedores)"
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
log_header "[3/4] Verificación de Ciclo de Nube"

if [ $((DAY_OF_YEAR % CLOUD_SYNC_DAYS)) -eq 0 ]; then
    
    echo -e "${GREEN}★ HOY TOCA SINCRONIZACIÓN A GOOGLE DRIVE ★${NC}"
    
    # ---------------------------------------------------------
    # 2.1 SUBIR SISTEMA (Mantiene SOLO EL ÚLTIMO en Drive)
    # ---------------------------------------------------------
    log_info "Destino: $GDRIVE_ROOT/$GDRIVE_SYSTEM"
    log_step "Subiendo SOLO los backups generados HOY ($PVE_DATE)..."
    
    # PASO A: Subir el backup de HOY (Copy = No borrar todavía)
    # --progress mostrará la velocidad y porcentaje
    rclone copy "$BACKUP_DIR/dump" "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM" \
        --transfers=4 \
        --progress \
        --include "*$PVE_DATE*" \
        --include "*.log"

    # Subir config del host de hoy
    rclone copy "$CONFIG_DEST/host-config-$HOST_NAME-$DATE.tar.gz" \
        "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM/Configs"
    
    log_success "Carga de archivos completada."

    # PASO B: Limpieza Agresiva (Solo dejar el más nuevo)
    # Borra todo lo que tenga más de 1 día (24 horas) de antigüedad
    log_header "LIMPIEZA DE NUBE"
    log_step "Eliminando versiones antiguas en Drive para liberar espacio..."
    
    # Limpiar Dumps de VMs viejos
    rclone delete "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM" \
        --min-age 1d \
        --include "*.zst" \
        --include "*.log" \
        --include "*.vma.zst" \
        --include "*.tar.zst" \
        --verbose

    # Limpiar Configs viejas
    rclone delete "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_SYSTEM/Configs" \
        --min-age 1d \
        --include "*.tar.gz"

    log_success "Historial antiguo eliminado. Solo queda la versión de hoy."

    # ---------------------------------------------------------
    # 2.2 SUBIR DATOS
    # ---------------------------------------------------------
    log_header "[4/4] Sincronizando Datos (/mnt/data)"
    log_info "Destino: $GDRIVE_ROOT/$GDRIVE_DATA"
    log_step "Escaneando cambios en archivos..."

    rclone sync "$DATA_DIR" "$RCLONE_REMOTE:$GDRIVE_ROOT/$GDRIVE_DATA" \
        --transfers=8 \
        --progress \
        --fast-list \
        --exclude ".Trash/**" \
        --exclude "lost+found/**" \
        --exclude ".DS_Store"

    log_success "Datos sincronizados."

else
    echo -e "${YELLOW}SKIP: Hoy no toca subida a la nube.${NC}"
    echo "El backup hoy solo queda en disco local (Rotación de 3 días)."
    echo "Próxima subida a Drive: En $((CLOUD_SYNC_DAYS - (DAY_OF_YEAR % CLOUD_SYNC_DAYS))) día(s)."
fi

# ==============================================================================
#  RESUMEN FINAL
# ==============================================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo -e "\n${BLUE}============================================================${NC}"
echo -e "${GREEN} PROCESO COMPLETADO EN $(($ELAPSED / 60)) MIN Y $(($ELAPSED % 60)) SEG.${NC}"
echo -e "${BLUE}============================================================${NC}"
