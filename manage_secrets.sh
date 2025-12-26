#!/bin/bash

# ==============================================================================
#  GESTOR DE SECRETOS - PROXMOX BACKUP
# ==============================================================================
#  Uso:
#    ./manage_secrets.sh encrypt    # Encripta config.env → config.env.age
#    ./manage_secrets.sh decrypt    # Desencripta config.env.age → config.env
#    ./manage_secrets.sh edit       # Edita y re-encripta
# ==============================================================================

set -e

# --- CONFIGURACIÓN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRET_FILE="$SCRIPT_DIR/.env"
ENCRYPTED_FILE="$SCRIPT_DIR/.env.age"

# --- COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✔${NC} $1"; }
log_error() { echo -e "${RED}✖${NC} $1"; exit 1; }
log_info() { echo -e "${YELLOW}ℹ${NC} $1"; }

# --- VERIFICAR AGE ---
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "age no está instalado. Instala con: apt install age"
    fi
}

# ==============================================================================
#  FUNCIONES
# ==============================================================================

encrypt_secrets() {
    check_age
    
    if [ ! -f "$SECRET_FILE" ]; then
        log_error "No existe $SECRET_FILE. Crea el archivo primero."
    fi
    
    log_info "Encriptando $SECRET_FILE..."
    log_info "Se te pedirá una passphrase para encriptar."
    
    age -p -o "$ENCRYPTED_FILE" "$SECRET_FILE"
    
    log_success "Archivo encriptado: $ENCRYPTED_FILE"
    log_info "Seguro para subir a GitHub."
    
    # Preguntar si eliminar el original
    read -p "¿Eliminar el archivo sin encriptar? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        rm "$SECRET_FILE"
        log_success "Archivo original eliminado."
    fi
}

decrypt_secrets() {
    check_age
    
    if [ ! -f "$ENCRYPTED_FILE" ]; then
        log_error "No existe $ENCRYPTED_FILE"
    fi
    
    log_info "Desencriptando $ENCRYPTED_FILE..."
    log_info "Necesitas tu clave privada de age (~/.config/age/keys.txt)"
    
    age -d -o "$SECRET_FILE" "$ENCRYPTED_FILE"
    chmod 600 "$SECRET_FILE"
    
    log_success "Archivo desencriptado: $SECRET_FILE"
}

edit_secrets() {
    # Desencriptar temporalmente
    if [ -f "$ENCRYPTED_FILE" ] && [ ! -f "$SECRET_FILE" ]; then
        decrypt_secrets
    fi
    
    if [ ! -f "$SECRET_FILE" ]; then
        log_info "Creando nuevo archivo de secretos..."
        cp "$SCRIPT_DIR/.env.example" "$SECRET_FILE"
    fi
    
    # Editar
    ${EDITOR:-nano} "$SECRET_FILE"
    
    # Re-encriptar
    encrypt_secrets
}

# ==============================================================================
#  MAIN
# ==============================================================================

case "${1:-}" in
    encrypt)
        encrypt_secrets
        ;;
    decrypt)
        decrypt_secrets
        ;;
    edit)
        edit_secrets
        ;;
    *)
        echo "Uso: $0 {encrypt|decrypt|edit}"
        echo ""
        echo "Comandos:"
        echo "  encrypt  - Encripta config.env → config.env.age"
        echo "  decrypt  - Desencripta config.env.age → config.env"
        echo "  edit     - Edita y re-encripta los secretos"
        exit 1
        ;;
esac
