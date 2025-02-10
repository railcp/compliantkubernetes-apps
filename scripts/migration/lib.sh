#!/usr/bin/env bash

set -euo pipefail

GLOBAL_IFS="$IFS"

THIS="$(basename "$(readlink -f "${0}")")"

declare -A CONFIG
declare -A VERSION

SC_KUBECONFIG_FILE=".state/kube_config_sc.yaml"
WC_KUBECONFIG_FILE=".state/kube_config_wc.yaml"

declare -a SC_CONFIG_FILES
SC_CONFIG_FILES=(
  "defaults/common-config.yaml"
  "defaults/sc-config.yaml"
  "common-config.yaml"
  "sc-config.yaml"
  "secrets.yaml"
)

declare -a WC_CONFIG_FILES
WC_CONFIG_FILES=(
  "defaults/common-config.yaml"
  "defaults/wc-config.yaml"
  "common-config.yaml"
  "wc-config.yaml"
  "secrets.yaml"
)

# --- logging functions ---

log_info_no_newline() {
  echo -e -n "[\e[34mck8s\e[0m] ${CK8S_STACK}: ${*}" 1>&2
}

log_info() {
  log_info_no_newline "${*}\n"
}

log_warn_no_newline() {
  echo -e -n "[\e[33mck8s\e[0m] ${CK8S_STACK}: ${*}" 1>&2
}

log_warn() {
  log_warn_no_newline "${*}\n"
}

log_error_no_newline() {
  echo -e -n "[\e[31mck8s\e[0m] ${CK8S_STACK}: ${*}" 1>&2
}

log_error() {
  log_error_no_newline "${*}\n"
}

log_fatal() {
  log_error "${*}"
  exit 1
}

# --- git version

git_version() {
  git -C "${ROOT}" describe --exact-match --tags 2>/dev/null || git -C "${ROOT}" rev-parse HEAD
}

# --- config functions ---

# Usage: config_version <sc|wc>
config_version() {
  if [[ ! "${1:-}" =~ ^(sc|wc)$ ]]; then
    log_fatal "usage: config_version <sc|wc>"
  fi

  local prefix="${1}"

  local version
  version="$(yq4 ".global.ck8sVersion" <<<"${CONFIG["${prefix}"]}")"

  VERSION["${prefix}-config"]="${version}"
  version="${version#v}"
  VERSION["${prefix}-config-major"]="${version%%.*}"
  version="${version#*.}"
  VERSION["${prefix}-config-minor"]="${version%%.*}"
  version="${version#*.}"
  VERSION["${prefix}-config-patch"]="${version}"
}

