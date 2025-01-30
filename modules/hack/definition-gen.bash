#!/bin/bash

set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"

name="${1}"

package_path="${here}/../${name}"
definition_path="${package_path}/apis/definition.yaml"

kubernetes_schema=https://raw.githubusercontent.com/kubernetes/kubernetes/refs/heads/release-1.32/api/openapi-spec/swagger.json

kube_schema_definition() {
  local definition_name="${1}"

  docker run --rm redocly/cli bundle --dereferenced "${kubernetes_schema}" | yq4 --output-format json '.definitions["'"${definition_name}"'"]' | yq4 --prettyPrint
}

kind=$(yq4 '.kind' "${package_path}/definition-gen.yaml")
plural="${kind,,}s"

export kind
export plural
yq4 '(.. | select(tag == "!!str")) |= envsubst(nu)' "${here}/definition-base.yaml" >"${definition_path}"

yq4 '.properties' "${package_path}/definition-gen.yaml" | yq4 --inplace '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties = load("/dev/stdin")' "${definition_path}"

while read -r property definition isArray; do
  if [ "${isArray}" = "true" ]; then
    yq4 --inplace '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.'"${property}".type' = "array"' "${definition_path}"
    kube_schema_definition "${definition}" |
      yq4 --inplace '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.'"${property}".items' = load("/dev/stdin")' "${definition_path}"
  else
    kube_schema_definition "${definition}" |
      yq4 --inplace '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.'"${property}"' = load("/dev/stdin")' "${definition_path}"
  fi
done < <(yq4 '.kubernetesDefinitions.[] | (.property + " " + .definition + " " + .isArray // false)' "${package_path}/definition-gen.yaml")

yq4 --prettyPrint --inplace 'sort_keys(.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties)' "${definition_path}"
