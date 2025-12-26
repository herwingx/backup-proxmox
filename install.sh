#!/bin/bash

# ==============================================================================
#  INSTALADOR DE PROXMOX SMART BACKUP SYSTEM
# ==============================================================================
#  Uso: curl -sSL <url>/install.sh | bash
#  O:   ./install.sh
# ==============================================================================

set -e

# --- CONFIGURACIÓN POR DEFECTO ---
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="backups-vms.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
CONFIG_DIR="/etc/proxmox-backup"
CONFIG_FILE="$CONFIG_DIR/config.env"
LOG_DIR="/var/log/proxmox-backup"

# --- COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✔${NC} $1"; }
log_error() { echo -e "${RED}✖${NC} $1"; exit 1; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# ==============================================================================
#  BANNER
# ==============================================================================
clear
echo -e "${BLUE}"
cat << "EOF"
  ╔════════════════════════════════════════════════════════════════════╗
  ║        PROXMOX SMART BACKUP - INSTALADOR v2.0                      ║
  ╚════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ==============================================================================
#  VERIFICACIONES
# ==============================================================================

# Verificar si es root
if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root. Usa: sudo ./install.sh"
fi

# Verificar si es Proxmox
if ! command -v vzdump &> /dev/null; then
    log_error "vzdump no encontrado. ¿Estás en un servidor Proxmox?"
fi

# Verificar rclone
if ! command -v rclone &> /dev/null; then
    log_warn "rclone no está instalado. La sincronización a la nube no funcionará."
    log_info "Instala rclone con: apt install rclone && rclone config"
fi

# Verificar age (necesario para desencriptar secretos)
if ! command -v age &> /dev/null; then
    log_warn "age no está instalado. Es necesario para desencriptar los secretos."
    read -p "  ¿Deseas instalar age ahora? (S/n): " INSTALL_AGE
    
    if [[ ! $INSTALL_AGE =~ ^[Nn]$ ]]; then
        log_info "Instalando age..."
        apt update && apt install -y age
        
        if command -v age &> /dev/null; then
            log_success "age instalado correctamente."
        else
            log_error "No se pudo instalar age. Instala manualmente: apt install age"
        fi
    else
        log_warn "Sin age, deberás configurar Telegram manualmente."
    fi
fi

log_success "Verificaciones completadas."
echo ""

# ==============================================================================
#  DETECTAR INSTALACIÓN EXISTENTE
# ==============================================================================
EXISTING_CRON=""
CURRENT_HOUR="3"
CURRENT_MIN="0"

if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
    log_warn "Se detectó una instalación existente."
    EXISTING_CRON=$(crontab -l 2>/dev/null | grep "$SCRIPT_PATH")
    
    # Extraer hora actual del cron
    CURRENT_MIN=$(echo "$EXISTING_CRON" | awk '{print $1}')
    CURRENT_HOUR=$(echo "$EXISTING_CRON" | awk '{print $2}')
    
    echo -e "  Cronjob actual: ${CYAN}$EXISTING_CRON${NC}"
    echo ""
fi

# ==============================================================================
#  CONFIGURACIÓN INTERACTIVA
# ==============================================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW} CONFIGURACIÓN DEL BACKUP${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# --- Hora del backup ---
echo -e "${CYAN}¿A qué hora quieres ejecutar el backup diario?${NC}"
echo -e "  Formato: HH:MM (24 horas)"
echo -e "  Actual/Default: ${GREEN}$CURRENT_HOUR:$(printf '%02d' $CURRENT_MIN)${NC}"
echo ""
read -p "  Nueva hora (Enter para mantener actual): " NEW_TIME

if [ -n "$NEW_TIME" ]; then
    # Validar formato HH:MM
    if [[ $NEW_TIME =~ ^([0-9]|0[0-9]|1[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        CURRENT_HOUR="${BASH_REMATCH[1]}"
        CURRENT_MIN="${BASH_REMATCH[2]}"
        log_success "Hora configurada: $CURRENT_HOUR:$CURRENT_MIN"
    else
        log_warn "Formato inválido. Usando hora por defecto: $CURRENT_HOUR:$(printf '%02d' $CURRENT_MIN)"
    fi
fi

# --- Configuración desde archivo encriptado ---
echo ""
echo -e "${CYAN}Cargando secretos encriptados...${NC}"

TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
RCLONE_TOKEN=""
SCRIPT_DIR="$(dirname "$0")"
ENCRYPTED_FILE="$SCRIPT_DIR/.env.age"
LOCAL_CONFIG="$SCRIPT_DIR/.env"

# Prioridad: 1) Config existente en servidor, 2) Archivo .age, 3) Manual
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    if [ -n "$TELEGRAM_TOKEN" ]; then
        log_success "Configuración existente encontrada en servidor."
        echo -e "  Token: ${CYAN}${TELEGRAM_TOKEN:0:20}...${NC}"
        echo -e "  Chat ID: ${CYAN}$TELEGRAM_CHAT_ID${NC}"
    fi

elif [ -f "$ENCRYPTED_FILE" ]; then
    log_info "Archivo encriptado encontrado: config.env.age"
    
    if command -v age &> /dev/null; then
        log_info "Desencriptando con age..."
        
        if age -d -o "$LOCAL_CONFIG" "$ENCRYPTED_FILE" 2>/dev/null; then
            source "$LOCAL_CONFIG"
            rm -f "$LOCAL_CONFIG"  # Limpiar archivo temporal
            log_success "Secretos cargados correctamente."
        else
            log_warn "No se pudo desencriptar. ¿Tienes la clave privada en ~/.config/age/keys.txt?"
        fi
    else
        log_warn "age no instalado. Instala con: apt install age"
    fi

else
    log_warn "No se encontró .env.age"
    log_info "Configuración manual de Telegram:"
    
    read -p "  ¿Habilitar Telegram? (s/N): " ENABLE_TELEGRAM
    
    if [[ $ENABLE_TELEGRAM =~ ^[Ss]$ ]]; then
        echo ""
        read -p "  Bot Token: " TELEGRAM_TOKEN
        read -p "  Chat ID: " TELEGRAM_CHAT_ID
        
        if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            log_success "Telegram configurado correctamente."
        else
            log_warn "Configuración incompleta. Telegram deshabilitado."
            TELEGRAM_TOKEN=""
            TELEGRAM_CHAT_ID=""
        fi
    fi
fi

# ==============================================================================
#  INSTALACIÓN
# ==============================================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW} INSTALANDO...${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Crear directorios
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"
log_success "Directorios creados: $LOG_DIR, $CONFIG_DIR"

# Guardar configuración
cat > "$CONFIG_FILE" << EOF
# Proxmox Smart Backup - Configuración
# Generado: $(date)

# Telegram Notifications
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF

chmod 600 "$CONFIG_FILE"
log_success "Configuración guardada: $CONFIG_FILE"

# --- CONFIGURAR RCLONE ---
if [ -n "$RCLONE_TOKEN" ]; then
    log_info "Configurando rclone para Google Drive..."
    
    RCLONE_CONFIG_DIR="/root/.config/rclone"
    RCLONE_CONFIG_FILE="$RCLONE_CONFIG_DIR/rclone.conf"
    
    mkdir -p "$RCLONE_CONFIG_DIR"
    
    # Usar printf para preservar las comillas del JSON
    printf '%s\n' "[gdrive]" \
        "type = drive" \
        "scope = drive" \
        "token = ${RCLONE_TOKEN}" \
        "team_drive = " > "$RCLONE_CONFIG_FILE"

    chmod 600 "$RCLONE_CONFIG_FILE"
    log_success "rclone.conf generado: $RCLONE_CONFIG_FILE"
    
    # Verificar conexión
    log_info "Verificando conexión a Google Drive..."
    if rclone lsd gdrive: --max-depth 1 &>/dev/null; then
        log_success "Conexión a Google Drive verificada."
    else
        log_warn "No se pudo verificar la conexión. Revisa el token."
    fi
else
    log_warn "RCLONE_TOKEN no encontrado. Configura rclone manualmente: rclone config"
fi

# Copiar script
SCRIPT_SOURCE="$(dirname "$0")/$SCRIPT_NAME"

if [ -f "$SCRIPT_SOURCE" ]; then
    cp "$SCRIPT_SOURCE" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    log_success "Script instalado: $SCRIPT_PATH"
else
    log_error "No se encontró $SCRIPT_NAME en el directorio actual."
fi

# ==============================================================================
#  CONFIGURACIÓN DEL CRONJOB
# ==============================================================================
log_info "Configurando cronjob..."

# Eliminar cronjob anterior si existe
if [ -n "$EXISTING_CRON" ]; then
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | grep -v "Proxmox Smart Backup") | crontab -
    log_info "Cronjob anterior eliminado."
fi

# Crear nuevo cronjob
CRON_SCHEDULE="$CURRENT_MIN $CURRENT_HOUR * * *"
CRON_JOB="$CRON_SCHEDULE $SCRIPT_PATH >> $LOG_DIR/backup-\$(date +\%F).log 2>&1"
CRON_COMMENT="# Proxmox Smart Backup System - Backup diario"

(crontab -l 2>/dev/null; echo "$CRON_COMMENT"; echo "$CRON_JOB") | crontab -

log_success "Cronjob configurado: Diario a las $CURRENT_HOUR:$(printf '%02d' $CURRENT_MIN)"

# ==============================================================================
#  LOGROTATE
# ==============================================================================
cat > /etc/logrotate.d/proxmox-backup << 'LOGROTATE'
/var/log/proxmox-backup/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE

log_success "Logrotate configurado (mantiene 7 días de logs)."

# ==============================================================================
#  TEST DE TELEGRAM
# ==============================================================================
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    echo ""
    log_info "Enviando mensaje de prueba a Telegram..."
    
    MESSAGE="✅ *Proxmox Smart Backup Instalado*

🖥️ Host: $(hostname)
📅 Fecha: $(date '+%Y-%m-%d %H:%M')
⏰ Backup programado: Diario a las $CURRENT_HOUR:$(printf '%02d' $CURRENT_MIN)

_Instalación completada correctamente._"

    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$MESSAGE" \
        -d parse_mode="Markdown" 2>&1)
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        log_success "Mensaje de prueba enviado correctamente."
    else
        log_warn "Error al enviar mensaje. Verifica el token y chat ID."
        echo "  Respuesta: $RESPONSE"
    fi
fi

# ==============================================================================
#  RESUMEN FINAL
# ==============================================================================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN} ✔ INSTALACIÓN COMPLETADA ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}Script:${NC}       $SCRIPT_PATH"
echo -e "  ${BLUE}Config:${NC}       $CONFIG_FILE"
echo -e "  ${BLUE}Logs:${NC}         $LOG_DIR/"
echo -e "  ${BLUE}Cronjob:${NC}      Diario a las $CURRENT_HOUR:$(printf '%02d' $CURRENT_MIN)"
echo -e "  ${BLUE}Telegram:${NC}     $([ -n "$TELEGRAM_TOKEN" ] && echo "✔ Habilitado" || echo "✖ Deshabilitado")"
echo ""
echo -e "  ${YELLOW}Comandos útiles:${NC}"
echo -e "    • Ejecutar ahora:        ${GREEN}$SCRIPT_PATH${NC}"
echo -e "    • Ver cronjobs:          ${GREEN}crontab -l${NC}"
echo -e "    • Editar config:         ${GREEN}nano $CONFIG_FILE${NC}"
echo -e "    • Ver logs:              ${GREEN}tail -f $LOG_DIR/backup-\$(date +%F).log${NC}"
echo -e "    • Reinstalar:            ${GREEN}./install.sh${NC}"
echo ""

# Preguntar si ejecutar ahora
read -p "¿Deseas ejecutar el backup ahora? (s/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Ss]$ ]]; then
    log_info "Ejecutando backup..."
    "$SCRIPT_PATH"
else
    log_info "Listo. El próximo backup será a las $CURRENT_HOUR:$(printf '%02d' $CURRENT_MIN)"
fi
