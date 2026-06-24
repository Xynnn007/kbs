# Helm chart end-to-end tests (Trustee deploy + kbs-client + undeploy).
#
# Prerequisites: helm, kubectl, base64, diff, and a pre-built kbs-client.
# A Kubernetes cluster must already exist (kind recommended). Cluster creation is out of band.
#
# Images must already be loaded into the target Kubernetes cluster before running e2e-test.

REPO_ROOT := $(abspath ../..)
CHART_DIR := $(abspath .)
KBS_CLIENT ?= $(REPO_ROOT)/target/release/kbs-client

HELM_RELEASE ?= trustee-e2e
NAMESPACE ?= coco-trustee-e2e
E2E_SCENARIO ?= $(CHART_DIR)/scenarios/e2e-local-images.yaml
KUBE_CONTEXT ?=
HELM_TIMEOUT ?= 20m

E2E_IMAGE_PREFIX ?= trustee-e2e
E2E_IMAGE_TAG ?= e2e
KIND_CLUSTER_NAME ?= kind

E2E_KBS_IMAGE_REPOSITORY := $(E2E_IMAGE_PREFIX)/kbs-grpc-as
E2E_AS_IMAGE_REPOSITORY := $(E2E_IMAGE_PREFIX)/coco-as-grpc
E2E_RVPS_IMAGE_REPOSITORY := $(E2E_IMAGE_PREFIX)/rvps

E2E_KBS_IMAGE := $(E2E_KBS_IMAGE_REPOSITORY):$(E2E_IMAGE_TAG)
E2E_AS_IMAGE := $(E2E_AS_IMAGE_REPOSITORY):$(E2E_IMAGE_TAG)
E2E_RVPS_IMAGE := $(E2E_RVPS_IMAGE_REPOSITORY):$(E2E_IMAGE_TAG)

HELM_KUBE_ARGS := $(if $(KUBE_CONTEXT),--kube-context '$(KUBE_CONTEXT)',)
HELM_E2E_IMAGE_ARGS := \
	--set-string kbs.image.repository='$(E2E_KBS_IMAGE_REPOSITORY)' \
	--set-string kbs.image.tag='$(E2E_IMAGE_TAG)' \
	--set-string kbs.image.pullPolicy='Never' \
	--set-string as.image.repository='$(E2E_AS_IMAGE_REPOSITORY)' \
	--set-string as.image.tag='$(E2E_IMAGE_TAG)' \
	--set-string as.image.pullPolicy='Never' \
	--set-string rvps.image.repository='$(E2E_RVPS_IMAGE_REPOSITORY)' \
	--set-string rvps.image.tag='$(E2E_IMAGE_TAG)' \
	--set-string rvps.image.pullPolicy='Never'
KUBECTL := kubectl $(if $(KUBE_CONTEXT),--context '$(KUBE_CONTEXT)',)

export HELM_RELEASE NAMESPACE E2E_SCENARIO KBS_CLIENT KUBECTL KUBE_CONTEXT \
	E2E_IMAGE_TAG E2E_IMAGE_PREFIX KIND_CLUSTER_NAME

.PHONY: e2e-test deploy undeploy test-client check-tools wait-ready \
	check-docker helm-dependency-build helm-lint load-e2e-images-into-kind

check-tools:
	@command -v helm >/dev/null || (echo "missing: helm" >&2; exit 1)
	@command -v kubectl >/dev/null || (echo "missing: kubectl" >&2; exit 1)

check-docker:
	@command -v docker >/dev/null || (echo "missing: docker" >&2; exit 1)

helm-dependency-build: check-tools
	helm dependency build '$(CHART_DIR)'

helm-lint: helm-dependency-build
	helm lint '$(CHART_DIR)' -f '$(E2E_SCENARIO)' $(HELM_E2E_IMAGE_ARGS)

load-e2e-images-into-kind: check-docker
	@command -v kind >/dev/null || (echo "missing: kind (required to load local images)" >&2; exit 1)
	@echo "==> loading images into kind cluster $(KIND_CLUSTER_NAME)"
	kind load docker-image --name '$(KIND_CLUSTER_NAME)' \
		'$(E2E_KBS_IMAGE)' '$(E2E_AS_IMAGE)' '$(E2E_RVPS_IMAGE)'

deploy: helm-lint
	helm upgrade --install '$(HELM_RELEASE)' '$(CHART_DIR)' \
		$(HELM_KUBE_ARGS) \
		--namespace '$(NAMESPACE)' \
		--create-namespace \
		-f '$(E2E_SCENARIO)' \
		$(HELM_E2E_IMAGE_ARGS) \
		--wait \
		--timeout '$(HELM_TIMEOUT)'

wait-ready: check-tools
	$(KUBECTL) wait --for=condition=available deployment/$(HELM_RELEASE)-rvps -n '$(NAMESPACE)' --timeout=600s
	$(KUBECTL) wait --for=condition=available deployment/$(HELM_RELEASE)-as -n '$(NAMESPACE)' --timeout=600s
	$(KUBECTL) wait --for=condition=available deployment/$(HELM_RELEASE)-kbs -n '$(NAMESPACE)' --timeout=600s

undeploy: check-tools
	helm uninstall '$(HELM_RELEASE)' -n '$(NAMESPACE)' $(HELM_KUBE_ARGS) 2>/dev/null || true
	$(KUBECTL) delete namespace '$(NAMESPACE)' --ignore-not-found --timeout=120s 2>/dev/null || true

test-client: check-tools wait-ready
	@chmod +x '$(CHART_DIR)/e2e/test.sh'
	@'$(CHART_DIR)/e2e/test.sh'

# Deploy, test, then always undeploy. Images must already be present in the cluster.
e2e-test: check-tools
	@status=0; \
	if [ $$status -eq 0 ]; then \
		$(MAKE) deploy || status=$$?; \
	fi; \
	if [ $$status -eq 0 ]; then \
		$(MAKE) test-client || status=$$?; \
	fi; \
	$(MAKE) undeploy || true; \
	exit $$status
