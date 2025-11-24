#!/usr/bin/env bash
set -euo pipefail

: "${PROXMOX_URL:?Missing PROXMOX_URL}"
: "${PROXMOX_USERNAME:?Missing PROXMOX_USERNAME}"
: "${PROXMOX_TOKEN:?Missing PROXMOX_TOKEN}"
: "${PROXMOX_NODE:?Missing PROXMOX_NODE}"
: "${VM_NAME:?Missing VM_NAME}"

AUTH_HEADER="Authorization: PVEAPIToken=${PROXMOX_USERNAME}=${PROXMOX_TOKEN}"

# Normalize PROXMOX_URL → ensure it has /api2/json exactly once, no trailing slash.
RAW_URL="$(printf '%s' "${PROXMOX_URL}" | tr -d '[:space:]')"  # strip whitespace just in case
API_BASE="${RAW_URL%/}"

case "${API_BASE}" in
  */api2/json)
    # already includes /api2/json
    ;;
  *)
    API_BASE="${API_BASE}/api2/json"
    ;;
esac

echo "[wait-for-shutdown] Using Proxmox API base: ${API_BASE}"
echo "[wait-for-shutdown] Looking up VM named '${VM_NAME}' on node '${PROXMOX_NODE}'..."

# Select:
#  - correct name
#  - non-template (template == 0)
#  - status == "running"
# Then pick the highest VMID numerically (in case more than one matches).
VMID="$(
  curl -fsS -k --globoff \
    -H "${AUTH_HEADER}" \
    "${API_BASE}/nodes/${PROXMOX_NODE}/qemu" \
  | jq -r --arg name "${VM_NAME}" '
      .data[]
      | select(
          .name == $name
          and ((.template // 0 | tonumber) == 0)
          and (.status == "running")
        )
      | .vmid
    ' \
  | sort -n \
  | tail -n 1 \
  | tr -dc "0-9"
)"

if [[ -z "${VMID}" ]]; then
  echo "[wait-for-shutdown] ERROR: Could not find running non-template VM '${VM_NAME}' on node '${PROXMOX_NODE}'" >&2
  exit 1
fi

echo "[wait-for-shutdown] Monitoring VMID ${VMID} for shutdown..."

STATUS_URL="${API_BASE}/nodes/${PROXMOX_NODE}/qemu/${VMID}/status/current"
echo "[wait-for-shutdown] Status URL: ${STATUS_URL}"

# 60 * 10s = 10 minutes max
for i in $(seq 1 60); do
  STATUS="$(
    curl -fsS -k --globoff \
      -H "${AUTH_HEADER}" \
      "${STATUS_URL}" \
    | jq -r '.data.status' \
  )" || STATUS="unknown"

  if [[ "${STATUS}" == "stopped" ]]; then
    echo "[wait-for-shutdown] VM ${VMID} is stopped after $((i * 10))s. Proceeding."
    exit 0
  fi

  echo "[wait-for-shutdown] Attempt ${i}/180: status=${STATUS}, waiting 10s..."
  sleep 10
done

echo "[wait-for-shutdown] ERROR: Timed out waiting for VM ${VMID} to stop" >&2
exit 1
