SHELL := /bin/bash

.PHONY: plan apply upgrade wipe-state

# 1Password Environment ID holding shared, non-secret config (e.g. TF_VAR_onepassword_vault_id).
# Create/manage at: 1Password app -> Developer -> Environments. Same pattern as proxmox-terraform.
OP_ENVIRONMENT_ID ?= yqyj5imuy4oxitewkr6il7t6aq

OP_CHECK = @if [ -z "$$OP_SERVICE_ACCOUNT_TOKEN" ]; then echo "ERROR: OP_SERVICE_ACCOUNT_TOKEN is not set"; exit 1; fi
OP_RUN = op run --environment $(OP_ENVIRONMENT_ID) --

plan:  ## Plan all modules and save plan files
	$(OP_CHECK)
	$(OP_RUN) terragrunt run --all plan -- -out=tfplan

apply:  ## Apply saved plan files (run plan first)
	$(OP_CHECK)
	$(OP_RUN) terragrunt run --all apply -- tfplan

upgrade:  ## Upgrade all provider lock files after version bumps (run before plan)
	terragrunt run --all init -- -upgrade

# Deliberately leaves secrets/ untouched — those 1Password items outlive any particular
# cluster instance; wiping them here would risk duplicate creation on the next apply.
# See secrets/terragrunt.hcl and RUNBOOK.md.
wipe-state:  ## Wipe state for cluster-scoped modules only — run before a fresh cluster rebuild
	@read -p "WARNING: This permanently deletes Terraform state for the cluster-scoped modules. Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	rm -rf .terraform-state/core-helm .terraform-state/core .terraform-state/argocd .terraform-state/apps
	@echo "Cluster-scoped state wiped (secrets/ and talos/ left untouched). Run 'make plan && make apply' to start fresh."
