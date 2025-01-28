#!/bin/bash

set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"

name="${1}"

package_path="${here}/../../${name}"
definition_path="${package_path}/apis/definition.yaml"

kubernetes_schema=https://raw.githubusercontent.com/kubernetes/kubernetes/refs/heads/release-1.32/api/openapi-spec/swagger.json

kube_schema_definition() {
  local definition_name="${1}"

  docker run --rm redocly/cli bundle --dereferenced "${kubernetes_schema}" | yq4 -o json '.definitions["'"${definition_name}"'"]' | yq4 --prettyPrint
}

kind=$(yq4 '.kind' "${package_path}/definition-gen.yaml")
plural="${kind,,}s"

export kind
export plural
yq4 '(.. | select(tag == "!!str")) |= envsubst(nu)' "${here}/definition-base.yaml" >"${definition_path}"

# TODO: Loop over kubernetesProperties
kube_schema_definition io.k8s.api.core.v1.Affinity |
  yq4 -i '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.affinity = load("/dev/stdin")' "${definition_path}"
