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

AUTOMATED_SRC="infra/os/arch/iso/automated_script.sh"

# You can export these from env or let the script no-op the upload part
PVE_ACCESS_HOST="${PVE_ACCESS_HOST:-}"
PVE_NODE="${PVE_NODE:-}"
PVE_ISO_STORAGE="${PVE_ISO_STORAGE:-local}"
PM_TOKEN_ID="${PM_TOKEN_ID:-}"
PM_TOKEN_SECRET="${PM_TOKEN_SECRET:-}"
PVE_SSH_IP="${PVE_SSH_IP:-}"

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

echo "==> Installing custom automated_script.sh into profile"
if [[ ! -f "${AUTOMATED_SRC}" ]]; then
  echo "ERROR: ${AUTOMATED_SRC} not found (cwd: $(pwd))" >&2
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

  BASE_URL="https://${PVE_SSH_IP}:8006"

  echo "Using base URL: ${BASE_URL}"

  curl -k --fail-with-body \
    -X POST "${BASE_URL}/api2/json/nodes/${PVE_NODE}/storage/${PVE_ISO_STORAGE}/upload?content=iso" \
    -H "Authorization: PVEAPIToken=${PM_TOKEN_ID}=${PM_TOKEN_SECRET}" \
    -F "filename=@${ISO_PATH}"

  echo "Upload complete."
else
  echo "==> Skipping Proxmox upload (PVE_ACCESS_HOST / PM_TOKEN_* not set)"
fi

########################################
# Generate ISO build manifest
########################################

echo "==> Generating ISO build manifest"

ISO_PATH=$(echo .iso-build/archiso/out/*.iso)
ISO_NAME="$(basename "$ISO_PATH")"
BASE_NAME="${ISO_NAME%.iso}"

ARTIFACTS_DIR="infra/os/arch/artifacts"
SPEC_DIR="infra/os/arch/spec"

MANIFEST_PATH="${ARTIFACTS_DIR}/${BASE_NAME}.json"
STABLE_LINK="${SPEC_DIR}/iso-manifest-stable.json"

mkdir -p "$ARTIFACTS_DIR"
mkdir -p "$SPEC_DIR"

cat > "$MANIFEST_PATH" << 'EOF'
{
  "iso_name": "__ISO_NAME__",
  "built_at": "__BUILT_AT__",
  "git_sha": "__GIT_SHA__",
  "proxmox_node": "__PVE_NODE__",
  "proxmox_storage": "__PVE_ISO_STORAGE__",
  "uploader_host": "__HOSTNAME__"
}
EOF

# Portable in-place sed (GNU + BSD)
inplace_sed() {
  local expr="$1"
  local file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    sed -i '' "$expr" "$file"
  fi
}

# Repo revision for traceability
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

inplace_sed "s|__ISO_NAME__|${ISO_NAME}|g" "$MANIFEST_PATH"
inplace_sed "s|__BUILT_AT__|$(date -u +"%Y-%m-%dT%H:%M:%SZ")|g" "$MANIFEST_PATH"
inplace_sed "s|__GIT_SHA__|${GIT_SHA}|g" "$MANIFEST_PATH"
inplace_sed "s|__PVE_NODE__|${PVE_NODE}|g" "$MANIFEST_PATH"
inplace_sed "s|__PVE_ISO_STORAGE__|${PVE_ISO_STORAGE}|g" "$MANIFEST_PATH"
inplace_sed "s|__HOSTNAME__|$(hostname)|g" "$MANIFEST_PATH"

echo "Wrote manifest: $MANIFEST_PATH"
cat "$MANIFEST_PATH"

########################################
# Update stable manifest symlink (optional)
########################################

if [[ "${UPDATE_STABLE:-yes}" == "yes" ]]; then
  echo "==> update-stable=yes → updating stable manifest symlink"

  # Always replace the symlink atomically
  ln -sfn "../artifacts/${BASE_NAME}.json" "$STABLE_LINK"

  echo "Stable manifest now points to:"
  ls -l "$STABLE_LINK"
else
  echo "==> update-stable=no → stable manifest symlink unchanged"
fi


echo "Done."
