#!/usr/bin/env bash

set -e -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

ROOT_DIR="$(pwd -P)"

LNDAB_LAUNCHED_BY_SYSTEMD=${LNDAB_LAUNCHED_BY_SYSTEMD}
if [[ -n "$LNDAB_LAUNCHED_BY_SYSTEMD" ]]; then
  echo "sourcing '$ROOT_DIR/.envrc' because being launched as a systemd service..."
  . ./.envrc
fi

LND_HOME=${LND_HOME:-$HOME/.lnd}
LND_NETWORK=${LND_NETWORK:-mainnet}
LND_CHAIN=${LND_CHAIN:-bitcoin}
LNDAB_CHANNEL_BACKUP_PATH=${LNDAB_CHANNEL_BACKUP_PATH:-"$LND_HOME/data/chain/$LND_CHAIN/$LND_NETWORK/channel.backup"}
LNDAB_BACKUP_SCRIPT=${LNDAB_BACKUP_SCRIPT:-$ROOT_DIR/backup-via-s3.sh}
LNDAB_FILE_CREATION_POLLING_TIME=${LNDAB_FILE_CREATION_POLLING_TIME:-1}

if [[ ! -e "$LNDAB_BACKUP_SCRIPT" ]]; then
  echo "the backup script does not exist at '$LNDAB_BACKUP_SCRIPT'"
  exit 1
fi

# ---------------------------------------------------------------------------------------------------------------------------

wait_for_changes() {
  inotifywait -e close_write "$LNDAB_CHANNEL_BACKUP_PATH"
}

wait_for_creation() {
  until [[ -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; do
    sleep ${LNDAB_FILE_CREATION_POLLING_TIME}
  done
}

generate_backup_label() {
  local stamp=$(date -d "today" +"%Y%m%d_%H%M_%S")
  echo "${LND_CHAIN}_${LND_NETWORK}_${stamp}_channel.backup"
}

perform_backup() {
  local new_label=$(generate_backup_label)
  ${LNDAB_BACKUP_SCRIPT} "$new_label" ${LNDAB_CHANNEL_BACKUP_PATH}
}

# ---------------------------------------------------------------------------------------------------------------------------

function finish {
  echo "finished monitoring '$LNDAB_CHANNEL_BACKUP_PATH'"
}
trap finish EXIT

echo
echo "======================================================================================================================="
echo
echo "monitoring '$LNDAB_CHANNEL_BACKUP_PATH'"

if [[ ! -e "$LNDAB_CHANNEL_BACKUP_PATH" ]]; then
  echo "waiting for '$LNDAB_CHANNEL_BACKUP_PATH' to be created..."
  wait_for_creation
  perform_backup
fi

while wait_for_changes; do
  perform_backup
done