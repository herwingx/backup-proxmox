#!/bin/bash

# Test for decrypt_secrets in scripts/manage_secrets.sh

set -e

# Path to the script under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/scripts/manage_secrets.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================"
echo " Running tests for decrypt_secrets"
echo "======================================"

# Setup test environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Export variables expected by the script BEFORE sourcing
export SCRIPT_DIR="$TEST_DIR"
export SECRET_FILE="$TEST_DIR/.env"
export ENCRYPTED_FILE="$TEST_DIR/.env.age"

# Create a dummy encrypted file
echo "dummy_encrypted_content" > "$ENCRYPTED_FILE"

# Mock age command
age() {
    echo "mock_age called with args: $*" >> "$TEST_DIR/age_calls.log"
    # Create the output file if -o flag is present
    local output_file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o) output_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if [[ -n "$output_file" ]]; then
        echo "dummy_decrypted_content" > "$output_file"
    fi
}
export -f age

# Source the script
source "$TARGET_SCRIPT"

# The script overwrites our exported variables, so we overwrite them back
SECRET_FILE="$TEST_DIR/.env"
ENCRYPTED_FILE="$TEST_DIR/.env.age"

# Create a dummy encrypted file (just in case)
echo "dummy_encrypted_content" > "$ENCRYPTED_FILE"

# Override log_error to capture the error without exiting
export ERROR_MSG=""
log_error() {
    echo -e "${RED}mock log_error:${NC} $1"
    export ERROR_MSG="$1"
}
export -f log_error

# --- Scenario 1: Happy Path ---
echo "--- Running Scenario 1: Happy Path ---"
decrypt_secrets

# Assertions for Scenario 1
if [[ -f "$SECRET_FILE" ]]; then
    echo -e "${GREEN}PASS${NC}: Decrypted file created."
else
    echo -e "${RED}FAIL${NC}: Decrypted file not created."
    exit 1
fi

if [[ "$(cat "$SECRET_FILE")" == "dummy_decrypted_content" ]]; then
    echo -e "${GREEN}PASS${NC}: Decrypted file has correct content."
else
    echo -e "${RED}FAIL${NC}: Decrypted file has wrong content."
    exit 1
fi

if grep -q "\-d -o $SECRET_FILE $ENCRYPTED_FILE" "$TEST_DIR/age_calls.log"; then
    echo -e "${GREEN}PASS${NC}: age called with correct arguments."
else
    echo -e "${RED}FAIL${NC}: age not called correctly."
    cat "$TEST_DIR/age_calls.log"
    exit 1
fi

file_perms=$(stat -c "%a" "$SECRET_FILE")
if [[ "$file_perms" == "600" ]]; then
    echo -e "${GREEN}PASS${NC}: Decrypted file has correct permissions (600)."
else
    echo -e "${RED}FAIL${NC}: Decrypted file has wrong permissions: $file_perms"
    exit 1
fi

# --- Scenario 2: Error Case (Missing Encrypted File) ---
echo "--- Running Scenario 2: Missing Encrypted File ---"
rm -f "$ENCRYPTED_FILE"
export ERROR_MSG=""

decrypt_secrets

# Assertions for Scenario 2
if [[ "$ERROR_MSG" == "No existe $ENCRYPTED_FILE" ]]; then
    echo -e "${GREEN}PASS${NC}: Correct error message logged when file is missing."
else
    echo -e "${RED}FAIL${NC}: Expected error message not found. Got: $ERROR_MSG"
    exit 1
fi

echo "======================================"
echo -e "${GREEN}All decrypt_secrets tests passed.${NC}"
echo "======================================"
