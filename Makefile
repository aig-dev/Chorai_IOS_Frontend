IOS_DEVICE ?=
IOS_DERIVED_DATA ?= /tmp/chorai-ios-local

export IOS_DEVICE IOS_DERIVED_DATA

.PHONY: ios-run
ios-run:
	@./scripts/ios-run.sh
