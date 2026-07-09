#!/bin/bash
# scripts/inventory.sh

###### VARIABLES ######
# Ruta absoluta al directorio raíz del proyecto (un nivel arriba del script)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TOFU_DIR="${PROJECT_ROOT}/opentofu"
HOSTS_FILE="${PROJECT_ROOT}/ansible/hosts"

NODE_IPS=$(cd "$TOFU_DIR" && tofu output -json node_ips | jq '.value // .')


###### LÓGICA ######

echo "[node_master]" > "$HOSTS_FILE"
echo "$NODE_IPS" | jq -r '
  to_entries[]
  | select(.key | test("master"))
  | "\(.key) ansible_host=\(.value) ansible_user=ubuntu"
' >> "$HOSTS_FILE"

echo "" >> "$HOSTS_FILE"
echo "[node_workers]" >> "$HOSTS_FILE"
echo "$NODE_IPS" | jq -r '
  to_entries[]
  | select(.key | test("worker"))
  | "\(.key) ansible_host=\(.value) ansible_user=ubuntu"
' >> "$HOSTS_FILE"

echo "[nfs_server]" >> "$HOSTS_FILE"
echo "$NODE_IPS" | jq -r '
  to_entries[]
  | select(.key | test("nfs"))
  | "\(.key) ansible_host=\(.value) ansible_user=ubuntu"
' >> "$HOSTS_FILE"

cat >> "$HOSTS_FILE" << 'EOF'

[k3s_cluster:children]
node_master
node_workers

[all:children]
node_master
node_workers
nfs_server
EOF

echo "Inventory generado:"
cat "$HOSTS_FILE"