# Usage: config_validate <secrets|sc|wc>
config_validate() {
  local defaults
  local setmes
  local pass="true"

  IFS=$'\n'

  case "${1:-}" in
  secrets)
    log_info "validating ${1}"

    setmes="$(yq_paths "set-me" < <(sops -d "${CK8S_CONFIG_PATH}/secrets.yaml"))"$'\n'"$(yq_paths "somelongsecret" < <(sops -d "${CK8S_CONFIG_PATH}/secrets.yaml"))"
    for setme in ${setmes}; do
      log_error "error: \"${setme//\"/}\" is unset in ${1}"
      pass="false"
    done
    ;;

  sc | wc)
    log_info "validating ${1}-config"

    defaults="$(yq_merge "${CK8S_CONFIG_PATH}/defaults/common-config.yaml" "${CK8S_CONFIG_PATH}/defaults/${1}-config.yaml")"
    setmes="$(yq_paths "set-me" <<<"${defaults}")"
    conditional_setmes="$(yq_paths "set-me-if-*" <<<"${defaults}")"

    for setme in ${setmes}; do
      compare=$(diff <(yq4 -oj "${setme}" <<<"${defaults}") <(yq4 -oj "${setme}" <<<"${CONFIG["${1}"]}") || true)
      if [[ -z "${compare}" ]]; then
        log_error "error: \"${setme//\"/}\" is unset in ${1}-config"
        pass="false"
      fi
    done

    for condsetme in ${conditional_setmes}; do
      required_condition=$(yq4 "${condsetme}" <<<"${defaults}" | sed -rn 's/set-me-if-(.*)/\1/p' | yq4 "[.] | flatten | .[0]")
      if [[ $(yq4 "${required_condition}" <<<"${CONFIG["${1}"]}") == "true" ]]; then
        compare=$(diff <(yq4 -oj "${condsetme}" <<<"${defaults}") <(yq4 -oj "${condsetme}" <<<"${CONFIG["${1}"]}") || true)
        if [[ -z "${compare}" ]]; then
          log_error "error: \"${condsetme//\"/}\" is unset in ${1}-config"
          pass="false"
        fi
      fi
    done

    sync_enabled=$(yq4 '.objectStorage.sync.enabled' <<<"${CONFIG["${1}"]}")
    sync_default_enabled=$(yq4 '.objectStorage.sync.syncDefaultBuckets' <<<"${CONFIG["${1}"]}")
    if [[ "${1}" = "sc" ]] && [[ "${sync_enabled}" = "true" ]] && [[ "${sync_default_enabled}" = "true" ]]; then
      log_info "checking sync swift"

      check_harbor="$(yq4 '.harbor.persistence.type' <<<"${CONFIG["${1}"]}")"
      check_thanos="$(yq4 '.thanos.objectStorage.type' <<<"${CONFIG["${1}"]}")"
      check_sync_swift="$(yq4 '.objectStorage.sync.swift' <<<"${CONFIG["${1}"]}")"

      if { [[ "${check_harbor}" = "swift" ]] || [[ "${check_thanos}" = "swift" ]]; } && [[ "${check_sync_swift}" = "null" ]]; then
        log_error "error: swift is enabled for Harbor/Thanos, but .objectStorage.sync is missing swift configuration"
      fi
    fi
    ;;

  *)
    log_fatal "usage: config_validate <secrets|sc|wc>"
    ;;
  esac

  if [[ "${pass}" = "false" ]]; then
    if [[ -t 1 ]]; then
      log_warn_no_newline "config validation failed do you still want to continue? [y/N]: "
      read -r reply
      if [[ "${reply}" != "y" ]]; then
        exit 1
      fi
    else
      exit 1
    fi
  fi

  IFS="${GLOBAL_IFS}"
}

# Usage: config_load <sc|wc>
config_load() {
  case "${1:-}" in
  sc)
    log_info "loading ${1}-config"
    CONFIG[sc]="$(yq_merge "${SC_CONFIG_FILES[@]/#/"$CK8S_CONFIG_PATH/"}")"
    config_version sc
    ;;
  wc)
    log_info "loading ${1}-config"
    CONFIG[wc]="$(yq_merge "${WC_CONFIG_FILES[@]/#/"$CK8S_CONFIG_PATH/"}")"
    config_version wc
    ;;
  *)
    log_fatal "usage: config_load <sc|wc>"
    ;;
  esac
}

check_sops() {
  grep -qs "sops:\\|\"sops\":\\|\\[sops\\]\\|sops_version=" "${1:-/dev/null}"
}

