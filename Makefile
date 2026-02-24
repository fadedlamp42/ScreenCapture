PROJECT = ScreenCapture.xcodeproj
SCHEME = ScreenCapture
BUILD_DIR = .build
APP_DEBUG = $(BUILD_DIR)/Build/Products/Debug/ScreenCapture.app
APP_RELEASE = $(BUILD_DIR)/Build/Products/Release/ScreenCapture.app
BINARY = Contents/MacOS/ScreenCapture

# ad-hoc signing (no Apple certificate needed for local dev)
SIGN_FLAGS = CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
DEPLOY_TARGET = MACOSX_DEPLOYMENT_TARGET=15.0

# suppress xcodebuild noise; show only warnings/errors
XCODE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR) -quiet $(SIGN_FLAGS) $(DEPLOY_TARGET)

.PHONY: run release build clean

# build debug and run in foreground (ctrl+c to quit)
run: build
	@$(APP_DEBUG)/$(BINARY)

build:
	@xcodebuild $(XCODE_FLAGS) -configuration Debug build

# build optimized release and run in foreground
release:
	@xcodebuild $(XCODE_FLAGS) -configuration Release build
	@$(APP_RELEASE)/$(BINARY)

clean:
	@rm -rf $(BUILD_DIR)
	@echo "cleaned"
