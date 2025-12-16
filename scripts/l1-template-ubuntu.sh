#!/usr/bin/env bash
set -euo pipefail

###
# ubuntu-build-template.sh
#
# Requirements (env vars):
#   PVE_ACCESS_HOST   e.g. https://shardik.hosts.allanshomelab.com
#   PVE_NODE          e.g. shardik
#   PVE_STORAGE_VM    e.g. local-lvm
#   PVE_SSH_USER      e.g. gitops or root (must be able to run qm)
#   PVE_SSH_IP        e.g. 10.0.0.10 (direct IP, not reverse proxy)
#
# Optional env:
#   UBUNTU_CLOUD_IMAGE_URL  (default: Noble cloud image)
#   UBUNTU_TEMPLATE_VMID    (if unset, we call pvesh get /cluster/nextid)
#   UBUNTU_TEMPLATE_NAME    (default: ubuntu-2204-cloud-base-YYYYMMDD)
#   UPDATE_STABLE           (set to yes to update vm-template-stable.json)
###

: "${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"
: "${PVE_NODE:?Missing PVE_NODE}"
: "${PVE_STORAGE_VM:?Missing PVE_STORAGE_VM}"
: "${PVE_SSH_USER:?Missing PVE_SSH_USER}"
: "${PVE_SSH_IP:?Missing PVE_SSH_IP}"

UBUNTU_CLOUD_IMAGE_URL="${UBUNTU_CLOUD_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
# If name not provided, include date so multiple runs don't collide
UBUNTU_TEMPLATE_NAME="${UBUNTU_TEMPLATE_NAME:-ubuntu-noble-$(date -u +"%Y%m%d")}"
UPDATE_STABLE="${UPDATE_STABLE:-yes}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BUILD_ROOT="${REPO_ROOT}/artifacts/.cloud-image/ubuntu"
mkdir -p "${BUILD_ROOT}"

IMAGE_NAME="$(basename "${UBUNTU_CLOUD_IMAGE_URL}")"
IMAGE_PATH="${BUILD_ROOT}/${IMAGE_NAME}"
SHA_PATH="${BUILD_ROOT}/${IMAGE_NAME}.sha256"

echo "=== Ubuntu cloud image template build ==="
echo "Ubuntu image URL : ${UBUNTU_CLOUD_IMAGE_URL}"
echo "Local image path : ${IMAGE_PATH}"
echo "Template name    : ${UBUNTU_TEMPLATE_NAME}"
echo "Proxmox node     : ${PVE_NODE}"
echo "Proxmox storage  : ${PVE_STORAGE_VM}"

echo
echo "==> Downloading Ubuntu cloud image (if needed)..."
if [[ ! -f "${IMAGE_PATH}" ]]; then
  curl -L --fail-with-body -o "${IMAGE_PATH}" "${UBUNTU_CLOUD_IMAGE_URL}"
else
  echo "Image already exists at ${IMAGE_PATH}, skipping download."
fi

echo "==> Calculating SHA256..."
sha256sum "${IMAGE_PATH}" | awk '{print $1}' >"${SHA_PATH}"
SHA256="$(cat "${SHA_PATH}")"
echo "SHA256: ${SHA256}"

echo
echo "==> Uploading cloud image to Proxmox..."
SSH_HOST="${PVE_SSH_IP#*://}"
SSH_HOST="${SSH_HOST%/}"

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${IMAGE_PATH}" \
  "${PVE_SSH_USER}@${SSH_HOST}:/tmp/${IMAGE_NAME}"

echo
echo "==> Selecting VMID on Proxmox..."
# If UBUNTU_TEMPLATE_VMID is set, use it; otherwise ask Proxmox for the next free one
if [[ -n "${UBUNTU_TEMPLATE_VMID:-}" ]]; then
  VMID="${UBUNTU_TEMPLATE_VMID}"
  echo "Using provided VMID: ${VMID}"
else
  VMID="$(
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "${PVE_SSH_USER}@${SSH_HOST}" \
      "pvesh get /cluster/nextid"
  )"
  echo "Using next available VMID from Proxmox: ${VMID}"
