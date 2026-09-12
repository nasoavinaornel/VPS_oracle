#!/usr/bin/env bash
set -uo pipefail

INSTANCE_NAME="mon-vps-free"
SHAPE="VM.Standard.A1.Flex"
OCPUS=2
MEMORY_GB=12

notify() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" -d text="$1" > /dev/null
}

echo "Recherche du domaine de disponibilité..."
AD=$(oci iam availability-domain list --compartment-id "$OCI_TENANCY_OCID" --query 'data[0].name' --raw-output)

echo "Recherche de l'image Debian 12 la plus récente..."
IMAGE_ID=$(oci compute image list \
  --compartment-id "$OCI_TENANCY_OCID" \
  --operating-system "Debian" \
  --operating-system-version "12" \
  --shape "$SHAPE" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)

echo "Tentative de création de l'instance..."
output=$(oci compute instance launch \
  --compartment-id "$OCI_TENANCY_OCID" \
  --availability-domain "$AD" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
  --image-id "$IMAGE_ID" \
  --subnet-id "$OCI_SUBNET_ID" \
  --display-name "$INSTANCE_NAME" \
  --assign-public-ip true \
  --metadata "{\"ssh_authorized_keys\": \"$SSH_PUBLIC_KEY\"}" \
  --wait-for-state RUNNING 2>&1)
status=$?

if [[ $status -eq 0 ]]; then
  IP=$(echo "$output" | grep -o '"publicIp": *"[^"]*"' | head -1 | cut -d'"' -f4 || echo "voir console Oracle")
  notify "✅ VPS Oracle créé avec succès ! IP publique: ${IP}"
  echo "SUCCESS"
elif echo "$output" | grep -qi "Out of host capacity"; then
  echo "Pas de capacité disponible, on réessaiera dans 5 min."
  echo "RETRY"
else
  echo "$output"
  notify "⚠️ Erreur inattendue lors de la création du VPS, vérifie GitHub Actions."
  echo "ERROR"
fi
