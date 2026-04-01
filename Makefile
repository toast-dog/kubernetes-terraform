# Auto-discover helm_release resources in root .tf files
HELM_TARGETS := $(shell grep -h 'resource "helm_release"' *.tf | \
	sed 's/resource "helm_release" "\([^"]*\)".*/\1/' | \
	sed 's/^/-target=helm_release./' | \
	tr '\n' ' ')

.PHONY: plan plan-helm plan-init apply

plan-helm:  ## Plan helm releases only
	terraform plan $(HELM_TARGETS) -out=plan

plan-init:  ## Fresh cluster bootstrap: MetalLB first (installs its CRDs), then all helm charts, then full apply. Requires VAULT_TOKEN after vault unseal.
	terraform apply -target=helm_release.metallb
	terraform apply $(HELM_TARGETS)
	terraform apply

plan:  ## Plan everything
	terraform plan -out=plan

apply:  ## Apply the current plan
	terraform apply "plan"
