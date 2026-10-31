PACKAGE := host/WispLoomKit
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/WispLoom.app
SOURCES := host/App $(PACKAGE)
XCODEBUILD := xcodebuild -project host/WispLoom.xcodeproj -scheme WispLoom -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet

.PHONY: bootstrap project apps build release run dev test lint format clean

bootstrap:
	@xcodebuild -version | grep -q '^Xcode 27' || { echo "Xcode 27 is required"; exit 1; }
	@command -v xcodegen >/dev/null || brew install xcodegen
	@test -d node_modules || npm ci
	@$(MAKE) project

project:
	xcodegen generate --spec host/project.yml

# Each app becomes build/apps/<name>/ (manifest.json, ui.js, backend/).
apps:
	node scripts/build-apps.mjs

build: project apps
	$(XCODEBUILD) -configuration Debug build

release: project apps
	$(XCODEBUILD) -configuration Release build

# WISP_APPS makes the shell load build/apps and hot-reload it.
run: build
	WISP_APPS=$(CURDIR)/build/apps $(APP)/Contents/MacOS/WispLoom

# Rebuilds ui.js on save while the shell runs; Rust backends rebuild with `make apps`.
dev: build
	node scripts/build-apps.mjs --watch & WISP_APPS=$(CURDIR)/build/apps $(APP)/Contents/MacOS/WispLoom; kill %1

test:
	swift test --package-path $(PACKAGE) --scratch-path build/WispLoomKit
	npm test --silent
	cargo test --all
	cd backend/py && python3 -m unittest

lint:
	swift format lint --strict --recursive $(SOURCES)
	npm run --silent typecheck
	cargo fmt --all --check
	cargo clippy --all-targets -- -D warnings

format:
	swift format --in-place --recursive $(SOURCES)
	cargo fmt --all

clean:
	rm -rf build