fi

echo
echo "==> Creating / refreshing Proxmox VM template (VMID=${VMID})..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${PVE_SSH_USER}@${SSH_HOST}" "bash -s" <<EOF
set -euo pipefail

VMID="${VMID}"
NAME="${UBUNTU_TEMPLATE_NAME}"
STORAGE="${PVE_STORAGE_VM}"
NODE="${PVE_NODE}"
IMAGE_PATH="/tmp/${IMAGE_NAME}"

if [ ! -f "\${IMAGE_PATH}" ]; then
  echo "ERROR: Cloud image not found at \${IMAGE_PATH}" >&2
  exit 1
fi

echo "Proxmox: checking for existing VMID \${VMID}..."
if qm status "\${VMID}" >/dev/null 2>&1; then
  echo "VMID \${VMID} already exists, destroying existing VM/template..."
  qm stop "\${VMID}" || true
  qm destroy "\${VMID}" --purge 1 || qm destroy "\${VMID}" || true
fi

echo "Creating VM \${VMID} (\${NAME}) on node \${NODE}..."
qm create "\${VMID}" \
  --name "\${NAME}" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --machine q35 \
  --tags "orchestrator,template,ubuntu"

echo "Importing disk into storage \${STORAGE}..."
qm importdisk "\${VMID}" "\${IMAGE_PATH}" "\${STORAGE}" --format qcow2

echo "Attaching disk as scsi0 and configuring SCSI controller..."
qm set "\${VMID}" \
  --scsihw virtio-scsi-pci \
  --scsi0 "\${STORAGE}:vm-\${VMID}-disk-0"

echo "Attaching cloud-init drive (ide2)..."
qm set "\${VMID}" --ide2 "\${STORAGE}:cloudinit"

echo "Setting boot order to scsi0..."
qm set "\${VMID}" --boot order=scsi0

echo "Configuring serial console and VGA for headless usage..."
qm set "\${VMID}" --serial0 socket --vga serial0

echo "Enabling QEMU guest agent..."
qm set "\${VMID}" --agent 1

echo "Converting VM \${VMID} to template..."
qm template "\${VMID}"

echo "Cleaning up uploaded image..."
rm -f "\${IMAGE_PATH}"

echo "Template \${VMID} (\${NAME}) ready on node \${NODE} with storage \${STORAGE}."
EOF

echo
echo "==> Generating manifest JSON..."

TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ARTIFACT_DIR="${REPO_ROOT}/infra/os/ubuntu/artifacts"
SPEC_DIR="${REPO_ROOT}/infra/os/ubuntu/spec"
mkdir -p "${ARTIFACT_DIR}" "${SPEC_DIR}"

MANIFEST_FILE="${ARTIFACT_DIR}/vm-template-$(date -u +"%Y%m%d-%H%M%S").json"

cat >"${MANIFEST_FILE}" <<EOF
{
  "created_at": "${TIMESTAMP_UTC}",
  "description": "Ubuntu cloud-image base with qemu-guest-agent and cloud-init drive",
  "name": "${UBUNTU_TEMPLATE_NAME}",
  "node": "${PVE_NODE}",
  "storage": "${PVE_STORAGE_VM}",
  "vmid": ${VMID},
  "cloud_image_url": "${UBUNTU_CLOUD_IMAGE_URL}",
  "cloud_image_sha256": "${SHA256}"
}
EOF

echo "Manifest written to: ${MANIFEST_FILE}"
cat "${MANIFEST_FILE}"

if [[ "${UPDATE_STABLE}" == "yes" ]]; then
  STABLE_PATH="${SPEC_DIR}/vm-template-stable.json"

  # Create/update symlink atomically
  ln -sf "../artifacts/$(basename "${MANIFEST_FILE}")" "${STABLE_PATH}"

  echo
  echo "Stable manifest now points to: ${STABLE_PATH}"
  ls -l "${STABLE_PATH}"
fi

echo
echo "=== Done. ==="
