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
	@$(RUN) bash -lc ' \
	  cd terraform/l2 && \
	  echo "Using Terraform in $$(pwd)"; \
	  # Ensure Terraform is initialized
	  terraform init -input=false -upgrade=false >/dev/null; \
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  export TF_VAR_l1_manifest_json="$$(jq -c '.' manifests/arch_devops/template-manifest.json)"; \
	  if [ "$${APPLY:-0}" = "1" ]; then \
	    echo "Applying Terraform destroy (APPLY=1)"; \
	    terraform apply -destroy -auto-approve; \
	  else \
	    echo "Terraform destroy plan only (no changes applied)."; \
	    echo "Set APPLY=1 to actually destroy."; \
	    terraform plan -destroy; \
	  fi'

l3-apply: ## Converge Arch DevOps host (L3 via Ansible)
	@$(RUN) bash -lc 'ansible-playbook \
	  -i ansible/inventories/arch_devops/hosts.ini \
	  ansible/playbooks/l3_arch.yml'