check_config() {
  if [ -z "${CK8S_CLUSTER:-}" ]; then
    log_fatal "error: \"CK8S_CLUSTER\" is unset"
  elif [[ ! "${CK8S_CLUSTER}" =~ ^(sc|wc|both)$ ]]; then
    log_fatal "error: invalid value set for \"CK8S_CLUSTER\", valid values are <sc|wc|both>"
  fi

  if [ -z "${THIS:-}" ]; then
    log_fatal "error: \"THIS\" is unset"
  elif [ -z "${ROOT:-}" ]; then
    log_fatal "error: \"ROOT\" is unset"
  elif [ -z "${CK8S_CONFIG_PATH:-}" ]; then
    log_fatal "error: \"CK8S_CONFIG_PATH\" is unset"
  elif [ ! -d "${CK8S_CONFIG_PATH}" ]; then
    log_fatal "error: \"CK8S_CONFIG_PATH\" is not a directory"
  fi

  log_info "using config path: \"${CK8S_CONFIG_PATH}\""

  local pass="true"

  if [[ "${CK8S_CLUSTER}" =~ ^(sc|both)$ ]]; then
    for FILE in "${SC_CONFIG_FILES[@]}" "$SC_KUBECONFIG_FILE"; do
      if [ ! -f "${CK8S_CONFIG_PATH}/${FILE}" ]; then
        log_error "error: \"${FILE}\" is not a file"
        pass="false"
      fi
    done
  fi
  if [[ "${CK8S_CLUSTER}" =~ ^(wc|both)$ ]]; then
    for FILE in "${WC_CONFIG_FILES[@]}" "$WC_KUBECONFIG_FILE"; do
      if [ ! -f "${CK8S_CONFIG_PATH}/${FILE}" ]; then
        log_error "error: \"${FILE}\" is not a file"
        pass="false"
      fi
    done
  fi

  if ! check_sops "${CK8S_CONFIG_PATH}/secrets.yaml"; then
    log_error "error: \"secrets.yaml\" is not encrypted"
    pass="false"
  fi

  if [[ "${pass}" = "false" ]]; then
    exit 1
  fi

  for prefix in wc sc; do
    if [[ "${CK8S_CLUSTER}" =~ ^($prefix|both)$ ]]; then
      if check_sops "${CK8S_CONFIG_PATH}/.state/kube_config_${prefix}.yaml"; then
        CONFIG["${prefix}-kubeconfig"]="encrypted"
      else
        CONFIG["${prefix}-kubeconfig"]="unencrypted"
      fi

      log_info "using ${prefix} kubeconfig ${CONFIG["${prefix}-kubeconfig"]}"
    fi
  done
}

