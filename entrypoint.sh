#!/bin/sh

RUN_AS_USER=${RUN_AS_USER:-sds}
WORK_DIR=${WORK_DIR:-/sds}
NETWORK_PORT=${NETWORK_PORT:-18081}
PPD_BIN=/usr/bin/ppd


if [ ! -d "$WORK_DIR/config" ]
then
  if [ -z "${MNEMONIC_PHRASE}" ]; then
      echo "Error: The environment variable MNEMONIC_PHRASE is not set." >&2
      exit 1
  fi
  
  if [ -z "${NETWORK_ADDRESS}" ]; then
      echo "Error: The environment variable NETWORK_ADDRESS is not set." >&2
      exit 1
  fi

  echo "[entrypoint] Init SDS resource node..."
  printf "\n\n3\n" | $PPD_BIN config --create-p2p-key --home $WORK_DIR
  printf "\n" | $PPD_BIN config accounts --mnemonic "$MNEMONIC_PHRASE" --home $WORK_DIR

  echo "[entrypoint] Set network_address to '$NETWORK_ADDRESS'"
  sed -i '/\[node\.connectivity\]/,/^\[/ {/network_address/ s/= .*/= '\'$NETWORK_ADDRESS\''/}' $WORK_DIR/config/config.toml

  echo "[entrypoint] Set network_port to $NETWORK_PORT"
  sed -i '/\[node\.connectivity\]/,/^\[/ {/network_port/ s/= .*/= '\'$NETWORK_PORT\''/}' $WORK_DIR/config/config.toml

  RPC_NAMESPACES=${RPC_NAMESPACES:-user,owner}
  echo "[entrypoint] Set rpc_namespaces to '$RPC_NAMESPACES'"
  sed -i "s/rpc_namespaces = 'user'/rpc_namespaces = '$RPC_NAMESPACES'/" $WORK_DIR/config/config.toml
fi

chown -R $RUN_AS_USER $WORK_DIR

# Setup cron job for auto-upload monitoring
if [ -f /usr/local/bin/monitor-and-upload.sh ]; then
  echo "[entrypoint] Setting up auto-upload cron job..."
  
  # Create cron job that runs every 5 minutes
  # Pass environment variables to the script
  # Redirect to Docker's stdout/stderr so logs appear in docker logs
  echo "*/5 * * * * RPC_PASSWORD='$RPC_PASSWORD' RPC_URL='$RPC_URL' /usr/local/bin/monitor-and-upload.sh >> /dev/stdout 2>&1" > /tmp/crontab.tmp
  
  # Install crontab for the user
  crontab -u $RUN_AS_USER /tmp/crontab.tmp
  rm /tmp/crontab.tmp
  
  # Start cron daemon
  cron
  
  echo "[entrypoint] Auto-upload cron job configured (runs every 5 minutes)"
fi

echo "[entrypoint] Starting as user: $RUN_AS_USER"
exec gosu "$RUN_AS_USER" "$@"
