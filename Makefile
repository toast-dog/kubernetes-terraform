# Auto-discover helm_release resources in root .tf files
HELM_TARGETS := $(shell grep -h 'resource "helm_release"' *.tf | \
	sed 's/resource "helm_release" "\([^"]*\)".*/\1/' | \
	sed 's/^/-target=helm_release./' | \
	tr '\n' ' ')

.PHONY: plan plan-helm plan-init apply

plan-helm:  ## Plan helm releases only
	terraform plan $(HELM_TARGETS) -out=plan

plan-init:  ## Fresh cluster bootstrap: MetalLB first (installs its CRDs), then all helm charts, then full apply. Requires VAULT_TOKEN after vault unseal.
	@read -p "WARNING: This will force-apply Terraform across three stages without further prompts. Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	terraform apply -auto-approve -target=helm_release.metallb
	terraform apply -auto-approve $(HELM_TARGETS)
	terraform apply -auto-approve

plan:  ## Plan everything
	terraform plan -out=plan

apply:  ## Apply the current plan
	terraform apply "plan"
