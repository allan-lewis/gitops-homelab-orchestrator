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

.PHONY: help clean l0-runway l3-apply

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

clean: ## Remove all artifacts
	@$(RUN) bash -lc 'rm -rf artifacts'

l0-runway: ## Run the L0 runway (Proxmox validations via Ansible)
	@$(RUN) bash -lc ' \
	  mkdir -p artifacts; \
	  ansible-playbook ansible/playbooks/l0_runway.yml'

l3-apply: ## Converge Arch DevOps host (L3 via Ansible)
	@$(RUN) bash -lc 'ansible-playbook \
	  -i ansible/inventories/arch_devops/hosts.ini \
	  ansible/playbooks/l3_arch.yml'
