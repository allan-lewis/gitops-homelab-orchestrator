SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c 
.ONESHELL:

RUN ?= doppler run -- # by default, run using doppler
ifeq ($(CI),true) # skip doppler in CI mode 
  ifneq ($(FORCE_DOPPLER),1) # unless forcing doppler usage
    override RUN :=
  endif
endif
ifeq ($(DOPPLER),0) # kill switch to disable doppler 
  override RUN :=
endif

export ANSIBLE_CONFIG := $(CURDIR)/ansible.cfg
export ANSIBLE_HOST_KEY_CHECKING := False
export PIP_DISABLE_PIP_VERSION_CHECK := 1
export ORCHESTRATOR_OS = "arch"
export ORCHESTRATOR_PERSONA = "devops"
export RUN

ifneq (,$(wildcard ./.env))
include .env # load .env if present
export
endif

.DEFAULT_GOAL := help

.PHONY: help clean l0-runway l1-init l1-validate l1-build l1-manifest l2-destroy l2-apply l3-apply l4-smoke

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

clean: ## Remove all artifacts
	@$(RUN) bash -lc 'rm -rf artifacts'

l0-runway: ## Run the L0 runway (Proxmox validations via Ansible)
	@$(RUN) bash -lc ' \
	  mkdir -p artifacts; \
	  ansible-playbook ansible/playbooks/l0_runway.yml'

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
	  norm_out="artifacts/l1_images/template-manifest.json"; \
	  echo "GET $$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config -> $$raw_out and $$norm_out"; \
	  resp="$$(curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config")"; \
	  echo "$$resp" | jq -S . > "$$raw_out"; \
	  ctime="$$(echo "$$resp" | jq -r '\''.data.meta | split(",")[] | select(startswith("ctime=")) | split("=")[1]'\'' )"; \
	  created_at=""; \
	  if created_at="$$(date -u -r "$$ctime" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)"; then :; else \
	    created_at="$$(date -u -d "@$$ctime" "+%Y-%m-%dT%H:%M:%SZ")"; \
	  fi; \
	  echo "$$resp" | jq -S \
	    --arg vmid "$$vmid" \
	    --arg node "$${PVE_NODE}" \
	    --arg created_at "$$created_at" \
	    '\''.data | {name: .name, node: $$node, vmid: ($$vmid | tonumber), storage: (.scsi0 // .ide1 | split(":")[0]), created_at: $$created_at, description: .description}'\'' \
	    > "$$norm_out"; \
	  echo "Wrote $$raw_out"; \
	  echo "Wrote $$norm_out"; \
	  ts="$$(date -u +"%Y%m%d-%H%M%S")"; \
	  os="$${ORCHESTRATOR_OS:-unknown_os}"; \
	  os="$${os%\"}"; \
	  os="$${os#\"}"; \
	  persona="$${ORCHESTRATOR_PERSONA:-unknown_persona}"; \
	  persona="$${persona%\"}"; \
	  persona="$${persona#\"}"; \
	  dest_dir="infra/$$os/$$persona/artifacts"; \
	  mkdir -p "$$dest_dir"; \
	  dest_file="$$dest_dir/vm-template-$$ts.json"; \
	  cp "$$norm_out" "$$dest_file"; \
	  echo "Saved timestamped manifest to $$dest_file"'

l2-destroy: ## Plan/Destroy Arch DevOps VM via Terraform (dry-run by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  cd terraform/l2; \
	  echo "Using Terraform in $$PWD"; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  : "$${TF_VAR_PROXMOX_VM_PUBLIC_KEY:?Missing TF_VAR_PROXMOX_VM_PUBLIC_KEY}"; \
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST" \
	         TF_VAR_pm_token_id="$$PM_TOKEN_ID" \
	         TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET" \
	         TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY" \
	         TF_VAR_l1_manifest_json; \
	  terraform init -input=false -upgrade=false >/dev/null; \
	  if [ "$${APPLY:-0}" = 1 ]; then \
	    echo "Applying Terraform destroy (APPLY=1)"; \
	    terraform apply -destroy -auto-approve; \
	  else \
	    echo "Terraform destroy plan only (no changes applied)."; \
	    echo "Set APPLY=1 to actually destroy."; \
	    terraform plan -destroy; \
	  fi'

l2-apply: ## Plan/Apply Arch DevOps VM via Terraform (plan by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  cd terraform/l2; \
	  echo "Using Terraform in $$PWD"; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  : "$${TF_VAR_PROXMOX_VM_PUBLIC_KEY:?Missing TF_VAR_PROXMOX_VM_PUBLIC_KEY}"; \
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST" \
	         TF_VAR_pm_token_id="$$PM_TOKEN_ID" \
	         TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET" \
	         TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY" \
	         TF_VAR_l1_manifest_json; \
	  terraform init -input=false -upgrade=false >/dev/null; \
	  if [ "$${APPLY:-0}" = 1 ]; then \
	    echo "Applying Terraform changes (APPLY=1)"; \
	    terraform apply -auto-approve; \
	  else \
	    echo "Terraform plan only (no changes applied)."; \
	    echo "Set APPLY=1 to actually apply."; \
	    terraform plan; \
	  fi'

l3-apply: ## Converge Arch DevOps host (L3 via Ansible)
	@$(RUN) bash -lc 'ansible-playbook \
	  -i ansible/inventories/arch_devops/hosts.ini \
	  ansible/playbooks/l3_arch.yml'

l4-smoke: ## Quick smoke test for the rebuilt DevOps host (with retry)
	@echo "=== Running L4 Smoke Test (Ansible ping + uptime) ==="
	@set -euo pipefail; \
	  INI="ansible/inventories/arch_devops/hosts.ini"; \
	  echo "Using inventory: $$INI"; \
	  RETRIES=10; \
	  DELAY=6; \
	  COUNT=1; \
	  echo "--- Waiting for SSH connectivity (retries: $$RETRIES, delay: $$DELAY sec) ---"; \
	  until ansible -i "$$INI" all -m ping >/dev/null 2>&1; do \
	    if [ $$COUNT -ge $$RETRIES ]; then \
	      echo "❌ Smoke test failed: host not reachable after $$RETRIES attempts."; \
	      exit 1; \
	    fi; \
	    echo "SSH not ready yet (attempt $$COUNT/$$RETRIES). Retrying in $$DELAY seconds..."; \
	    sleep $$DELAY; \
	    COUNT=$$((COUNT+1)); \
	  done; \
	  echo "✔️ Host reachable! Running full smoke tests..."; \
	  echo "--- Ansible ping ---"; \
	  ansible -i "$$INI" all -m ping; \
	  echo "--- uptime ---"; \
	  ansible -i "$$INI" all -a "uptime"; \
	  echo "=== Smoke test complete ==="
