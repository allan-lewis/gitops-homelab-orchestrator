#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   l3-converge.sh <os> <persona>
#
# Examples:
#   l3-converge.sh arch devops
#   l3-converge.sh arch tinker
#
# Expects:
#   - Inventory generated at: artifacts/<os>/<persona>/hosts.ini
#   - Optional env vars:
#       L3_TAGS  : comma-separated Ansible tags (e.g., "base,desktop")
#       L3_LIMIT : Ansible --limit expression (e.g., "blaine" or "blaine:patricia")

OS="${1:?Usage: $0 <os> <persona>}"
PERSONA="${2:?Usage: $0 <os> <persona>}"

INVENTORY="artifacts/${OS}/${PERSONA}/hosts.ini"
PLAYBOOK="ansible/playbooks/l3-converge-${OS}.yml"

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Inventory not found at: ${INVENTORY}" >&2
  echo "Did you run the corresponding l3-${OS}-${PERSONA}-inventory target first?" >&2
  exit 1
fi

L3_TAGS="${L3_TAGS:-}"
L3_LIMIT="${L3_LIMIT:-}"

extra=()

if [[ -n "${L3_TAGS}" ]]; then
  extra+=(--tags "${L3_TAGS}")
fi

if [[ -n "${L3_LIMIT}" ]]; then
  extra+=(--limit "${L3_LIMIT}")
fi

echo "=== [L3] Converging hosts (os=${OS}, persona=${PERSONA}) ==="
echo "Inventory : ${INVENTORY}"
echo "Playbook  : ${PLAYBOOK}"
echo "L3_TAGS   : ${L3_TAGS:-<none>}"
echo "L3_LIMIT  : ${L3_LIMIT:-<none>}"

ansible-playbook \
  -i "${INVENTORY}" \
  "${PLAYBOOK}" \
  "${extra[@]}"

echo "=== [L3] Converge complete ==="
