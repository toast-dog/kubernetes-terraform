SHELL := /bin/bash

.PHONY: plan apply upgrade bootstrap bootstrap-vault wipe-state

plan:  ## Plan all modules and save plan files
	terragrunt run --all plan -- -out=tfplan

apply:  ## Apply saved plan files (run plan first)
	terragrunt run --all apply -- tfplan

upgrade:  ## Upgrade all provider lock files after version bumps (run before plan)
	terragrunt run --all init -- -upgrade

wipe-state:  ## Wipe all Terraform state — run before make bootstrap on a fresh cluster rebuild
	@read -p "WARNING: This permanently deletes all Terraform state. Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	rm -rf .terraform-state
	@echo "State wiped. Run 'make bootstrap' to start fresh."

bootstrap:  ## Fresh cluster bootstrap
	@read -p "WARNING: Fresh cluster bootstrap. Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	@printf "\n--- [1/5] core-helm: installing Helm charts ---\n"
	cd core-helm && terragrunt apply -auto-approve
	@echo ""
	@echo "  Helm charts installed. Restore the wildcard TLS cert backup NOW"
	@echo "  to prevent cert-manager from issuing a new one (5/week rate limit):"
	@echo ""
	@echo "    kubectl apply -f ../wildcard-tls-backup.yaml"
	@echo ""
	@read -p "  Press enter once restored (or if this is a first-ever build with no backup)..."
	@printf "\n--- [2/5] core: applying CRD resources, NetworkPolicies, IngressRoutes ---\n"
	cd core && terragrunt apply -auto-approve
	@printf "\n--- [3/5] argocd: applying ---\n"
	cd argocd && terragrunt apply -auto-approve
	@printf "\n--- [4/5] vault-helm: deploying Vault + ESO Helm charts (bootstrap_mode=true: HTTP listener, no TLS) ---\n"
	cd vault-helm && TF_VAR_bootstrap_mode=true terragrunt apply -auto-approve
	@printf "\n--- [5/5] Manual steps required before running 'make bootstrap-vault' ---\n"
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
	@printf "\n--- [1/4] vault (Apply 1): PKI CAs, ACME, cert-manager auth role, HTTP ClusterIssuer, vault-tls Certificate ---\n"
	cd vault && TF_VAR_bootstrap_mode=true terragrunt apply -auto-approve
	@printf "\n--- [2/4] Waiting for cert-manager to issue the vault-tls Secret (~30s) ---\n"
	@until kubectl get secret vault-tls -n vault >/dev/null 2>&1; do echo "  waiting..."; sleep 5; done
	@echo "  vault-tls is ready."
	@printf "\n--- [3/4] vault-helm (Apply 2): enabling Vault TLS listener, updating ESO/CronJob/IngressRoute ---\n"
	@echo "  NOTE: Vault uses OnDelete strategy — pods are deleted here to apply the new TLS config."
	@echo "  They restart sealed; the unseal CronJob handles unsealing automatically (~1 min)."
	cd vault-helm && terragrunt apply -auto-approve
	kubectl delete pod -n vault -l app.kubernetes.io/name=vault
	@printf "\n  Waiting for all Vault pods to unseal (up to 5 minutes)...\n"
	@kubectl wait pod -n vault -l app.kubernetes.io/name=vault --for=condition=Ready --timeout=300s
	@echo "  All Vault pods are unsealed."
	@printf "\n  Waiting for Vault to accept authenticated requests via Traefik ingress...\n"
	@until curl -s -H "X-Vault-Token: $$VAULT_TOKEN" https://vault.lab.toastdog.net/v1/auth/token/lookup-self 2>/dev/null | grep -q '"type"'; do echo "  waiting..."; sleep 5; done
	@echo "  Vault is ready."
	@printf "\n--- [4/4] vault (Apply 2): switching ClusterIssuer to HTTPS, creating CA secrets + ServersTransport ---\n"
	cd vault && terragrunt apply -auto-approve
	@echo ""
	@echo "  Bootstrap complete. Add the root CA to your local trust stores:"
	@echo "    curl -s https://vault.lab.toastdog.net/v1/pki/ca/pem > homelab-root-ca.crt"
