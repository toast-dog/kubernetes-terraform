# Auto-discover helm_release resources in root .tf files
HELM_TARGETS := $(shell grep -h 'resource "helm_release"' *.tf | \
	sed 's/resource "helm_release" "\([^"]*\)".*/\1/' | \
	sed 's/^/-target=helm_release./' | \
	tr '\n' ' ')

.PHONY: plan plan-helm apply

plan-helm:  ## Plan helm releases only (run this first on a fresh cluster)
	terraform plan $(HELM_TARGETS) -out=plan

plan:  ## Plan everything
	terraform plan -out=plan

apply:  ## Apply the current plan
	terraform apply "plan"
