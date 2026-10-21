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

summary() {
  echo "$1" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

echo "=== 1. Instances déjà présentes dans le compte ==="
oci compute instance list --compartment-id "$OCI_TENANCY_OCID" --all \
  --query 'data[*].{nom:"display-name",etat:"lifecycle-state",forme:shape}' --output table

echo "=== 2. Domaine de disponibilité ==="
AD=$(oci iam availability-domain list --compartment-id "$OCI_TENANCY_OCID" --query 'data[0].name' --raw-output)
if [[ -z "$AD" ]]; then
  echo "::error title=Oracle::Impossible de lire le domaine de disponibilité (voir les logs)"
  summary "### ❌ Étape 2 : domaine de disponibilité introuvable"
  exit 0
fi
echo "AD: $AD"

echo "=== 3. Image Ubuntu ==="
IMAGE_ID=$(oci compute image list \
  --compartment-id "$OCI_TENANCY_OCID" \
  --operating-system "Canonical Ubuntu" \
  --shape "$SHAPE" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)
if [[ -z "$IMAGE_ID" ]]; then
  echo "::error title=Oracle::Aucune image Ubuntu trouvée pour ce shape"
  summary "### ❌ Étape 3 : image Ubuntu introuvable"
  exit 0
fi
echo "Image: $IMAGE_ID"

SSH_KEY_CLEAN=$(echo "$SSH_PUBLIC_KEY" | tr -d '\n\r')

echo "=== 4. Tentative de création ==="
output=$(oci compute instance launch \
  --compartment-id "$OCI_TENANCY_OCID" \
  --availability-domain "$AD" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
  --image-id "$IMAGE_ID" \
  --subnet-id "$OCI_SUBNET_ID" \
  --display-name "$INSTANCE_NAME" \
  --assign-public-ip true \
  --metadata "{\"ssh_authorized_keys\": \"$SSH_KEY_CLEAN\"}" \
  --wait-for-state RUNNING 2>&1)
status=$?

echo "----- Réponse complète d'Oracle -----"
echo "$output"
echo "-------------------------------------"

code=$(echo "$output" | grep -o '"code": *"[^"]*"' | head -1 | cut -d'"' -f4)
http=$(echo "$output" | grep -o '"status": *[0-9]*' | head -1 | grep -o '[0-9]*$')
msg=$(echo "$output" | grep -o '"message": *"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ $status -eq 0 ]]; then
  INSTANCE_ID=$(echo "$output" | grep -o '"id": *"ocid1.instance[^"]*"' | head -1 | cut -d'"' -f4)
  IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" \
    --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
  notify "✅ VPS Oracle créé ! IP publique : ${IP:-voir console Oracle}"
  summary "### ✅ VPS créé — IP : ${IP:-voir console Oracle}"
  echo "SUCCESS"
  exit 0
fi

if echo "$output" | grep -qi "Out of host capacity"; then
  label="CAPACITE_INSUFFISANTE"; level="notice"
elif [[ "${http:-}" == "429" ]] || echo "$output" | grep -qi "TooManyRequests"; then
  label="TROP_DE_REQUETES"; level="warning"
elif echo "$output" | grep -qi "LimitExceeded"; then
  label="LIMITE_DE_COMPTE_DEPASSEE"; level="error"
else
  label="AUTRE_ERREUR"; level="error"
fi

echo "::${level} title=Oracle - ${label}::code=${code:-?} http=${http:-?} message=${msg:-?}"
summary "### Résultat : ${label}"
summary "- Code Oracle : \`${code:-?}\`"
summary "- HTTP : \`${http:-?}\`"
summary "- Message : ${msg:-?}"

if [[ "$label" == "LIMITE_DE_COMPTE_DEPASSEE" || "$label" == "AUTRE_ERREUR" ]]; then
  notify "⚠️ Oracle : ${label} (code=${code:-?}, http=${http:-?}) ${msg:-?}"
fi
exit 0
