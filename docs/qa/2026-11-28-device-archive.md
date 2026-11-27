# Device archive and app privacy manifest

2026-11-28. This qualifies local packaging only. Distribution signing, IPA export, installation on a physical device, App Store privacy disclosure and external-service qualification remain open.

## Fixed input and correction

The baseline is the Git archive of d877b4c2be7c542db8e3e6b4efd3a47e002d5032, built independently with Xcode 27.2 (27B52). Its 2,561 original files were unchanged after the first device archive. That archive built successfully but lacked the app's own root PrivacyInfo.xcprivacy; twelve bundled third-party manifests were present.

Existing AuthManager, CoreFlow persistence and AppStorage use UserDefaults for information accessible to this app itself. The correction adds NSPrivacyAccessedAPICategoryUserDefaults with reason CA92.1, and includes the manifest in the app target's Resources phase. It does not change runtime data handling. Apple's [required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) requires the app's own declaration; the [reason definition](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) describes this app-local use.

The qualified input is that baseline plus these two explicit files; this document and the architecture documentation were added afterwards:

| File | SHA-256 |
| --- | --- |
| ArcNote/PrivacyInfo.xcprivacy | dc8d7e1f9a7da7f3381f30746b59206ee62ce225b69fe3bcbb66234f8459be35 |
| ArcNote.xcodeproj/project.pbxproj | ee7ea298e9d3d92c380c0026710d7b8196d6487b6ff4cbf413e5f7292b1e1573 |

All 2,562 patched source files remained unchanged after qualification. The first system tar extraction interpreted a tracked AppleDouble member as metadata and failed source completeness; that preparation failure is retained. Re-extraction preserving the actual members passed the full inventory check before building.

## Actual checks

| Check | Result |
| --- | --- |
| Persisted Swift settings | Existing check-concurrency.py --settings-only passed without Swift language or concurrency overrides |
| Release / ArcNote Production | generic/platform=iOS archive passed; actual binary IOS/arm64, minimum iOS 16.0, production API environment |
| Debug / ArcNote | generic/platform=iOS Simulator build passed; actual app local environment and minimum iOS 16.0 |
| Debug-Production / ArcNote Production | Simulator build passed; actual app production environment and minimum iOS 16.0 |
| Packaged resource | All three app roots contain the exact source manifest and reason; twelve SDK manifests retained |
| Concurrency diagnostics | Both device archive logs and both simulator build logs passed the existing first-party diagnostic checker |
| Device executable | Byte-identical before and after the resource correction; SHA-256 1b393455bf101b2191acecccc0d602fa90b08333420bb33553424469e06b5c22 |
| Final xcarchive | 84 files, 100,813,772 bytes; inventory SHA-256 5f95e372c422e2f4d93acbdcec415e934f24a0ff0a0bb2373e2699207d0b1dd1 |

The device command used the production scheme, Release, a separate DerivedData directory, copied package cache, disabled automatic package resolution, CODE_SIGNING_ALLOWED=NO and CODE_SIGNING_REQUIRED=NO. Actual codesign inspection confirms that the app is unsigned. The two simulator configurations use a separate shared simulator DerivedData directory and ran sequentially. No credentials, provisioning profile or store upload was used.

Local receipts and retained archives are under /private/tmp/chorai-rc-runtime-20261126-1386e573b5/release-ios-device-20261128. The backend release evidence has a sanitized machine summary. No functional UI or business tests were rerun for this resource-only correction. The prior 171 hosted and eleven UI checks belong to the [share qualification](2026-11-28-share-runtime.md), not this run.

The manifest only declares the confirmed required-reason API use. It makes no claim that the complete data collection disclosure, all SDK declarations, signed distribution or overall launch readiness have passed.
