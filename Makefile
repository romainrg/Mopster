ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
export DEVELOPER_DIR := $(lastword $(sort $(wildcard /Applications/Xcode*.app)))/Contents/Developer
endif

APP := build/Build/Products/Debug/Mopster.app
XCB := xcodebuild -project Mopster.xcodeproj -scheme Mopster -destination 'platform=macOS' -derivedDataPath build

.PHONY: generate build test core-test check-strings run demo release screenshots clean

generate:
	xcodegen generate

build: generate
	$(XCB) build

test: generate
	$(XCB) test
	$(MAKE) check-strings

core-test:
	swift test --package-path MopsterCore $(if $(FILTER),--filter $(FILTER))

check-strings:
	scripts/check-strings.sh

run: build
	open $(APP)

demo: build
	$(APP)/Contents/MacOS/Mopster --demo

release:
	scripts/build-release.sh

screenshots:
	scripts/screenshots.sh --readme

clean:
	rm -rf build Mopster.xcodeproj Mopster/Resources/Info.plist MopsterCore/.build
