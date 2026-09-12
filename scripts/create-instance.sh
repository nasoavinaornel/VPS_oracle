name: Create Oracle VPS

on:
  schedule:
    - cron: "*/5 * * * *"
  workflow_dispatch:

permissions:
  actions: write

jobs:
  try-create:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install OCI CLI
        run: pip install oci-cli

      - name: Configure OCI CLI
        run: |
          mkdir -p ~/.oci
          echo "${OCI_PRIVATE_KEY}" > ~/.oci/key.pem
          chmod 600 ~/.oci/key.pem
          cat > ~/.oci/config <<EOF
          [DEFAULT]
          user=${OCI_USER_OCID}
          fingerprint=${OCI_FINGERPRINT}
          tenancy=${OCI_TENANCY_OCID}
          region=${OCI_REGION}
          key_file=~/.oci/key.pem
          EOF
        env:
          OCI_PRIVATE_KEY: ${{ secrets.OCI_PRIVATE_KEY }}
          OCI_USER_OCID: ${{ secrets.OCI_USER_OCID }}
          OCI_FINGERPRINT: ${{ secrets.OCI_FINGERPRINT }}
          OCI_TENANCY_OCID: ${{ secrets.OCI_TENANCY_OCID }}
          OCI_REGION: ${{ secrets.OCI_REGION }}

      - name: Try create instance
        id: attempt
        run: bash scripts/create-instance.sh | tee result.log
        env:
          OCI_TENANCY_OCID: ${{ secrets.OCI_TENANCY_OCID }}
          OCI_SUBNET_ID: ${{ secrets.OCI_SUBNET_ID }}
          SSH_PUBLIC_KEY: ${{ secrets.SSH_PUBLIC_KEY }}
          TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
          TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}

      - name: Disable workflow if success
        if: contains(steps.attempt.outputs.stdout, 'SUCCESS') || success()
        run: |
          if grep -q "SUCCESS" result.log; then
            curl -s -X PUT \
              -H "Authorization: Bearer ${{ secrets.GITHUB_TOKEN }}" \
              -H "Accept: application/vnd.github+json" \
              "https://api.github.com/repos/${{ github.repository }}/actions/workflows/create-vps.yml/disable"
          fi
