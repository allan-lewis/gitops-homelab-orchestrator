SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help

## Secrets runner wrapper
## - Default: use Doppler locally.
## - In CI (GitHub Actions), default to **no Doppler**.
## - You can still override explicitly:
##     make l1-build RUN=
##     make l1-build DOPPLER=0
##     make l1-build FORCE_DOPPLER=1
# Local default
RUN ?= doppler run --
# Auto-disable in CI unless explicitly forced
ifeq ($(CI),true)
  ifneq ($(FORCE_DOPPLER),1)
    override RUN :=
  endif
endif
# Manual kill switch (works anywhere): DOPPLER=0
ifeq ($(DOPPLER),0)
  override RUN :=
endif

export RUN

export ANSIBLE_CONFIG := $(CURDIR)/ansible.cfg
export ANSIBLE_HOST_KEY_CHECKING = False
export PIP_DISABLE_PIP_VERSION_CHECK=1

# Load .env if present
ifneq (,$(wildcard ./.env))
include .env
export
endif

.PHONY: help clean l0-runway l2-destroy l3-apply

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

clean: ## Remove all artifacts
	@$(RUN) bash -lc 'rm -rf artifacts'

l0-runway: ## Run the L0 runway (Proxmox validations via Ansible)
	@$(RUN) bash -lc ' \
	  mkdir -p artifacts; \
	  ansible-playbook ansible/playbooks/l0_runway.yml'

l2-destroy: ## Plan/Destroy Arch DevOps VM via Terraform (dry-run by default)
	@cd terraform/l2 && \
	  echo "Using Terraform in $$(pwd)" && \
	  $(RUN) terraform init -input=false -upgrade=false >/dev/null && \
	  if [ "$${APPLY:-0}" = "1" ]; then \
	    echo "Applying Terraform destroy (APPLY=1)"; \
	    TF_VAR_pve_access_host="$$PVE_ACCESS_HOST" \
	    TF_VAR_pm_token_id="$$PM_TOKEN_ID" \
	    TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET" \
	    TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY" \
	    TF_VAR_l1_manifest_json="$$(jq -c . ../../manifests/arch_devops/template-manifest.json)" \
	      $(RUN) terraform apply -destroy -auto-approve; \
	  else \
	    echo "Terraform destroy plan only (no changes applied)."; \
	    echo "Set APPLY=1 to actually destroy."; \
	    TF_VAR_pve_access_host="$$PVE_ACCESS_HOST" \
	    TF_VAR_pm_token_id="$$PM_TOKEN_ID" \
	    TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET" \
	    TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY" \
	    TF_VAR_l1_manifest_json="$$(jq -c . ../../manifests/arch_devops/template-manifest.json)" \
	      $(RUN) terraform plan -destroy; \
	  fi

l3-apply: ## Converge Arch DevOps host (L3 via Ansible)
	@$(RUN) bash -lc 'ansible-playbook \
	  -i ansible/inventories/arch_devops/hosts.ini \
	  ansible/playbooks/l3_arch.yml'

## TODO: these are legacy and need to be removed/re-factored
l1-fmt: ## Packer format for L1 (Arch)
	@$(RUN) bash -lc "set -euo pipefail; cd packer/arch; packer fmt ."

l1-init: ## Packer init for L1 (Arch)
	@$(RUN) bash -lc "set -euo pipefail; cd packer/arch; packer init ."

l1-validate: ## Validate L1 packer config (with Doppler env)
	@$(RUN) bash -lc "set -euo pipefail; cd packer/arch; packer validate ."

l1-build: ## Build the Arch template (Packer -> Proxmox) and capture VMID from packer-manifest.json
	@$(RUN) bash -lc 'set -euo pipefail; \
	  mkdir -p artifacts; \
	  echo "Running Packer build..."; \
	  packer build packer/arch | tee artifacts/l1_packer.log; \
	  manifest="artifacts/packer-manifest.json"; \
	  [ -f "$$manifest" ] || { echo "Missing $$manifest; Packer did not emit a manifest" >&2; exit 1; }; \
	  vmid="$$(jq -r '\''(.last_run_uuid) as $$id | (.builds[] | select(.packer_run_uuid==$$id) | .artifact_id) // (.builds[-1].artifact_id)'\'' "$$manifest")"; \
	  case "$$vmid" in ""|*[!0-9]*) echo "Could not parse numeric VMID from $$manifest (got: $$vmid)" >&2; exit 1;; esac; \
	  printf "%s\n" "$$vmid" > artifacts/l1_vmid; \
	  echo "Captured VMID=$$vmid"'

l1-manifest: ## Fetch VM config and save pretty JSON + normalized manifest
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  : "$${PVE_NODE:?Missing PVE_NODE}"; \
	  command -v jq >/dev/null 2>&1 || { echo "jq is required for l1-manifest"; exit 1; }; \
	  mkdir -p artifacts/l1_images; \
	  [ -f artifacts/l1_vmid ] || { echo "artifacts/l1_vmid not found. Run make l1-build first."; exit 1; }; \
	  vmid="$$(cat artifacts/l1_vmid)"; \
	  AUTH="Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}"; \
	  HOST="$${PVE_ACCESS_HOST%/}/api2/json"; \
	  raw_out="artifacts/l1_images/qemu-$${vmid}-config.json"; \
	  norm_out="artifacts/l1_images/manifest.json"; \
	  echo "GET $$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config -> $$raw_out and $$norm_out"; \
	  resp="$$(curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config")"; \
	  echo "$$resp" | jq -S . > "$$raw_out"; \
	  echo "$$resp" | jq -S --arg vmid "$$vmid" --arg node "$${PVE_NODE}" "{vmid:(\$$vmid|tonumber), node:\$$node} + .data" > "$$norm_out"; \
	  echo "Wrote $$raw_out"; \
	  echo "Wrote $$norm_out"'