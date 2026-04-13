# ArgoCD AppProjects — one per app, created by Terraform so they exist before
# any child Application is synced. The root Application stays in "default".
#
# Each project locks down:
#   sourceRepos              — which repos/registries that app is allowed to pull from
#   destinations             — which namespace(s) that app is allowed to deploy into
#   clusterResourceWhitelist — which cluster-scoped resource types are allowed
#                              (derived by cross-referencing `helm template | grep "^kind:"``
#                               with `kubectl api-resources --namespaced=false`)

resource "kubernetes_manifest" "argocd_project_reloader" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "reloader"
      namespace = "argocd"
    }
    spec = {
      description = "Stakater Reloader — rolls pods when Secrets or ConfigMaps change"
      sourceRepos = [
        "https://stakater.github.io/stakater-charts",
        "https://git.thompson-manor.org/toast-dog/kubernetes-apps",
      ]
      destinations = [{
        namespace = "reloader"
        server    = "https://kubernetes.default.svc"
      }]
      clusterResourceWhitelist = [
        { group = "",                          kind = "Namespace"          },
        { group = "rbac.authorization.k8s.io", kind = "ClusterRole"        },
        { group = "rbac.authorization.k8s.io", kind = "ClusterRoleBinding" },
      ]
    }
  }
}

resource "kubernetes_manifest" "argocd_project_authentik" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "authentik"
      namespace = "argocd"
    }
    spec = {
      description = "Authentik identity provider"
      sourceRepos = [
        "https://charts.goauthentik.io",
        "https://git.thompson-manor.org/toast-dog/kubernetes-apps",
      ]
      destinations = [{
        namespace = "authentik"
        server    = "https://kubernetes.default.svc"
      }]
      # Authentik chart creates only namespaced RBAC (Role/RoleBinding).
      # Namespace is cluster-scoped and required for the namespace manifest.
      clusterResourceWhitelist = [
        { group = "", kind = "Namespace" },
      ]
    }
  }
}

resource "kubernetes_manifest" "argocd_project_cloudnativepg" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "cloudnativepg"
      namespace = "argocd"
    }
    spec = {
      description = "CloudNativePG operator"
      sourceRepos = [
        "https://cloudnative-pg.github.io/charts",
        "https://git.thompson-manor.org/toast-dog/kubernetes-apps",
      ]
      destinations = [{
        namespace = "cnpg-system"
        server    = "https://kubernetes.default.svc"
      }]
      clusterResourceWhitelist = [
        { group = "",                              kind = "Namespace"                      },
        { group = "apiextensions.k8s.io",          kind = "CustomResourceDefinition"      },
        { group = "rbac.authorization.k8s.io",     kind = "ClusterRole"                   },
        { group = "rbac.authorization.k8s.io",     kind = "ClusterRoleBinding"            },
        { group = "admissionregistration.k8s.io",  kind = "MutatingWebhookConfiguration"  },
        { group = "admissionregistration.k8s.io",  kind = "ValidatingWebhookConfiguration" },
      ]
    }
  }
}
