IOS_DEVICE ?=
IOS_DERIVED_DATA ?= /tmp/chorai-ios-local

override IOS_DEVICE := $(value IOS_DEVICE)
override IOS_DERIVED_DATA := $(value IOS_DERIVED_DATA)

export IOS_DEVICE IOS_DERIVED_DATA

.PHONY: ios-run
ios-run:
	@./scripts/ios-run.sh

.PHONY: check-concurrency
check-concurrency:
	@python3 scripts/check-concurrency.py

.PHONY: check-concurrency-required
check-concurrency-required:
	@python3 scripts/check-concurrency.py --require-simulator --ui-selectors-file scripts/ios-ui-gate-selectors.json
