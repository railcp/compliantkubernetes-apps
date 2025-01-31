#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit

here="$(dirname "$(readlink -f "$0")")"

command="${1}"
helmfile_environment="${2}"
name="${3}"
release_name="${4}"

package_path="${here}/../${name}"
helmfile_path="${here}/../../helmfile.d"

helm_template() {
  helmfile -f "${helmfile_path}" -e "${helmfile_environment}" template --selector name="module-${release_name#"module-"}"
}

helm_template_main() {
  git worktree add main --quiet
  trap 'git worktree remove main' RETURN ERR

  helmfile -f "./main/helmfile.d" -e "${helmfile_environment}" template --selector name="${release_name#"module-"}"
  : # TODO: helmfile as the last command prevents the trap from firing for some reason
}

render_release() {
  crossplane render /dev/stdin "${package_path}/apis/composition.yaml" "${here}/functions.yaml" |
    yq4 'select(.kind == "Release")'
}

crossplane_diff() {
  "${here}/crossplane-helm.bash" diff "${release_name}" /dev/stdin
}

crossplane_template() {
  "${here}/crossplane-helm.bash" template "${release_name}" /dev/stdin
}

diff_template() {
  a=$(helm_template_main)
  b=$(helm_template | render_release | crossplane_template)
  diff --unified --color <(echo "${a}") <(echo "${b}")
}

validate() {
  helm_template | crossplane beta validate "${package_path}/apis" -
}

case "${command}" in
"diff-release") helm_template | render_release | crossplane_diff ;;
"diff-template") diff_template ;;
"validate") validate ;;
"dev") validate && diff_template ;;
"render") helm_template | render_release ;;
"template") helm_template ;;
esac
