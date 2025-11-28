#!/usr/bin/env bash
set -euo pipefail

###
# ubuntu-build-template.sh
#
# Requirements (env vars):
#   PVE_ACCESS_HOST   e.g. https://polaris.hosts.allanshomelab.com
#   PVE_NODE          e.g. polaris
#   PVE_STORAGE_VM    e.g. local-lvm
#   PVE_SSH_USER      e.g. gitops or root (must be able to run qm)
#
# Optional env:
#   UBUNTU_CLOUD_IMAGE_URL  (default: Jammy cloud image)
#   UBUNTU_TEMPLATE_VMID    (default: 9000)
#   UBUNTU_TEMPLATE_NAME    (default: ubuntu-2204-cloud-base)
#   UPDATE_STABLE           (set to 1 to update vm-template-stable.json)
###

: "${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"
: "${PVE_NODE:?Missing PVE_NODE}"
: "${PVE_STORAGE_VM:?Missing PVE_STORAGE_VM}"
: "${PVE_SSH_USER:?Missing PVE_SSH_USER}"

UBUNTU_CLOUD_IMAGE_URL="${UBUNTU_CLOUD_IMAGE_URL:-https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img}"
UBUNTU_TEMPLATE_VMID="${UBUNTU_TEMPLATE_VMID:-9000}"
UBUNTU_TEMPLATE_NAME="${UBUNTU_TEMPLATE_NAME:-ubuntu-2204-cloud-base}"
UPDATE_STABLE="${UPDATE_STABLE:-0}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BUILD_ROOT="${REPO_ROOT}/artifacts/.cloud-image/ubuntu"
mkdir -p "${BUILD_ROOT}"

IMAGE_NAME="$(basename "${UBUNTU_CLOUD_IMAGE_URL}")"
IMAGE_PATH="${BUILD_ROOT}/${IMAGE_NAME}"
SHA_PATH="${BUILD_ROOT}/${IMAGE_NAME}.sha256"

echo "=== Ubuntu cloud image template build ==="
echo "Ubuntu image URL : ${UBUNTU_CLOUD_IMAGE_URL}"
echo "Local image path : ${IMAGE_PATH}"
echo "Template VMID    : ${UBUNTU_TEMPLATE_VMID}"
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
sha256sum "${IMAGE_PATH}" | awk '{print $1}' > "${SHA_PATH}"
SHA256="$(cat "${SHA_PATH}")"
echo "SHA256: ${SHA256}"
