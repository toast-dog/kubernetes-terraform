SHELL := /bin/bash

.PHONY: plan apply bootstrap bootstrap-vault

plan:  ## Plan all modules and save plan files
	terragrunt run --all plan -- -out=tfplan

apply:  ## Apply saved plan files (run plan first)
	terragrunt run --all apply -- tfplan

bootstrap:  ## Fresh cluster bootstrap
	@read -p "WARNING: Fresh cluster bootstrap. Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	@echo "\n--- [1/5] core-helm: installing Helm charts ---"
	cd core-helm && terragrunt apply -auto-approve
	@echo ""
	@echo "  Helm charts installed. Restore the wildcard TLS cert backup NOW"
	@echo "  to prevent cert-manager from issuing a new one (5/week rate limit):"
	@echo ""
	@echo "    kubectl apply -f ../wildcard-tls-backup.yaml"
	@echo ""
	@read -p "  Press enter once restored (or if this is a first-ever build with no backup)..."
	@echo "\n--- [2/5] core: applying CRD resources, NetworkPolicies, IngressRoutes ---"
	cd core && terragrunt apply -auto-approve
	@echo "\n--- [3/5] argocd: applying ---"
	cd argocd && terragrunt apply -auto-approve
	@echo "\n--- [4/5] vault-helm: deploying Vault + ESO Helm charts ---"
	cd vault-helm && terragrunt apply -auto-approve
	@echo "\n--- [5/5] Manual steps required before running 'make bootstrap-vault' ---"
	@echo ""
	@echo "  1. Initialize Vault:"
	@echo "       kubectl exec -n vault vault-0 -- vault operator init \\"
	@echo "         -key-shares=5 -key-threshold=3 -format=json > vault-init.json"
	@echo ""
	@echo "  2. Store unseal keys:"
	@echo "       kubectl create secret generic vault-unseal-keys -n vault \\"
	@echo "         --from-literal=key1=\$$(jq -r '.unseal_keys_b64[0]' vault-init.json) \\"
	@echo "         --from-literal=key2=\$$(jq -r '.unseal_keys_b64[1]' vault-init.json) \\"
	@echo "         --from-literal=key3=\$$(jq -r '.unseal_keys_b64[2]' vault-init.json)"
	@echo ""
	@echo "  3. Wait ~1 min for the vault-unseal CronJob to unseal all pods"
	@echo ""
	@echo "  4. Export the root token:"
	@echo "       export VAULT_TOKEN=\$$(jq -r '.root_token' vault-init.json)"
	@echo ""
	@echo "  5. Run: make bootstrap-vault"

bootstrap-vault:  ## Finish vault setup — run after Vault is initialized and unsealed (requires VAULT_TOKEN)
	@if [ -z "$$VAULT_TOKEN" ]; then echo "ERROR: VAULT_TOKEN is not set"; exit 1; fi
	cd vault && TF_VAR_bootstrap_mode=true terragrunt apply -auto-approve
