#!/bin/bash

set -euo pipefail

if [ "$(kind get clusters | wc -l)" -ne "1" ]; then
  echo "number of kind clusters is not exactly 1" >&2
  exit 1
fi

helmfile -e service_cluster apply -l name=crossplane-packages --include-transitive-needs

kubectl wait --for condition=Healthy=true providers.pkg.crossplane.io/provider-helm --timeout 120s
kubectl wait --for condition=Healthy=true providers.pkg.crossplane.io/provider-kubernetes --timeout 120s
kubectl wait --for condition=Healthy=true functions.pkg.crossplane.io/function-patch-and-transform --timeout 120s
kubectl wait --for condition=Healthy=true functions.pkg.crossplane.io/function-environment-configs --timeout 120s
kubectl wait --for condition=Healthy=true configurations.pkg.crossplane.io/opensearch --timeout 120s

kubectl -n crossplane-system create secret generic wc-kubeconfig \
  --from-literal=value="$(
    kind get kubeconfig --name "$(kind get clusters)" |
      sed 's|server:.*|server: https://kubernetes.default|'
  )" \
  -o yaml --dry-run=client |
  kubectl apply -f -

helmfile -e service_cluster apply -l name=module-opensearch --include-transitive-needs
