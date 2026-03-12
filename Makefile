.PHONY: test-all test-unit test-e2e \
	test-kbs-unit test-as-unit test-trustee-cli-unit \
	test-kbs-e2e test-as-e2e \
	test-kbs-vault-e2e test-kbs-docker-e2e \
	kbs-e2e-build

# Aggregate targets
test-all: test-unit test-e2e

test-unit: test-kbs-unit test-as-unit test-trustee-cli-unit

test-e2e: test-kbs-e2e test-as-e2e

# KBS: lint, fmt, unit/integration tests
test-kbs-unit:
	$(MAKE) -C kbs lint TEST_FEATURES="$(TEST_FEATURES)"
	$(MAKE) -C kbs format
	$(MAKE) -C kbs check TEST_FEATURES="$(TEST_FEATURES)"

# Attestation service / RVPS / shared deps: fmt, clippy, tests
test-as-unit:
	cargo fmt -p attestation-service -p reference-value-provider-service -p eventlog -p verifier -p key-value-storage -p policy-engine --check
	cargo clippy -p attestation-service -p reference-value-provider-service -p eventlog -p verifier -p key-value-storage -p policy-engine -- -D warnings
	cargo test -p attestation-service -p reference-value-provider-service -p verifier -p eventlog -p key-value-storage -p policy-engine

# Trustee CLI: lint, fmt, unit tests
test-trustee-cli-unit:
	$(MAKE) -C tools/trustee-cli lint
	$(MAKE) -C tools/trustee-cli format
	$(MAKE) -C tools/trustee-cli check

# KBS e2e tests (reuses kbs/test Makefile)
# Build-only target used by CI to prepare kbs/test binaries and artifacts
kbs-e2e-build:
	$(MAKE) -C kbs/test install-dev-dependencies
	$(MAKE) -C kbs/test bins TEST_FEATURES="$(TEST_FEATURES)"

test-kbs-e2e: kbs-e2e-build
	$(MAKE) -C kbs/test e2e-test

# KBS Vault integration e2e (no SSL + SSL)
test-kbs-vault-e2e:
	$(MAKE) -C kbs/test install-dev-dependencies
	$(MAKE) -C kbs/test test-vault-nossl
	$(MAKE) -C kbs/test stop-vault
	$(MAKE) -C kbs/test test-vault-ssl
	$(MAKE) -C kbs/test stop-vault-ssl

# KBS Docker Compose e2e (cluster with sample TEE)
test-kbs-docker-e2e:
	cargo build --manifest-path tools/kbs-client/Cargo.toml --no-default-features --release
	openssl genpkey -algorithm ed25519 > kbs/config/private.key
	openssl pkey -in kbs/config/private.key -pubout -out kbs/config/public.pub
	docker compose build --build-arg BUILDPLATFORM="$${BUILD_PLATFORM:-linux/amd64}" --build-arg ARCH="$${TARGET_ARCH:-x86_64}" --build-arg VERIFIER="$${VERIFIER:-all-verifier}"
	docker compose up -d
	cd target/release && \
		echo "shhhhh" > test-secret && \
		./kbs-client --url http://127.0.0.1:8080 config --auth-private-key ../../kbs/config/private.key set-resource --path "test-org/test-repo/test-secret" --resource-file test-secret && \
		! ./kbs-client --url http://127.0.0.1:8080 get-resource --path "test-org/test-repo/test-secret" && \
		./kbs-client --url http://127.0.0.1:8080 config --auth-private-key ../../kbs/config/private.key set-resource-policy --policy-file "../../kbs/test/data/policy_2.rego" && \
		./kbs-client --url http://127.0.0.1:8080 get-resource --path "test-org/test-repo/test-secret"

# Attestation service e2e tests
test-as-e2e:
	$(MAKE) -C attestation-service/tests/e2e install-dependencies
	$(MAKE) -C attestation-service/tests/e2e e2e-grpc-test
	$(MAKE) -C attestation-service/tests/e2e e2e-restful-test

