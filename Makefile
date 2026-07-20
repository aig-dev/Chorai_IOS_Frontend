IOS_DEVICE ?=
IOS_DERIVED_DATA ?= /tmp/chorai-ios-local

.PHONY: ios-run
ios-run:
	@IOS_DEVICE="$(IOS_DEVICE)" \
		IOS_DERIVED_DATA="$(IOS_DERIVED_DATA)" \
		./scripts/ios-run.sh
