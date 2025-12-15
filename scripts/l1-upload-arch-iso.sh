#!/usr/bin/env bash
set -euo pipefail

echo "Host: $(hostname)"
echo "User: $(whoami)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "Repo root: ${REPO_ROOT}"

BUILD_ROOT=".iso-build/archiso"
PROFILE_DIR="${BUILD_ROOT}/profile"
OUT_DIR="${BUILD_ROOT}/out"

AUTOMATED_SRC="infra/arch/iso/automated_script.sh"

# You can export these from env or let the script no-op the upload part
PVE_ACCESS_HOST="${PVE_ACCESS_HOST:-}"
PVE_NODE="${PVE_NODE:-}"
PVE_ISO_STORAGE="${PVE_ISO_STORAGE:-local}"
PM_TOKEN_ID="${PM_TOKEN_ID:-}"
PM_TOKEN_SECRET="${PM_TOKEN_SECRET:-}"

# UID/GID for file ownership on host (works on macOS and Linux)
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

echo "Using HOST_UID=${HOST_UID}, HOST_GID=${HOST_GID}"
echo "Build root: ${BUILD_ROOT}"

mkdir -p "${BUILD_ROOT}"

echo "==> Bootstrapping ArchISO profile via Docker"
docker run --rm -i --privileged \
  -v "${REPO_ROOT}:/work" -w /work \
  -e HOST_UID="${HOST_UID}" -e HOST_GID="${HOST_GID}" \
  archlinux:latest bash -lc '
    set -eux
    pacman -Syu --noconfirm archiso
    rm -rf .iso-build/archiso/profile
    cp -r /usr/share/archiso/configs/releng .iso-build/archiso/profile
    chown -R "$HOST_UID:$HOST_GID" .iso-build/archiso/profile
  '

exit 0

echo "==> Installing custom automated_script.sh into profile"
if [[ ! -f "${AUTOMATED_SRC}" ]]; then
  echo "ERROR: ${AUTOMATED_SRC} not found" >&2
  exit 1
fi

DEST="${PROFILE_DIR}/airootfs/root/.automated_script.sh"
cp "${AUTOMATED_SRC}" "${DEST}"
chmod +x "${DEST}"

echo "Installed automated_script.sh at: ${DEST}"
ls -l "${DEST}"

echo "==> Building Arch ISO via Docker"
mkdir -p "${OUT_DIR}"

docker run --rm -i --privileged \
  -v "${REPO_ROOT}:/work" -w /work \
  -e ARCHISO_TRACE=1 \
  -e HOST_UID="${HOST_UID}" -e HOST_GID="${HOST_GID}" \
  archlinux:latest bash -lc '
    set -eux
    pacman -Syu --noconfirm archiso

    rm -rf .iso-build/archiso/out/*
    mkarchiso -v \
      -w /tmp/archiso-work \
      -o .iso-build/archiso/out \
      .iso-build/archiso/profile \
      2>&1 | tee .iso-build/archiso/out/build.log

    chown -R "$HOST_UID:$HOST_GID" .iso-build/archiso/out
    ls -lh .iso-build/archiso/out/*.iso
  '

ISO_PATH=$(echo "${OUT_DIR}"/*.iso)
ISO_NAME="$(basename "${ISO_PATH}")"

echo "==> Built ISO: ${ISO_NAME}"
echo "ISO path: ${ISO_PATH}"

# Optional: upload to Proxmox if env vars are present
if [[ -n "${PVE_ACCESS_HOST}" && -n "${PVE_NODE}" && -n "${PM_TOKEN_ID}" && -n "${PM_TOKEN_SECRET}" ]]; then
  echo "==> Uploading ISO to Proxmox via API"

  BASE_URL="${PVE_ACCESS_HOST%/}"

  curl -k --fail-with-body \
    -X POST "${BASE_URL}/api2/json/nodes/${PVE_NODE}/storage/${PVE_ISO_STORAGE}/upload?content=iso" \
    -H "Authorization: PVEAPIToken=${PM_TOKEN_ID}=${PM_TOKEN_SECRET}" \
    -F "filename=@${ISO_PATH}"

  echo "Upload complete."
else
  echo "==> Skipping Proxmox upload (PVE_ACCESS_HOST / PM_TOKEN_* not set)"
fi

echo "Done."
