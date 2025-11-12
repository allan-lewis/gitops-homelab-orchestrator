SHELL := /bin/bash
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

export PIP_DISABLE_PIP_VERSION_CHECK=1

# Load .env if present
ifneq (,$(wildcard ./.env))
include .env
export
endif

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

clean: ## Remove all artifacts
	@$(RUN) bash -lc "set -euo pipefail; rm -rf artifacts"

l0-smoke: ## Call /api2/json/version with Proxmox token and save pretty artifacts/l0_smoke_version.json
	@$(RUN) bash -lc 'set -euo pipefail; \
	  mkdir -p artifacts; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  URL="$${PVE_ACCESS_HOST%/}/api2/json/version"; \
	  echo "GET $$URL"; \
	  if command -v jq >/dev/null 2>&1; then \
	    curl -fsS -H "Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}" "$$URL" \
	      | jq -S . > artifacts/l0_smoke_version.json; \
	  else \
	    curl -fsS -H "Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}" "$$URL" \
	      > artifacts/l0_smoke_version.json; \
	  fi; \
	  echo "Smoke OK -> artifacts/l0_smoke_version.json"'

l0-build: ## Run the L0 runway locally (via Ansible), with Doppler env
	@$(RUN) bash -lc "set -euo pipefail; \
	  mkdir -p artifacts; \
	  : \"$$\{PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST\}\"; \
	  : \"$$\{PM_TOKEN_ID:?Missing PM_TOKEN_ID\}\"; \
	  : \"$$\{PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET\}\"; \
	  ansible-playbook ansible/playbooks/l0_runway.yml"

l0-clean: ## Remove L1 artifacts
	@$(RUN) bash -lc "set -euo pipefail; rm -rf artifacts/l0_smoke_version.json"

# --- L1 (Image Build) ---------------------------------------------------------

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

l1-manifest: ## Fetch VM config and save pretty JSON
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  : "$${PVE_NODE:?Missing PVE_NODE}"; \
	  mkdir -p artifacts/l1_images; \
	  [ -f artifacts/l1_vmid ] || { echo "artifacts/l1_vmid not found. Run make l1-build first."; exit 1; }; \
	  vmid="$$(cat artifacts/l1_vmid)"; \
	  AUTH="Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}"; \
	  HOST="$${PVE_ACCESS_HOST%/}/api2/json"; \
	  out="artifacts/l1_images/qemu-$${vmid}-config.json"; \
	  echo "GET $$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config -> $$out"; \
	  if command -v jq >/dev/null 2>&1; then \
	    curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config" | jq -S . > "$$out"; \
	  else \
	    curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config" > "$$out"; \
	  fi; \
	  echo "Wrote $$out"'

l1-clean: ## Remove L1 outputs and manifests
	@$(RUN) bash -lc "set -euo pipefail; rm -rf packer/arch/artifacts artifacts/l1* artifacts/l1_images artifacts/packer-manifest.json"

# --- L2 (VM Creation) ---------------------------------------------------------

l2-fmt:
	@$(RUN) bash -lc 'terraform -chdir=terraform/l2 fmt'

l2-init:
	@$(RUN) bash -lc 'export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; terraform -chdir=terraform/l2 init -upgrade'

l2-validate:
	@$(RUN) bash -lc 'export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; terraform -chdir=terraform/l2 validate'

l2-plan:
	@$(RUN) bash -lc '\
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  terraform -chdir=terraform/l2 plan'

l2-apply:
	@$(RUN) bash -lc '\
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  terraform -chdir=terraform/l2 apply -auto-approve'

l2-destroy:
	@$(RUN) bash -lc '\
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  terraform -chdir=terraform/l2 destroy -auto-approve'

l2-inventory:
	@echo "📦 L2 inventory:"
	@ls -lh artifacts/l2_inventory 2>/dev/null || echo "No inventory files yet"
	@echo ""
	@jq . artifacts/l2_inventory/inventory.json 2>/dev/null || echo "No JSON inventory yet"

l2-clean:
	@rm -rf artifacts/l2_inventory
	@echo "🧹 Removed generated L2 inventory artifacts."
