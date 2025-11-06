\
SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

export PIP_DISABLE_PIP_VERSION_CHECK=1

# Load .env if present
ifneq (,$(wildcard ./.env))
include .env
export
endif

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

smoke: ## Call /api2/json/version with Proxmox token and save artifacts
	@bash -lc 'set -euo pipefail; \
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
	  jq . artifacts/pve_version.json > artifacts/sanity_version.json || cp artifacts/pve_version.json artifacts/sanity_version.json; \
	  echo "Smoke OK"'

l0: ## Run the L0 runway locally
	@ansible-playbook ansible/playbooks/l0_runway.yml

clean: ## Remove artifacts
	rm -rf artifacts/*
