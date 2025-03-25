#!/usr/bin/env bash

# Welkin operator actions.

set -eu

here="$(dirname "$(readlink -f "$0")")"

# shellcheck source=bin/common.bash
source "${here}/common.bash"

usage() {
  echo "Usage: kubectl <wc|sc> ..." >&2
  echo "       kubecolor <wc|sc> ..." >&2
  echo "       helm <wc|sc> ..." >&2
  echo "       helmfile <wc|sc> ..." >&2
  exit 1
}

# Run arbitrary kubecolor commands as cluster admin.
ops_kubecolor() {
  case "${1}" in
  sc) kubeconfig="${config[kube_config_sc]}" ;;
  wc) kubeconfig="${config[kube_config_wc]}" ;;
  *) usage ;;
  esac
  shift
  with_kubeconfig "${kubeconfig}" kubecolor "${@}"
}

# Run arbitrary kubectl commands as cluster admin.
ops_kubectl() {
  case "${1}" in
  sc) kubeconfig="${config[kube_config_sc]}" ;;
  wc) kubeconfig="${config[kube_config_wc]}" ;;
  *) usage ;;
  esac
  shift
  with_kubeconfig "${kubeconfig}" kubectl "${@}"
}

# Run arbitrary helm commands as cluster admin.
ops_helm() {
  case "${1}" in
  sc) kubeconfig="${config[kube_config_sc]}" ;;
  wc) kubeconfig="${config[kube_config_wc]}" ;;
  *) usage ;;
  esac
  shift
  with_kubeconfig "${kubeconfig}" helm "${@}"
}

# Run arbitrary Helmfile commands as cluster admin.
ops_helmfile() {
  # Skip validation when fetching completions
  if [ "$2" == "__complete" ]; then
    config_load "$1" --skip-validation
  else
    config_load "$1"
  fi

  case "${1}" in
  sc)
    cluster="service_cluster"
    kubeconfig="${config[kube_config_sc]}"
    ;;
  wc)
    cluster="workload_cluster"
    kubeconfig="${config[kube_config_wc]}"
    ;;
  *) usage ;;
  esac

  shift

  with_kubeconfig "${kubeconfig}" \
    helmfile -f "${here}/../helmfile.d/" -e ${cluster} "${@}"
}

# Run arbitrary Velero commands as cluster admin.
ops_velero() {
  case "${1}" in
  sc) kubeconfig="${config[kube_config_sc]}" ;;
  wc) kubeconfig="${config[kube_config_wc]}" ;;
  *) usage ;;
  esac
  shift
  with_kubeconfig "${kubeconfig}" velero "${@}"
}

ops_opensearch_cli() {
  CONFIG=$(mktemp)
  OPENSEARCH_USER="admin"
  OPENSEARCH_PASSWORD=$(sops --config "${CK8S_CONFIG_PATH}/.sops.yaml" -d "${CK8S_CONFIG_PATH}"/secrets.yaml | yq4 '.opensearch.adminPassword')
  OPENSEARCH_ENDPOINT="https://opensearch.$(yq4 '.global.opsDomain' "${CK8S_CONFIG_PATH}"/common-config.yaml)"
  shift
  cat <<EOF >"$CONFIG"
  profiles:
    - name: ck8s
      endpoint: $OPENSEARCH_ENDPOINT
      password: $OPENSEARCH_PASSWORD
      user: $OPENSEARCH_USER
      max_retry: 3
      timeout: 10
EOF
  opensearch-cli "${@}" --config "$CONFIG" --profile ck8s
  rm "$CONFIG"
}

case "${1}" in
kubectl)
  shift
  ops_kubectl "${@}"
  ;;
kubecolor)
  shift
  ops_kubecolor "${@}"
  ;;
helm)
  shift
  ops_helm "${@}"
  ;;
helmfile)
  shift
  ops_helmfile "${@}"
  ;;
velero)
  shift
  ops_velero "${@}"
  ;;
opensearch-cli)
  shift
  ops_opensearch_cli "${@}"
  ;;
*) usage ;;
esac
