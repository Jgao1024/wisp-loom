PACKAGE := Packages/OrbitKit
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Orbit.app
SOURCES := App $(PACKAGE)

.PHONY: bootstrap project build run test lint format clean

bootstrap:
	@xcodebuild -version | grep -q '^Xcode 27' || { echo "Xcode 27 is required"; exit 1; }
	@command -v xcodegen >/dev/null || brew install xcodegen
	@$(MAKE) project

project:
	xcodegen generate

build: project
	xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet build

run: build
	open $(APP)

test:
	swift test --package-path $(PACKAGE) --scratch-path build/OrbitKit

lint:
	swift format lint --strict --recursive $(SOURCES)

format:
	swift format --in-place --recursive $(SOURCES)

clean:
	rm -rf build
