SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

# Wrap every command (default uses Doppler). Override with: RUN=
RUN ?= doppler run --

export PIP_DISABLE_PIP_VERSION_CHECK=1

# Load .env if present
ifneq (,$(wildcard ./.env))
include .env
export
endif

.PHONY: help smoke l0 l0-clean \
        l1 l1-init l1-validate l1-build l1-manifest l1-clean

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# --- Smoke Test ---------------------------------------------------------------

smoke: ## Call /api2/json/version with Proxmox token and save artifacts
	@$(RUN) bash -lc 'set -euo pipefail; \
	  mkdir -p artifacts; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  URL="$${PVE_ACCESS_HOST%/}/api2/json/version"; \
	  echo "GET $$URL"; \
	  curl -fsS \
	    -H "Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}" \
	    -o artifacts/pve_version.json \
	    "$$URL"; \
	  echo "Smoke OK"'

# --- L0 (Runway and Resource Check) -------------------------------------------

l0: ## Run the L0 runway locally (via Ansible), with Doppler env
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  ansible-playbook ansible/playbooks/l0_runway.yml'

l0-clean: ## Remove artifacts
	rm -rf artifacts/*

# --- L1 (Image Build) ---------------------------------------------------------

# Required env at runtime:
#   PVE_ACCESS_HOST   PM_TOKEN_ID   PM_TOKEN_SECRET
# Optional (but recommended):
#   TEMPLATE_NAME  TEMPLATE_PREFIX  PVE_NODE  PVE_BRIDGE  PVE_STORAGE_VM  ARCH_ISO_FILE

l1-init: ## Packer init for L1 (Arch)
	@$(RUN) bash -lc 'set -euo pipefail; cd packer/arch; packer fmt .; packer init .'

l1-validate: ## Validate L1 packer config (with Doppler env)
	@$(RUN) bash -lc 'set -euo pipefail; cd packer/arch; packer validate .'

l1-build: ## Build the Arch template (Packer -> Proxmox)
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  cd packer/arch; \
	  packer build .'

l1-manifest: ## Emit artifacts/images/<template>.json by querying Proxmox
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  mkdir -p artifacts/images; \
	  AUTH="Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}"; \
	  HOST="$${PVE_ACCESS_HOST%/}/api2/json"; \
	  TNAME="$${TEMPLATE_NAME:-$${TEMPLATE_PREFIX:-arch-}$$(date +%Y%m%d)}"; \
	  echo ">> Resolving template: $$TNAME"; \
	  vmline="$$(curl -fsS -H "$$AUTH" "$$HOST/cluster/resources?type=vm" \
	    | jq -r --arg n "$$TNAME" ".data[] | select(.template==1 and .name==\$$n) | \"\(.vmid) \(.node)\"")"; \
	  [ -n "$$vmline" ] || { echo "Template $$TNAME not found"; exit 1; }; \
	  vmid="$${vmline%% *}"; node="$${vmline##* }"; \
	  cfg="$$(curl -fsS -H "$$AUTH" "$$HOST/nodes/$$node/qemu/$$vmid/config" | jq -r ".data")"; \
	  jq -n --arg name "$$TNAME" --arg node "$$node" --arg vmid "$$vmid" --argjson config "$$cfg" \
	    "{name:\$$name,node:\$$node,vmid:(\$$vmid|tonumber),config:\$$config,created_at:(now|todate)}" \
	    > "artifacts/images/$${TNAME}.json"; \
	  echo "Manifest: artifacts/images/$${TNAME}.json"'

l1-clean: ## Remove L1 outputs and manifests
	@bash -lc 'set -euo pipefail; rm -rf packer/arch/outputs artifacts/images/*'

# One-shot: run all L1 steps
l1: l1-init l1-validate l1-build l1-manifest ## Run full L1 locally
