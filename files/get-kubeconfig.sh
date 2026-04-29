#!/usr/bin/env bash
set -euo pipefail

# Pull kubeconfig from an already-deployed module and save it locally.
# Usage: ./files/get-kubeconfig.sh [module_name] [destination_file]

MODULE_NAME="${1:-cluster-a}"
DEST_FILE="${2:-$HOME/.kube/${MODULE_NAME}.yaml}"
TMP_FILE=""
USE_INSECURE=""

cleanup() {
  if [[ -n "${TMP_FILE}" && -f "${TMP_FILE}" ]]; then
    rm -f "${TMP_FILE}"
  fi
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

require_cmd terraform
require_cmd ssh
require_cmd sed

if [[ ! -f "main.tf" ]]; then
  echo "Error: run this script from the Terraform root directory." >&2
  exit 1
fi

tf_eval() {
  local expr="$1"
  local output
  if ! output="$(terraform console <<<"${expr}" 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "${output}" | tail -n 1
}

strip_quotes() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "${value}"
}

prompt_insecure_mode() {
  local answer
  if [[ -t 0 ]]; then
    while true; do
      read -r -p "Enable insecure kubeconfig mode (insecure-skip-tls-verify: true)? [y/N]: " answer
      case "${answer}" in
        y|Y|yes|YES)
          USE_INSECURE="true"
          return
          ;;
        n|N|no|NO|"")
          USE_INSECURE="false"
          return
          ;;
        *)
          echo "Please answer y or n."
          ;;
      esac
    done
  else
    USE_INSECURE="false"
  fi
}

write_secure_kubeconfig() {
  sed -E "/^[[:space:]]*insecure-skip-tls-verify:[[:space:]]*true[[:space:]]*$/d; s#server: https://(127\\.0\\.0\\.1|localhost):6443#server: https://${MODULE_CP_IP}:6443#g" \
    "${TMP_FILE}" > "${DEST_FILE}"
}

write_insecure_kubeconfig() {
  local tmp_insecure
  tmp_insecure="$(mktemp)"
  sed -E "/^[[:space:]]*insecure-skip-tls-verify:[[:space:]]*true[[:space:]]*$/d; s#server: https://(127\\.0\\.0\\.1|localhost):6443#server: https://${MODULE_CP_IP}:6443#g" "${TMP_FILE}" > "${tmp_insecure}"

  awk '
    {
      print
      if ($0 ~ /^[[:space:]]*server: https:\/\//) {
        print "    insecure-skip-tls-verify: true"
      }
    }
  ' "${tmp_insecure}" > "${DEST_FILE}"

  rm -f "${tmp_insecure}"
}

if ! MODULE_DEMO_CONNECTION_RAW="$(tf_eval "module.${MODULE_NAME}.demo_connection")"; then
  echo "Error: failed to evaluate module.${MODULE_NAME}.demo_connection." >&2
  echo "Make sure the module name exists and terraform state is initialized." >&2
  exit 1
fi

if ! MODULE_CP_IP_RAW="$(tf_eval "module.${MODULE_NAME}.instance_1_public_ip")"; then
  echo "Error: failed to evaluate module.${MODULE_NAME}.instance_1_public_ip." >&2
  echo "Make sure the module name exists and terraform state is initialized." >&2
  exit 1
fi

if [[ -z "${MODULE_DEMO_CONNECTION_RAW}" || "${MODULE_DEMO_CONNECTION_RAW}" == "(known after apply)" ]]; then
  echo "Error: could not read module.${MODULE_NAME}.demo_connection from Terraform state." >&2
  echo "Run 'terraform apply' first, or pass the correct module name." >&2
  exit 1
fi

if [[ -z "${MODULE_CP_IP_RAW}" || "${MODULE_CP_IP_RAW}" == "(known after apply)" ]]; then
  echo "Error: could not read module.${MODULE_NAME}.instance_1_public_ip from Terraform state." >&2
  exit 1
fi

MODULE_DEMO_CONNECTION="$(strip_quotes "${MODULE_DEMO_CONNECTION_RAW}")"
MODULE_CP_IP="$(strip_quotes "${MODULE_CP_IP_RAW}")"

KEY_FILE="$(printf '%s\n' "${MODULE_DEMO_CONNECTION}" | awk '{for (i=1; i<=NF; i++) if ($i=="-i") {print $(i+1); exit}}')"
USER_HOST="$(printf '%s\n' "${MODULE_DEMO_CONNECTION}" | awk '{print $NF}')"

if [[ -z "${KEY_FILE}" || -z "${USER_HOST}" ]]; then
  echo "Error: failed to parse key path or SSH target from demo_connection." >&2
  echo "Value: ${MODULE_DEMO_CONNECTION}" >&2
  exit 1
fi

if [[ ! -f "${KEY_FILE}" ]]; then
  echo "Error: SSH key file not found: ${KEY_FILE}" >&2
  exit 1
fi

mkdir -p "$(dirname "${DEST_FILE}")"
TMP_FILE="$(mktemp)"

echo "Pulling kubeconfig from ${USER_HOST} ..."
ssh -o StrictHostKeyChecking=accept-new -i "${KEY_FILE}" "${USER_HOST}" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > "${TMP_FILE}"

prompt_insecure_mode

if [[ "${USE_INSECURE}" == "true" ]]; then
  write_insecure_kubeconfig
  echo "Insecure mode enabled in kubeconfig."
else
  write_secure_kubeconfig
  echo "Secure certificate validation kept in kubeconfig."
fi

chmod 600 "${DEST_FILE}"

echo "Kubeconfig written to: ${DEST_FILE}"
echo "Use it with: export KUBECONFIG=${DEST_FILE}"