# usage: check_version <sc|wc> <prepare|apply>
check_version() {
  if [[ ! "${1:-}" =~ ^(sc|wc)$ ]] || [[ ! "${2:-}" =~ ^(prepare|apply)$ ]]; then
    log_fatal "usage: check_version <sc|wc> <prepare|apply>"
  elif [ -z "${CK8S_TARGET_VERSION:-}" ]; then
    log_fatal "error: \"CK8S_TARGET_VERSION\" is unset"
  fi

  if [ "${VERSION["${1}-config"]}" = "any" ]; then
    log_warn "skipping version validation of ${1}-config for version \"${VERSION["${1}-config"]}\""
    return
  fi

  # `--exit-status` can be used instead of comparing to "null"
  common_override=$(yq4 '.global.ck8sVersion' "${CK8S_CONFIG_PATH}/common-config.yaml")
  sc_wc_override=$(yq4 '.global.ck8sVersion' "${CK8S_CONFIG_PATH}/${1}-config.yaml")
  if [ "$common_override" != "null" ] || [ "$sc_wc_override" != "null" ]; then
    log_warn "You have set the ck8sVersion in an override config"
    log_warn "If this override version does not match the current repository version then:"
    log_warn "- upgrade ${version} prepare will not remove it, and"
    log_warn "- upgrade ${version} apply will fail"
    if [[ -t 1 ]]; then
      log_warn_no_newline "Do you want to continue [y/N]: "
      read -r reply
      if [[ "${reply}" != "y" ]]; then
        exit 1
      fi
    fi
  fi

  cluster_version="$(get_apps_version "${1}" >/dev/null 2>&1 || true)"
  if [ -n "${cluster_version}" ]; then
    log_info "Currently running ${cluster_version} according to cluster"
    if [ "${common_override}" != "null" ] && [ "${cluster_version%.*}" != "${common_override}" ]; then
      log_warn "Version mismatch, cluster ${cluster_version}, config ${common_override}"
    fi
  fi

  if [[ ! "${VERSION["${1}-config"]}" =~ v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    log_warn "reducing version validation of ${1}-config for version \"${VERSION["${1}-config"]}\""
  else
    log_info "version validation of ${1}-config for version \"${VERSION["${1}-config"]}\""

    local version="${CK8S_TARGET_VERSION##v}"
    local major="${version%%.*}"
    local minor="${version##*.}"

    case "${2:-}" in
    prepare)
      if [ $((major - 1)) -eq "${VERSION["${1}-config-major"]}" ]; then
        if [ $((minor)) -eq 0 ]; then
          log_info "valid upgrade path to next major version \"v${major}.${minor}\""
        else
          log_fatal "invalid upgrade path to major version \"v${major}.${minor}\""
        fi
      elif [ $((major)) -eq "${VERSION["${1}-config-major"]}" ]; then
        if [ $((minor - 1)) -eq "${VERSION["${1}-config-minor"]}" ]; then
          log_info "valid upgrade path to next minor version \"v${major}.${minor}\""
        elif [ $((minor)) -eq "${VERSION["${1}-config-minor"]}" ]; then
          log_info "valid upgrade path to patch version \"v${major}.${minor}\""
        else
          log_fatal "invalid upgrade path to minor version \"v${major}.${minor}\""
        fi
      else
        log_fatal "invalid upgrade path to version \"v${major}.${minor}\""
      fi
      ;;

    apply)
      if [ $((major)) -eq "${VERSION["${1}-config-major"]}" ] && [ $((minor)) -eq "${VERSION["${1}-config-minor"]}" ]; then
        log_info "valid upgrade path to version \"v${major}.${minor}\""
      else
        log_fatal "invalid upgrade path to version \"v${major}.${minor}\""
      fi
      ;;
    esac
  fi

  local repo_version
  repo_version="$(git_version)"
  if [[ "${repo_version%.*}" == "${CK8S_TARGET_VERSION}" ]]; then
    log_info "valid repository version \"${repo_version}\""
  elif [[ "${repo_version}" == "${VERSION["${1}-config"]}" ]]; then
    log_warn "valid repository version \"${repo_version}\""
  else
    log_fatal "invalid repository version \"${repo_version}\""
  fi
}

# Root scripts need to manage this themselves
if [ -z "${CK8S_ROOT_SCRIPT:-}" ]; then
  if [ -z "${CK8S_STACK:-}" ]; then
    export CK8S_STACK="${THIS}"
  else
    export CK8S_STACK="${CK8S_STACK:-}/${THIS}"
  fi

  check_config
fi

# Normally a signal handler can only run one command. Use this to be able to
# add multiple traps for a single signal.
append_trap() {
  cmd="${1}"
  signal="${2}"

  if [ "$(trap -p "${signal}")" = "" ]; then
    # shellcheck disable=SC2064
    trap "${cmd}" "${signal}"
    return
  fi

  # shellcheck disable=SC2317
  previous_trap_cmd() { printf '%s\n' "$3"; }

  new_trap() {
    eval "previous_trap_cmd $(trap -p "${signal}")"
    printf '%s\n' "${cmd}"
  }

  # shellcheck disable=SC2064
  trap "$(new_trap)" "${signal}"
}

# usage: [[ "$(get_apps_version)" == "0.x" ]]
get_apps_version() {
  kubectl_do "${1}" get cm -n kube-system apps-meta -o jsonpath --template="{.data.version}"
}

unlock_migration() {
  kubectl_do "${1}" delete configmap -n kube-system apps-upgrade >/dev/null
}

# Usage: record_migration_prepare_begin sc|wc
record_migration_prepare_begin() {
  # This ConfigMap should only exist while doing an upgrade.
  # Abort if it already exists
  if kubectl_do "${1}" create configmap --dry-run=client -o yaml \
    -n kube-system apps-upgrade --from-literal "prepare=${CK8S_TARGET_VERSION}" |
    yq4 '.metadata.labels["app.kubernetes.io/managed-by"] = "apps-upgrade"' - |
    kubectl_do "${1}" create -f - >/dev/null; then
    return 0
  else
    log_fatal "prepare already started in ${1} (kubectl delete -n kube-system configmap apps-upgrade to try again)"
  fi
}

