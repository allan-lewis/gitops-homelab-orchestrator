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

.PHONY: \
  help \
  clean \
  l0-runway \
  l1-arch-template \
  l1-ubuntu-template \
  l2-arch-devops-apply \
  l2-arch-devops-destroy \
  l2-arch-tinker-apply \
  l2-arch-tinker-destroy \
  l2-ubuntu-tinker-apply \
  l2-ubuntu-tinker-destroy \
  l3-arch-devops-inventory \
  l3-arch-tinker-inventory \
  l3-ubuntu-legacy-inventory \
  l3-ubuntu-tinker-inventory \
  l3-arch-devops-converge \
  l3-arch-tinker-converge \
  l3-ubuntu-legacy-converge \
  l3-ubuntu-tinker-converge \
  l4-arch-devops-smoke \
  l4-arch-tinker-smoke \
  l4-ubuntu-tinker-smoke

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
#   make l1-arch-template                    # full packer build + manifest
#   make l1-arch-template SKIP_BUILD=1        # skip packer build, regenerate manifest only
l1-arch-template: ## L1 build+manifest for Arch (Packer + Proxmox template manifest)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l1-template-arch.sh packer/arch'

l1-ubuntu-template: ## L1 build+manifest for Ubuntu (Proxmox template manifest)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l1-template-ubuntu.sh'

## ---- L2 TARGETS PER OS/PERSONA

l2-arch-devops-apply: ## Plan/Apply Arch DevOps VM via Terraform (plan by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l2-terraform.sh terraform/l2/arch_devops apply'

l2-arch-devops-destroy: ## Plan/Destroy Arch DevOps VM via Terraform (dry-run by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l2-terraform.sh terraform/l2/arch_devops destroy'

l2-arch-tinker-apply: ## Plan/Apply Arch Tinker VM via Terraform (plan by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l2-terraform.sh terraform/l2/arch_tinker apply'

l2-arch-tinker-destroy: ## Plan/Destroy Arch Tinker VM via Terraform (dry-run by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l2-terraform.sh terraform/l2/arch_tinker destroy'

l2-ubuntu-tinker-apply: ## Plan/Apply Ubuntu Tinker VM via Terraform (plan by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l2-terraform.sh terraform/l2/ubuntu_tinker apply'

l2-ubuntu-tinker-destroy: ## Plan/Destroy Ubuntu Tinker VM via Terraform (dry-run by default)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l2-terraform.sh terraform/l2/ubuntu_tinker destroy'

## ---- L3 TARGETS PER OS/PERSONA

l3-arch-devops-inventory: ## Render L3 Ansible inventory for Arch DevOps hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-inventory.sh arch devops'

l3-arch-tinker-inventory: ## Render L3 Ansible inventory for Arch Tinker hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-inventory.sh arch tinker'

l3-ubuntu-legacy-inventory: ## Render L3 Ansible inventory for Ubuntu Legacy hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-inventory.sh ubuntu legacy'

l3-ubuntu-tinker-inventory: ## Render L3 Ansible inventory for Ubuntu Tinker hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-inventory.sh ubuntu tinker'

# Usage examples:
#   make l3-<os>-<persona>-converge                          	# all hosts, all tags
#   make l3-<os>-<persona>-converge L3_LIMIT=blaine          	# single host
#   make l3-<os>-<persona>-converge L3_LIMIT='blaine:patricia'  # Ansible limit expression
#   make l3-<os>-<persona>-converge L3_TAGS=base             	# only "base" tag
#   make l3-<os>-<persona>-converge L3_TAGS=base,desktop     	# multiple tags

l3-arch-devops-converge: l3-arch-devops-inventory ## Converge Arch DevOps hosts (L3 via Ansible)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-converge.sh arch devops'

l3-arch-tinker-converge: l3-arch-tinker-inventory ## Converge Arch Tinker hosts (L3 via Ansible)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-converge.sh arch tinker'

l3-ubuntu-legacy-converge: l3-ubuntu-legacy-inventory ## Converge Ubuntu Tinker hosts (L3 via Ansible)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-converge.sh ubuntu legacy'

l3-ubuntu-tinker-converge: l3-ubuntu-tinker-inventory ## Converge Ubuntu Tinker hosts (L3 via Ansible)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l3-converge.sh ubuntu tinker'

## ---- L4 SMOKE TEST TARGETS

l4-arch-devops-smoke: l3-arch-devops-inventory ## L4 smoke test for Arch DevOps hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l4-smoke.sh arch devops'

l4-arch-tinker-smoke: l3-arch-tinker-inventory ## L4 smoke test for Arch Tinker hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l4-smoke.sh arch tinker'

l4-ubuntu-tinker-smoke: l3-ubuntu-tinker-inventory ## L4 smoke test for Ubuntu Tinker hosts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  scripts/l4-smoke.sh ubuntu tinker'
