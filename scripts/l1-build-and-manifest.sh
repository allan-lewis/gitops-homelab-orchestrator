#!/usr/bin/env bash
set -euo pipefail

#
# L1 build + manifest:
# - Optionally runs packer init/validate/build (unless SKIP_BUILD=1)
# - Captures VMID -> artifacts/l1_vmid
# - Fetches Proxmox VM config and writes:
#     - artifacts/l1_images/qemu-<vmid>-config.json (raw)
#     - artifacts/l1_images/template-manifest.json (normalized)
#     - infra/<os>/artifacts/vm-template-<timestamp>.json
#   and optionally updates stable symlink (L1_UPDATE_STABLE=1)
#

# --- Resolve repo root -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# --- Args --------------------------------------------------------------------

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <packer_dir> [os_name]" >&2
  echo "Example: $0 packer/arch  # os_name defaults to 'arch'" >&2
  exit 1
fi

PACKER_DIR="$1"

if [[ ! -d "${PACKER_DIR}" ]]; then
  echo "Packer directory does not exist: ${PACKER_DIR}" >&2
  exit 1
fi

# If second argument is missing, default OS to basename of PACKER_DIR
OS_NAME="${2:-$(basename "${PACKER_DIR}")}"

# --- Environment validation ---------------------------------------------------

: "${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"
: "${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"
: "${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"
: "${PVE_NODE:?Missing PVE_NODE}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for L1 build/manifest" >&2
  exit 1
fi

SKIP_BUILD="${SKIP_BUILD:-0}"          # 0 = run packer, 1 = skip
L1_UPDATE_STABLE="${L1_UPDATE_STABLE:-0}"

mkdir -p artifacts artifacts/l1_images

# --- Optional Packer build ----------------------------------------------------

vmid=""

if [[ "${SKIP_BUILD}" != "1" ]]; then
  echo "=== [L1] Running Packer build (dir: ${PACKER_DIR}) ==="

  packer init "${PACKER_DIR}"
  packer validate "${PACKER_DIR}"

  packer build "${PACKER_DIR}" | tee artifacts/l1_packer.log

  manifest="artifacts/packer-manifest.json"
  if [[ ! -f "${manifest}" ]]; then
    echo "Missing ${manifest}; Packer did not emit a manifest" >&2
    exit 1
  fi

  vmid="$(jq -r '(.last_run_uuid) as $id
    | (.builds[] | select(.packer_run_uuid == $id) | .artifact_id)
    // (.builds[-1].artifact_id)' "${manifest}")"

  case "${vmid}" in
    ""|*[!0-9]*)
      echo "Could not parse numeric VMID from manifest (got: ${vmid})" >&2
      exit 1
      ;;
  esac

  printf "%s\n" "${vmid}" > artifacts/l1_vmid
  echo "Captured VMID=${vmid}"

else
  echo "=== [L1] SKIP_BUILD=1 -> skipping Packer build ==="
  if [[ ! -f artifacts/l1_vmid ]]; then
    echo "artifacts/l1_vmid not found; cannot skip build without existing VMID" >&2
    exit 1
  fi
  vmid="$(< artifacts/l1_vmid)"

  case "${vmid}" in
    ""|*[!0-9]*)
      echo "Existing VMID in artifacts/l1_vmid is not numeric (got: ${vmid})" >&2
      exit 1
      ;;
  esac

  echo "Reusing VMID=${vmid}"
fi

# --- Fetch VM config from Proxmox --------------------------------------------

AUTH_HEADER="Authorization: PVEAPIToken=${PM_TOKEN_ID}=${PM_TOKEN_SECRET}"
HOST="${PVE_ACCESS_HOST%/}/api2/json"

raw_out="artifacts/l1_images/qemu-${vmid}-config.json"
norm_out="artifacts/l1_images/template-manifest.json"

echo "=== [L1] Fetching Proxmox VM config (VMID=${vmid}) ==="

resp="$(curl -fsS -H "${AUTH_HEADER}" "${HOST}/nodes/${PVE_NODE}/qemu/${vmid}/config")"

echo "${resp}" | jq -S . > "${raw_out}"

ctime="$(
  echo "${resp}" | jq -r '
    .data.meta
    | split(",")[]
    | select(startswith("ctime="))
    | split("=")[1]
  '
)"

if created_at="$(date -u -r "${ctime}" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)"; then
  :
else
  created_at="$(date -u -d "@${ctime}" "+%Y-%m-%dT%H:%M:%SZ")"
fi

echo "${resp}" | jq -S \
  --arg vmid "${vmid}" \
  --arg node "${PVE_NODE}" \
  --arg created_at "${created_at}" \
  '.data
   | {
       name: .name,
       node: $node,
       vmid: ($vmid | tonumber),
       storage: (.scsi0 // .ide1 | split(":")[0]),
       created_at: $created_at,
       description: .description
     }' \
  > "${norm_out}"

echo "Wrote ${raw_out}"
echo "Wrote ${norm_out}"

# --- Save versioned manifest + stable symlink --------------------------------

ts="$(date -u +"%Y%m%d-%H%M%S")"

dest_dir="infra/${OS_NAME}/artifacts"
mkdir -p "${dest_dir}"

dest_file="${dest_dir}/vm-template-${ts}.json"
cp "${norm_out}" "${dest_file}"

echo "Saved timestamped manifest to ${dest_file}"

if [[ "${L1_UPDATE_STABLE}" == "1" ]]; then
  spec_dir="infra/${OS_NAME}/spec"
  mkdir -p "${spec_dir}"
  ln -sf "../artifacts/${dest_file##*/}" "${spec_dir}/vm-template-stable.json"
  echo "Updated stable symlink -> ${spec_dir}/vm-template-stable.json"
else
  echo "Skipping stable symlink update (L1_UPDATE_STABLE=${L1_UPDATE_STABLE})"
fi

echo "=== [L1] Completed (OS=${OS_NAME}, VMID=${vmid}) ==="
