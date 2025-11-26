#!/usr/bin/env bash
set -euo pipefail

#
# L2 Terraform wrapper
#
# Usage:
#   l2-terraform.sh <tf_dir> <mode>
#
#   <tf_dir>  : Terraform working directory (e.g., terraform/l2/arch_devops)
#   <mode>    : "apply" or "destroy"
#
# Behavior:
#   - Validates required Proxmox- and Terraform-related environment variables.
#   - Exports TF_VAR_* variables expected by the Terraform config.
#   - Runs `terraform init` in the given directory.
#   - If mode=apply:
#       - APPLY=1  -> terraform apply -auto-approve
#       - else     -> terraform plan
#     If mode=destroy:
#       - APPLY=1  -> terraform apply -destroy -auto-approve
#       - else     -> terraform plan -destroy
#

# --- Args & basic validation -------------------------------------------------

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <tf_dir> <mode>" >&2
  echo "Example: $0 terraform/l2/arch_devops apply" >&2
  echo "         $0 terraform/l2/arch_tinker destroy" >&2
  exit 1
fi

TF_DIR="$1"
MODE="$2"

if [[ ! -d "${TF_DIR}" ]]; then
  echo "Terraform directory does not exist: ${TF_DIR}" >&2
  exit 1
fi

case "${MODE}" in
  apply|destroy) ;;
  *)
    echo "Invalid mode: ${MODE}. Expected 'apply' or 'destroy'." >&2
    exit 1
    ;;
esac

# --- Environment validation ---------------------------------------------------

: "${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"
: "${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"
: "${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"
: "${TF_VAR_PROXMOX_VM_PUBLIC_KEY:?Missing TF_VAR_PROXMOX_VM_PUBLIC_KEY}"

# --- Setup Terraform variables -----------------------------------------------

export TF_VAR_pve_access_host="${PVE_ACCESS_HOST}"
export TF_VAR_pm_token_id="${PM_TOKEN_ID}"
export TF_VAR_pm_token_secret="${PM_TOKEN_SECRET}"
export TF_VAR_proxmox_vm_public_key="${TF_VAR_PROXMOX_VM_PUBLIC_KEY}"

# --- Run Terraform ------------------------------------------------------------

cd "${TF_DIR}"
echo "Using Terraform in ${PWD}"
echo "Mode: ${MODE} (APPLY=${APPLY:-0})"

terraform init -input=false -upgrade=false >/dev/null

case "${MODE}" in
  apply)
    if [[ "${APPLY:-0}" == "1" ]]; then
      echo "Applying Terraform changes (APPLY=1)"
      terraform apply -auto-approve
    else
      echo "Terraform plan only (no changes applied)."
      echo "Set APPLY=1 to actually apply."
      terraform plan
    fi
    ;;
  destroy)
    if [[ "${APPLY:-0}" == "1" ]]; then
      echo "Applying Terraform destroy (APPLY=1)"
      terraform apply -destroy -auto-approve
    else
      echo "Terraform destroy plan only (no changes applied)."
      echo "Set APPLY=1 to actually destroy."
      terraform plan -destroy
    fi
    ;;
esac
