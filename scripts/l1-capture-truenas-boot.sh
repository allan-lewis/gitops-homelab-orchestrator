#!/usr/bin/env bash
set -euo pipefail

# Capture a TrueNAS (or any VM) boot disk from a Proxmox node as a QCOW2 image.
#
# Usage:
#   capture-truenas-boot.sh <proxmox-node> <vmid> <local-output-dir>
#
# Example:
#   capture-truenas-boot.sh polaris 105 artifacts/truenas/boot
#
# Requirements:
#   - Run this from your operations host.
#   - SSH key-based access to the Proxmox node (default user: root).
#   - Proxmox node must have: qm, pvesm, qemu-img.
#
# Notes:
#   - SSH host key checking is disabled by default for convenience:
#       -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
#   - If the VM is running, we will:
#       - Initiate a graceful shutdown.
#       - Poll until it is stopped or a timeout is hit.
#       - Fail with an error if it does not stop in time.

PROXMOX_NODE="${1:?Usage: $0 <proxmox-node> <vmid> <local-output-dir>}"
VMID="${2:?Usage: $0 <proxmox-node> <vmid> <local-output-dir>}"
LOCAL_OUT_DIR="${3:?Usage: $0 <proxmox-node> <vmid> <local-output-dir>}"

# Optional: override these via env vars if you want non-root access or extra ssh options.
PROXMOX_USER="${PROXMOX_USER:-root}"

# Default SSH options: disable host key checking unless overridden.
DEFAULT_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
PROXMOX_SSH_OPTS="${PROXMOX_SSH_OPTS:-$DEFAULT_SSH_OPTS}"

REMOTE="${PROXMOX_USER}@${PROXMOX_NODE}"

# How long to wait for shutdown (in seconds) before giving up.
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-180}"
SHUTDOWN_POLL_INTERVAL="${SHUTDOWN_POLL_INTERVAL:-5}"

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

echo "==> Capturing boot disk for VMID ${VMID} on node ${PROXMOX_NODE}"
echo "==> Using SSH options: ${PROXMOX_SSH_OPTS}"

# Ensure local output dir exists
if [ ! -d "${LOCAL_OUT_DIR}" ]; then
  echo "==> Creating local output directory: ${LOCAL_OUT_DIR}"
  mkdir -p "${LOCAL_OUT_DIR}"
fi

# Function to get VM status string
get_vm_status() {
  ssh ${PROXMOX_SSH_OPTS} "${REMOTE}" "qm status ${VMID} --verbose 2>/dev/null || true"
}

# 1) Ensure VM is stopped (or shut it down gracefully)
echo "==> Checking VM power state..."
VM_STATUS="$(get_vm_status)"

if echo "${VM_STATUS}" | grep -q "status: stopped"; then
  echo "==> VM ${VMID} is already stopped."
else
  echo "==> VM ${VMID} is not stopped. Current status:"
  echo "${VM_STATUS}"
  echo "==> Initiating graceful shutdown via 'qm shutdown ${VMID}'..."

  ssh ${PROXMOX_SSH_OPTS} "${REMOTE}" "
    set -euo pipefail
    qm shutdown ${VMID} || true
  "

  echo "==> Waiting for VM to stop (timeout: ${SHUTDOWN_TIMEOUT}s)..."

  elapsed=0
  while true; do
    sleep "${SHUTDOWN_POLL_INTERVAL}"
    elapsed=$((elapsed + SHUTDOWN_POLL_INTERVAL))

    VM_STATUS="$(get_vm_status)"

    if echo "${VM_STATUS}" | grep -q 'status: stopped'; then
      echo "==> VM ${VMID} is now stopped."
      break
    fi

    echo "==> Still waiting... (elapsed ${elapsed}s, status: $(echo "${VM_STATUS}" | tr '\n' ' '))"

    if [ "${elapsed}" -ge "${SHUTDOWN_TIMEOUT}" ]; then
      echo "ERROR: VM ${VMID} did not stop within ${SHUTDOWN_TIMEOUT} seconds."
      echo "Please check the VM on Proxmox and try again."
      exit 1
    fi
  done
