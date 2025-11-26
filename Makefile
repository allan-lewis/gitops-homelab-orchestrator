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
export RUN

L1_UPDATE_STABLE ?= 0
export L1_UPDATE_STABLE

ifneq (,$(wildcard ./.env))
include .env # load .env if present
export
endif

.DEFAULT_GOAL := help

.PHONY: help clean l0-runway l1-arch-build l2-destroy l2-apply l3-render-inventory l3-apply l4-smoke

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

## ---- GLOBAL TARGETS
clean: ## Remove ALL artifacts across ALL layers
	@$(RUN) bash -lc 'scripts/clean-artifacts.sh'

## ---- L0 TARGETS FOR ANY OR OR PERSONA
l0-runway: ## L0 runway checks (OS/persona independent)
	@$(RUN) bash -lc 'scripts/l0-runway.sh'

## ---- L1 TARGETS FOR ALL PERSONAS FOR A SINGLE OS

# Usage examples:
#   make l1-arch-build                     # full packer build + manifest
#   make l1-arch-build SKIP_BUILD=1        # skip packer build, regenerate manifest only
l1-arch-build: ## L1 build+manifest for Arch (Packer + Proxmox template manifest)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l1-build-and-manifest.sh packer/arch'

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
	  cd terraform/l2/arch_tinker; \
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

# Render Ansible inventory from hosts.json → hosts.ini
l3-render-inventory: ## Render L3 Ansible inventory from hosts.json
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/render-inventory-from-hosts-json.sh infra/arch/tinker/spec/hosts.json artifacts/arch/tinker/hosts.ini'

# Usage examples:
#   make l3-apply                          # all hosts, all tags
#   make l3-apply L3_LIMIT=blaine          # single host
#   make l3-apply L3_LIMIT='blaine:patricia'  # Ansible limit expression
#   make l3-apply L3_TAGS=base             # only "base" tag
#   make l3-apply L3_TAGS=base,desktop     # multiple tags
l3-apply: l3-render-inventory ## Converge Arch DevOps host (L3 via Ansible)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  L3_TAGS="$(L3_TAGS)"; \
	  L3_LIMIT="$(L3_LIMIT)"; \
	  extra=""; \
	  [ -n "$$L3_TAGS" ] && extra="$$extra --tags $$L3_TAGS"; \
	  [ -n "$$L3_LIMIT" ] && extra="$$extra --limit $$L3_LIMIT"; \
	  ansible-playbook \
	    -i artifacts/arch/tinker/hosts.ini \
	    ansible/playbooks/converge-arch.yml \
	    $$extra'

l4-smoke: l3-render-inventory ## Quick smoke test for the rebuilt DevOps host (with retry)
	@echo "=== Running L4 Smoke Test (Ansible ping + uptime) ==="
	@set -euo pipefail; \
	  INI="artifacts/arch/devops/hosts.ini"; \
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
