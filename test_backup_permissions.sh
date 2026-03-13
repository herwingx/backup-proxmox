#!/bin/bash

TEST_DIR="/tmp/backup_test"
CONFIG_DEST="$TEST_DIR/host-configs"
MOCK_FILE="$TEST_DIR/mock_config.conf"
HOST_NAME="test-host"
DATE="2023-01-01"

# Setup
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
echo "sensitive mock data" > "$MOCK_FILE"

# The logic from backup.sh
mkdir -p "$CONFIG_DEST"
chmod 700 "$CONFIG_DEST"
FILES_TO_BACKUP="$MOCK_FILE"

(umask 077 && tar -czf "$CONFIG_DEST/host-config-$HOST_NAME-$DATE.tar.gz" $FILES_TO_BACKUP --warning=no-file-changed 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "Archive created successfully"
else
    echo "Archive creation failed"
fi

# Verification
ls -ld "$CONFIG_DEST"
ls -l "$CONFIG_DEST/host-config-$HOST_NAME-$DATE.tar.gz"
