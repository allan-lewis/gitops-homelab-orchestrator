#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   l3-converge.sh <os> <ansible group>
#
# Examples:
#   l3-converge.sh arch arch_devops
#   l3-converge.sh ubuntu ubuntu_core
#
# Expects:
#   - Inventory: ansible/inventory/
#   - Playbook : ansible/playbooks/l3-converge-<os>.yml
#   - Optional env vars:
#       L3_TAGS  : comma-separated Ansible tags (e.g., "base,desktop")
#       L3_LIMIT : Ansible --limit expression (e.g., "host1" or "host1:host2")

OS="${1:?Usage: $0 <os> <ansible group>}"
GROUP="${2:?Usage: $0 <os> <ansible group>}"

INVENTORY="ansible/inventory/"
PLAYBOOK="ansible/playbooks/l3-converge-${OS}.yml"

if [[ ! -d "${INVENTORY}" ]]; then
  echo "Inventory not found at: ${INVENTORY}" >&2
  exit 1
fi

if [[ ! -f "${PLAYBOOK}" ]]; then
  echo "Converge playbook not found at: ${PLAYBOOK}" >&2
  echo "Expected per-OS converge playbook: l3-converge-${OS}.yml" >&2
  exit 1
fi

L3_TAGS="${L3_TAGS:-}"
L3_LIMIT="${L3_LIMIT:-}"

# Build extra args safely under `set -u`
extra=()
extra+=(-e converge_group="${GROUP}")
if [[ -n "${L3_TAGS}" ]]; then
  extra+=(--tags "${L3_TAGS}")
fi
if [[ -n "${L3_LIMIT}" ]]; then
  extra+=(--limit "${L3_LIMIT}")
fi

echo "=== [L3] Converging hosts (os=${OS}) ==="
echo "Inventory : ${INVENTORY}"
echo "Group:      ${GROUP}"
echo "Playbook  : ${PLAYBOOK}"
echo "L3_TAGS   : ${L3_TAGS:-<none>}"
echo "L3_LIMIT  : ${L3_LIMIT:-<none>}"

if ((${#extra[@]})); then
  ansible-playbook \
    -i "${INVENTORY}" \
    "${PLAYBOOK}" \
    "${extra[@]}"
else
  ansible-playbook \
    -i "${INVENTORY}" \
    "${PLAYBOOK}"
fi

echo "=== [L3] Converge complete ==="
