#!/usr/bin/env bash
# kbs-client checks against an already-deployed Trustee Helm release.
# Cluster provisioning and Helm install/uninstall are handled by the Makefile (or CI).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CHART_DIR}/../.." && pwd)"

HELM_RELEASE="${HELM_RELEASE:-trustee-e2e}"
NAMESPACE="${NAMESPACE:-coco-trustee-e2e}"
KUBECTL="${KUBECTL:-kubectl}"

# When KBS_URL is set, use it directly; otherwise port-forward the in-cluster Service.
KBS_URL="${KBS_URL:-}"
KBS_PORT_FORWARD="${KBS_PORT_FORWARD:-18080}"

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${REPO_ROOT}/target}"
KBS_CLIENT="${KBS_CLIENT:-${CARGO_TARGET_DIR}/release/kbs-client}"
TEST_RESOURCE_FILE="${TEST_RESOURCE_FILE:-${SCRIPT_DIR}/fixtures/test-resource.txt}"
RESOURCE_PATH="${RESOURCE_PATH:-helm-e2e/test-repo/test-secret}"

WORK_DIR="$(mktemp -d)"
ADMIN_TOKEN_FILE="${WORK_DIR}/admin-token"
ROUNDTRIP_FILE="${WORK_DIR}/roundtrip.txt"
PORT_FORWARD_PID=""

cleanup() {
	local code=$?
	if [[ -n "${PORT_FORWARD_PID}" ]] && kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
		kill "${PORT_FORWARD_PID}" 2>/dev/null || true
		wait "${PORT_FORWARD_PID}" 2>/dev/null || true
	fi
	rm -rf "${WORK_DIR}"
	exit "${code}"
}
trap cleanup EXIT

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

wait_for_bootstrap_secret() {
	local secret_name="${HELM_RELEASE}-bootstrap-user-keys"
	local i
	for i in $(seq 1 120); do
		if ${KUBECTL} get secret "${secret_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
			return 0
		fi
		sleep 2
	done
	die "timed out waiting for Secret ${secret_name}"
}

start_port_forward() {
	log "port-forward KBS -> 127.0.0.1:${KBS_PORT_FORWARD}"
	${KUBECTL} port-forward -n "${NAMESPACE}" "svc/${HELM_RELEASE}-kbs" "${KBS_PORT_FORWARD}:8080" >/dev/null 2>&1 &
	PORT_FORWARD_PID=$!
	for _ in $(seq 1 60); do
		if (echo >/dev/tcp/127.0.0.1/"${KBS_PORT_FORWARD}") >/dev/null 2>&1; then
			sleep 2
			return 0
		fi
		sleep 1
	done
	die "KBS not reachable on 127.0.0.1:${KBS_PORT_FORWARD} after port-forward"
}

resolve_kbs_url() {
	if [[ -n "${KBS_URL}" ]]; then
		log "using KBS_URL=${KBS_URL}"
		return 0
	fi
	KBS_URL="http://127.0.0.1:${KBS_PORT_FORWARD}"
	start_port_forward
}

main() {
	require_cmd base64
	require_cmd diff

	[[ -x "${KBS_CLIENT}" ]] || die "kbs-client not found at ${KBS_CLIENT} (set KBS_CLIENT to a pre-built binary)"
	[[ -f "${TEST_RESOURCE_FILE}" ]] || die "test resource fixture not found: ${TEST_RESOURCE_FILE}"

	wait_for_bootstrap_secret
	resolve_kbs_url

	local secret_name="${HELM_RELEASE}-bootstrap-user-keys"
	${KUBECTL} get secret "${secret_name}" -n "${NAMESPACE}" \
		-o "jsonpath={.data.KBS_ADMIN_TOKEN}" | base64 -d >"${ADMIN_TOKEN_FILE}"

	log "set confidential resource"
	"${KBS_CLIENT}" --url "${KBS_URL}" config \
		--admin-token-file "${ADMIN_TOKEN_FILE}" \
		set-resource \
		--path "${RESOURCE_PATH}" \
		--resource-file "${TEST_RESOURCE_FILE}"

	log "set resource policy (allow_all)"
	"${KBS_CLIENT}" --url "${KBS_URL}" config \
		--admin-token-file "${ADMIN_TOKEN_FILE}" \
		set-resource-policy \
		--allow-all

	log "get resource (expect success with allow_all)"
	"${KBS_CLIENT}" --url "${KBS_URL}" get-resource \
		--path "${RESOURCE_PATH}" \
		| base64 -d >"${ROUNDTRIP_FILE}"
	diff -u "${TEST_RESOURCE_FILE}" "${ROUNDTRIP_FILE}"

	log "set resource policy (deny_all)"
	"${KBS_CLIENT}" --url "${KBS_URL}" config \
		--admin-token-file "${ADMIN_TOKEN_FILE}" \
		set-resource-policy \
		--deny-all

	log "get resource (expect failure with deny_all)"
	if "${KBS_CLIENT}" --url "${KBS_URL}" get-resource \
		--path "${RESOURCE_PATH}" >/dev/null 2>&1; then
		die "get-resource succeeded but should have been denied by deny_all resource policy"
	fi

	log "helm client e2e passed"
}

main "$@"