# Usage: record_migration_prepare_done sc|wc
record_migration_prepare_done() {
  # assert that the above begin has been done and from the expected version
  # yq4 should trip pipefail on version mismatch
  if kubectl_do "${1}" get -n kube-system cm apps-upgrade -o yaml |
    yq4 --exit-status 'select(.data.prepare == strenv(CK8S_TARGET_VERSION)) |
      .data.prepared = strenv(CK8S_TARGET_VERSION) |
      del(.data.last_prepare_step)' |
    kubectl_do "${1}" replace -f - >/dev/null then
    return 0
  else
    log_fatal "could not mark preparation as completed in ${1}"
  fi
}

# Get currently prepared version
get_prepared_version() {
  kubectl_do "${1}" get cm -n kube-system apps-upgrade -o jsonpath --template="{.data.prepared}"
}

# Usage: record_migration_prepare_step sc|wc step-description
record_migration_prepare_step() {
  local apps_upgrade
  apps_upgrade="$(kubectl_do "${1}" get -n kube-system cm apps-upgrade -o yaml)"
  if ! yq4 --exit-status 'select(.data.prepare == strenv(CK8S_TARGET_VERSION))' <<<"${apps_upgrade}"; then
    log_fatal "version mismatch, upgrading to ${CK8S_TARGET_VERSION} but cluster ${1} was prepared for $(yq4 '.data.prepare' <<<"${apps_upgrade}")"
  fi
  apps_upgrade="$(last_step="${2##*/}" yq4 --exit-status '.data.last_prepare_step = strenv(last_step)')"
  if ! kubectl_do "${1}" replace -f - >/dev/null; then
    log_fatal "could not record completed migration step in ${1}"
  fi
}

# Usage: record_migration_apply_step sc|wc step-description
record_migration_apply_step() {
  local apps_upgrade
  apps_upgrade="$(kubectl_do "${1}" get -n kube-system cm apps-upgrade -o yaml)"
  if ! yq4 --exit-status 'select(.data.prepare == strenv(CK8S_TARGET_VERSION))' <<<"${apps_upgrade}"; then
    log_fatal "version mismatch, upgrading to ${CK8S_TARGET_VERSION} but cluster ${1} was prepared for $(yq4 '.data.prepare' <<<"${apps_upgrade}")"
  fi
  apps_upgrade="$(last_step="${2##*/}" yq4 --exit-status '.data.last_apply_step = strenv(last_step)')"
  if ! kubectl_do "${1}" replace -f - >/dev/null; then
    log_fatal "could not record completed migration step in ${1}"
  fi
}

# Usage: record_migration_done sc|wc
record_migration_done() {
  # Record the upgraded-to version. Create if it does not already exist.
  if ! kubectl_do "${1}" patch -n kube-system cm apps-meta --type=merge -p "$(yq4 --null-input --output-format json '.data.version = strenv(CK8S_TARGET_VERSION)')"; then
    if ! kubectl_do "${1}" create configmap -n kube-system apps-meta --from-literal "version=${CK8S_TARGET_VERSION}"; then
      log_fatal "could not record new apps version in ${1}"
    fi
  fi
  # Complete the migration.
  kubectl_do "${1}" delete configmap -n kube-system apps-upgrade >/dev/null
}

# shellcheck source=scripts/migration/helm.sh
source "${ROOT}/scripts/migration/helm.sh"
# shellcheck source=scripts/migration/helmfile.sh
source "${ROOT}/scripts/migration/helmfile.sh"
# shellcheck source=scripts/migration/kubectl.sh
source "${ROOT}/scripts/migration/kubectl.sh"
# shellcheck source=scripts/migration/yq.sh
source "${ROOT}/scripts/migration/yq.sh"
