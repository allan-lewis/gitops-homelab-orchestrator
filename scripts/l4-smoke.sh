#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   l4-smoke.sh <os> <persona>
#
# Examples:
#   l4-smoke.sh arch devops
#   l4-smoke.sh arch tinker
#
# Uses inventory at:
#   artifacts/<os>/<persona>/hosts.ini
#
# Does:
#   - Waits for SSH connectivity (Ansible ping) with retries
#   - Runs Ansible ping and uptime against all hosts in the inventory

OS="${1:?Usage: $0 <os> <persona>}"
PERSONA="${2:?Usage: $0 <os> <persona>}"

INI="artifacts/${OS}/${PERSONA}/hosts.ini"

if [[ ! -f "${INI}" ]]; then
  echo "Inventory not found at: ${INI}" >&2
  echo "Did you run l3-${OS}-${PERSONA}-inventory first?" >&2
  exit 1
fi

if ! command -v ansible >/dev/null 2>&1; then
  echo "ansible is required for the L4 smoke test" >&2
  exit 1
fi

RETRIES="${RETRIES:-10}"
DELAY="${DELAY:-6}"

echo "=== [L4] Running smoke test (os=${OS}, persona=${PERSONA}) ==="
echo "Using inventory: ${INI}"
echo "Retries: ${RETRIES}, Delay: ${DELAY}s"

count=1
echo "--- Waiting for SSH connectivity (Ansible ping) ---"
until ansible -i "${INI}" all -m ping >/dev/null 2>&1; do
  if (( count >= RETRIES )); then
    echo "❌ Smoke test failed: hosts not reachable after ${RETRIES} attempts."
    exit 1
  fi
  echo "SSH not ready yet (attempt ${count}/${RETRIES}). Retrying in ${DELAY} seconds..."
  sleep "${DELAY}"
  count=$((count + 1))
done

echo "✔️ Hosts reachable! Running full smoke tests..."

echo "--- Ansible ping ---"
ansible -i "${INI}" all -m ping

echo "--- uptime ---"
ansible -i "${INI}" all -a "uptime"

echo "=== [L4] Smoke test complete (os=${OS}, persona=${PERSONA}) ==="