fi

# 2) Determine boot disk volume ID via qm config
echo "==> Detecting boot disk volume ID..."
BOOT_VOLID=$(ssh ${PROXMOX_SSH_OPTS} "${REMOTE}" "
  set -euo pipefail
  qm config ${VMID} \
    | awk '
        /^(scsi|virtio|sata)[0-9]+: / {
          # Example:
          #   scsi0: local-lvm:vm-104-disk-0,iothread=1,size=16G
          # We want just: local-lvm:vm-104-disk-0
          split(\$2, a, \",\")
          print a[1]
          exit
        }
      '
")

if [ -z "${BOOT_VOLID}" ]; then
  echo "ERROR: Could not determine boot disk volid for VMID ${VMID}."
  echo "Check 'qm config ${VMID}' on the Proxmox node and adjust the script if needed."
  exit 1
fi

echo "==> Boot disk volid: ${BOOT_VOLID}"

# 3) Resolve volume ID to an actual path using pvesm
echo "==> Resolving storage path via pvesm..."
REMOTE_DISK_PATH=$(ssh ${PROXMOX_SSH_OPTS} "${REMOTE}" "
  set -euo pipefail
  pvesm path '${BOOT_VOLID}'
")

if [ -z "${REMOTE_DISK_PATH}" ]; then
  echo "ERROR: pvesm could not resolve path for volid '${BOOT_VOLID}'."
  exit 1
fi

echo "==> Boot disk path on Proxmox node: ${REMOTE_DISK_PATH}"

# 4) Convert disk to QCOW2 on the Proxmox node
REMOTE_TMP_DIR="/var/tmp"
REMOTE_TS="$(timestamp)"
REMOTE_QCOW2="${REMOTE_TMP_DIR}/truenas-boot-vm${VMID}-${REMOTE_TS}.qcow2"

echo "==> Converting disk to QCOW2 on Proxmox node..."
ssh ${PROXMOX_SSH_OPTS} "${REMOTE}" "
  set -euo pipefail
  mkdir -p '${REMOTE_TMP_DIR}'
  echo 'Running: qemu-img convert -O qcow2 \"${REMOTE_DISK_PATH}\" \"${REMOTE_QCOW2}\"'
  qemu-img convert -O qcow2 '${REMOTE_DISK_PATH}' '${REMOTE_QCOW2}'
  echo 'QCOW2 created at: ${REMOTE_QCOW2}'
  echo 'qemu-img info:'
  qemu-img info '${REMOTE_QCOW2}'
"

# 5) Copy QCOW2 back to local host
# LOCAL_TS="$(timestamp)"
# LOCAL_QCOW2="${LOCAL_OUT_DIR}/truenas-boot-vm${VMID}-${LOCAL_TS}.qcow2"

# echo "==> Copying QCOW2 to local host: ${LOCAL_QCOW2}"
# scp ${PROXMOX_SSH_OPTS} "${REMOTE}:${REMOTE_QCOW2}" "${LOCAL_QCOW2}"

# echo "==> Verifying local QCOW2 with qemu-img (if present)..."
# if command -v qemu-img >/dev/null 2>&1; then
#   qemu-img info "${LOCAL_QCOW2}" || {
#     echo "WARNING: qemu-img info failed locally; file might be corrupt."
#   }
# else
#   echo "NOTE: qemu-img not installed locally; skipping local validation."
# fi

# # 6) Clean up remote QCOW2
# echo "==> Cleaning up temporary QCOW2 on Proxmox node..."
# ssh ${PROXMOX_SSH_OPTS} "${REMOTE}" "
#   set -euo pipefail
#   rm -f '${REMOTE_QCOW2}'
# "

# echo "==> Done."
# echo "Captured boot disk stored at: ${LOCAL_QCOW2}"
