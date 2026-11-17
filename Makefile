SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

REPO    := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
VERSION := $(shell sed -n 's/^DCT_VERSION=//p' payload/branding/tokens.env)

.PHONY: help
help: ## show this help
	@echo "Dominican OS build — version $(VERSION)"
	@echo
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  Fast loop:  sudo ./scripts/apply-branding.sh && ./scripts/verify-branding.sh"

.PHONY: deps
deps: ## check for a container runtime (podman or docker)
	@command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || \
	  { echo "need podman or docker"; exit 1; }
	@command -v podman >/dev/null 2>&1 && echo "runtime: podman" || echo "runtime: docker"

.PHONY: apply
apply: ## apply branding to THIS machine (needs root)
	sudo ./scripts/apply-branding.sh

.PHONY: dry-run
dry-run: ## preview what apply-branding would change
	./scripts/apply-branding.sh --dry-run

.PHONY: verify
verify: ## scan for leftover upstream branding
	./scripts/verify-branding.sh

.PHONY: audit
audit: ## firmware / Secure Boot baseline report for this machine
	mkdir -p docs/baseline
	./scripts/audit-secureboot.sh

.PHONY: baseline
baseline: ## save this machine's audit to docs/baseline/<hostname>.txt
	mkdir -p docs/baseline
	./scripts/audit-secureboot.sh "docs/baseline/$$(hostname).txt"
	@$(MAKE) --no-print-directory summary

.PHONY: summary
summary: ## rebuild docs/baseline/summary.csv from every report
	@mkdir -p docs/baseline
	@{ \
	  echo 'hostname,verdict,secureboot,bios_version,image'; \
	  grep -h '^MACHINE|' docs/baseline/*.txt 2>/dev/null \
	    | sed 's/^MACHINE|//; s/|/,/g'; \
	} > docs/baseline/summary.csv
	@echo
	@echo '--- docs/baseline/summary.csv ---'
	@cat docs/baseline/summary.csv

.PHONY: pkgs
pkgs: deps ## build the two .deb packages into dist/
	./scripts/build-pkgs.sh

.PHONY: iso
iso: deps pkgs ## assemble the ISO (slow, reproducible)
	./scripts/build-iso.sh

.PHONY: live-iso
live-iso: ## bootable live ISO by remastering Ubuntu Cinnamon 24.04 (needs sudo + xorriso)
	sudo ./scripts/build-live-iso.sh

.PHONY: live-iso-fast
live-iso-fast: ## same, but zstd squashfs (~3x faster, bigger image)
	sudo ./scripts/build-live-iso.sh --fast

.PHONY: live-iso-check
live-iso-check: ## preflight only: tooling + disk, no build
	./scripts/build-live-iso.sh --dry-run

.PHONY: iso-test
iso-test: ## boot the built ISO in QEMU and prove it reaches a desktop
	./scripts/test-live-iso.sh

.PHONY: iso-test-fast
iso-test-fast: ## structure checks only (no QEMU)
	./scripts/test-live-iso.sh --structure

.PHONY: demo
demo: ## regenerate branding assets + slide renders (no ISO needed)
	./scripts/make-demo-assets.sh
	./scripts/make-demo-mockups.sh
	@echo
	@echo "  renders -> demo/mockups/   (label these 'design render')"
	@echo "  runbook -> docs/demo.md"

.PHONY: installer-assets
installer-assets: ## re-trace installer artwork from the seal (needs uv)
	uv run --with potracer --with pillow --with numpy \
	    python3 scripts/make-installer-assets.py

.PHONY: lint
lint: ## bash syntax check on every script
	@for f in scripts/*.sh; do bash -n "$$f" && echo "ok  $$f"; done

.PHONY: clean
clean: ## remove build artefacts
	rm -rf dist live-build/binary live-build/chroot live-build/cache \
	       live-build/.build packages/*/stage .demo-build

.PHONY: clean-iso
clean-iso: ## remove remaster scratch (keeps dist/)
	rm -rf .iso-work
