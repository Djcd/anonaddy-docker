#!/usr/bin/with-contenv bash
# shellcheck shell=bash
set -e

. $(dirname $0)/00-env

if [ "$ANONADDY_DKIM_ENABLE" != "true" ]; then
  echo "INFO: DKIM disabled"
  exit 0
fi

echo "DKIM Enabled - Initialize"

if [ -f "$DKIM_PRIVATE_KEY" ]; then
  echo "INFO: $DKIM_PRIVATE_KEY already exists"
  exit 0
fi

mkdir -p /data/dkim
echo "generating private key and storing in ${DKIM_PRIVATE_KEY}"
echo "generating DNS TXT record with public key and storing it in /data/dkim/${ANONADDY_DOMAIN}.${ANONADDY_DKIM_SELECTOR}.txt"
echo ""
rspamadm dkim_keygen -s 'default' -b 2048 -d "${ANONADDY_DOMAIN}" -k "${DKIM_PRIVATE_KEY}" | tee -a "/data/dkim/${ANONADDY_DOMAIN}.${ANONADDY_DKIM_SELECTOR}.txt"
chown -R anonaddy. /data/dkim
