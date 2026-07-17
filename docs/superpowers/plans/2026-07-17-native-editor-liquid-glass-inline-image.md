# Native Editor Liquid Glass and Inline Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native iOS editor use its keyboard toolbar instead of slash commands, present a Liquid Glass writing surface with compact tags, and insert body images from either Photos or the camera without losing the draft.

**Architecture:** Keep SwiftUI as the native editor shell and media-acquisition owner while BlockNote remains the body-only rich-text engine inside `WKWebView`. Native code dismisses the keyboard, presents the source chooser, obtains a `CardEditingImage`, reuses `CardEditingStore.uploadInlineImage`, and sends only the successful URL through the existing bridge. The sibling web project remains the source of the bundled iOS BlockNote runtime and must stay protocol-compatible with `Packages/BlockNoteEditor`.

**Tech Stack:** Swift 5, SwiftUI, UIKit `UIImagePickerController`, AVFoundation camera authorization, PhotosUI `PhotosPicker`, WKWebView, BlockNote/React/TypeScript, Vitest, XCTest/XCUITest, Xcode 26.2 SDK.

## Global Constraints

- Work directly on `main` in both `Chorai_IOS_Frontend` and `chorai_web_frontend`; do not create a worktree.
- Keep the preserved wrong-target web UI work in `chorai_web_frontend` stash `stash@{0}` untouched.
- The iOS deployment floor remains iOS 16.0.
- On iOS 26 and later use system `glassEffect`; on iOS 16 through 25 use `ultraThinMaterial`; Reduce Transparency uses an opaque fallback.
- Typing `/` in the native embedded editor inserts text and never opens a command menu; the `@` card-link suggestion remains available.
- The keyboard formatting bar remains the mobile command surface.
- Add Tag uses the same visible capsule as a normal tag, approximately 24 points high, inside a minimum 44-by-44-point hit target.
- Photo Library and Take Photo apply only to Insert Body Image; background selection remains photo-library-only.
- Take Photo remains visible but disabled with an availability explanation when the camera is unavailable.
- Cancellation, permission denial, conversion failure, upload failure, and bridge failure do not pre-mutate the BlockNote body or discard the draft.
- The simulator proves the unavailable-camera route; physical hardware is required for final camera-capture verification.
- Do not add a backend endpoint or change the BlockNote document schema.

## File Map

### Embedded iOS editor source (`../chorai_web_frontend`)

- `src/editor/ios/EmbeddedBlockNoteEditor.tsx`: retains `@` and removes `/`.
- `src/editor/ios/EmbeddedBlockNoteEditor.test.tsx`: locks the mobile trigger contract.
- `src/editor/ios/iosEditorAdapter.ts`: retains the insertion block across native focus loss.
- `src/editor/ios/iosEditorAdapter.test.ts`: proves insertion uses the retained pre-blur block.
- `src/editor/ios/bridge.ts` and tests: restore the protocol-v3 baseline; no new protocol version is needed.
- `scripts/sync-ios-editor.mjs`: remains the sole build/sync path.

### Native iOS editor (`Chorai_IOS_Frontend`)

- `ArcNote/CardEditor/CardEditorInlineImageSource.swift`: new source chooser modifier and camera picker wrapper.
- `ArcNote/CardEditor/CardEditorGlassSurface.swift`: new accessibility-aware shared glass surface.
- `ArcNote/NewNoteView.swift`: source state, camera authorization, conversion, upload guard, and insertion.
- `ArcNote/CardEditor/CardEditorShell.swift`: progress/message presentation and deterministic fixture.
- `ArcNote/CardEditor/CardEditorBackground.swift`: glass writing plane and image layering.
- `ArcNote/CardEditor/CardEditorFormattingBar.swift`: glass keyboard toolbar.
- `ArcNote/CardEditor/CardEditorMetadataRows.swift`: compact Add Tag control.
- `ArcNote/CardEditor/CardMetadataPresentation.swift`: tag capsule with an optional leading symbol.
- `ArcNote/Info.plist`: accurate Photos and Camera purpose strings.
- `ArcNote.xcodeproj/project.pbxproj`: app-target membership for two focused new files.
- `Packages/BlockNoteEditor/Sources/BlockNoteEditor/Resources/*`: generated embedded runtime.
- `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift`: native route and mutation-order contracts.
- `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`: glass, tag, picker, target-membership, and fixture contracts.
- `ArcNoteUITests/ArcNoteUITests.swift`: source chooser, keyboard, unavailable camera, and visual checks.

---

### Task 1: Restore the Protocol-v3 Embedded Source Baseline on Web `main`

**Files:**
- Modify through existing commits: `../chorai_web_frontend/src/editor/ios/{bridge,iosEditorAdapter,iosSchema}.ts`
- Modify through existing commits: `../chorai_web_frontend/src/editor/ios/{bridge,iosEditorAdapter,iosSchema}.test.ts*`
- Modify through existing commits: `../chorai_web_frontend/src/editor/ios/EmbeddedBlockNoteEditor.tsx`
- Create through existing commits: `../chorai_web_frontend/src/editor/ios/EmbeddedBlockNoteEditor.test.tsx`

**Interfaces:**
- Consumes: released iOS bundle protocol `3` and native `requestCardLink` event.
- Produces: editable web `main` source matching the protocol-v3 bundle already in the iOS repository.

- [ ] **Step 1: Reproduce the source/bundle mismatch**

Run from `../chorai_web_frontend`:

```bash
npm run check:ios-editor
```

Expected: exit 1 with `changed: editor.js` and `changed: manifest.json`.

- [ ] **Step 2: Restore the reviewed source commits onto `main`**

```bash
git cherry-pick 3250298 ec8dc3e
```

Expected: two clean cherry-picks ending with `feat(editor): add card link bridge event`; `stash@{0}` remains present.

- [ ] **Step 3: Verify the restored source and bundle**

```bash
npm test -- src/editor/ios
npm run check:ios-editor
git branch --show-current
git status --short
git stash list -1
```

Expected: Vitest passes, resource check reports no drift, branch is `main`, status is clean, and the preserved stash is still listed.

### Task 2: Remove Native Slash Commands and Retain the Image Insertion Anchor

**Files:**
- Modify: `../chorai_web_frontend/src/editor/ios/EmbeddedBlockNoteEditor.test.tsx`
- Modify: `../chorai_web_frontend/src/editor/ios/EmbeddedBlockNoteEditor.tsx`
- Modify: `../chorai_web_frontend/src/editor/ios/iosEditorAdapter.test.ts`
- Modify: `../chorai_web_frontend/src/editor/ios/iosEditorAdapter.ts`
- Generate: `Packages/BlockNoteEditor/Sources/BlockNoteEditor/Resources/{editor.js,manifest.json}`

**Interfaces:**
- Consumes: `createCardLinkSuggestionItems(runtime.requestCardLink)` and `IOSBridgeEditor.blur()/insertImage(url, alt)`.
- Produces: one native suggestion trigger (`@`) and `lastInsertionBlockID: string | null` retained before blur.

- [ ] **Step 1: Write the failing mobile-trigger test**

Add to `EmbeddedBlockNoteEditor.test.tsx`:

```tsx
import { readFileSync } from 'node:fs';

it('exposes only the card-link trigger in the native editor', () => {
  const source = readFileSync(
    new URL('./EmbeddedBlockNoteEditor.tsx', import.meta.url),
    'utf8',
  );
  expect(source).toContain('triggerCharacter="@"');
  expect(source).not.toContain('triggerCharacter="/"');
  expect(source).not.toContain('getDefaultReactSlashMenuItems');
  expect(source).not.toContain('slashMenuKeys');
});
```

- [ ] **Step 2: Write the failing retained-anchor test**

Add to `iosEditorAdapter.test.ts`:

```ts
it('inserts an image after the block retained before native blur', () => {
  const editor = createEditor([
    { id: 'first', type: 'paragraph', content: 'First' },
    { id: 'second', type: 'paragraph', content: 'Second' },
  ]);
  const adapter = createAdapter(editor);
  editor.setTextCursorPosition(editor.document[0], 'end');
  adapter.blur();
  editor.setTextCursorPosition(editor.document[1], 'end');
  adapter.insertImage('https://example.com/retained.png', 'Retained');
  expect(editor.document.map((block) => block.type)).toEqual([
    'paragraph', 'image', 'paragraph',
  ]);
});
```

- [ ] **Step 3: Verify RED**

```bash
npm test -- src/editor/ios/EmbeddedBlockNoteEditor.test.tsx src/editor/ios/iosEditorAdapter.test.ts
```

Expected: the trigger test finds `/`, and the image appears after the second paragraph.

- [ ] **Step 4: Remove only the slash controller**

Delete `getDefaultReactSlashMenuItems`, `slashMenuKeys`, `getSlashMenuItems`, and the `/` controller. Keep this exact child and keep `slashMenu={false}`:

```tsx
{editable && (
  <SuggestionMenuController
    triggerCharacter="@"
    getItems={getCardLinkMenuItems}
  />
)}
```

- [ ] **Step 5: Retain a supported insertion block before blur**

Add inside `createIOSBridgeEditorAdapter`:

```ts
let lastInsertionBlockID: string | null = null;

const isSupportedInlineBlock = (block: typeof iosSchema.Block) => (
  iosSchema.blockSchema[block.type].content === 'inline'
  && toSelectionBlockType(block) !== 'unsupported'
);

const retainInsertionBlock = () => {
  try {
    const block = editor.getTextCursorPosition().block;
    lastInsertionBlockID = isSupportedInlineBlock(block) ? block.id : null;
  } catch {
    lastInsertionBlockID = null;
  }
};

const retainedInsertionBlock = () => {
  const retained = lastInsertionBlockID
    ? editor.document.find((block) => block.id === lastInsertionBlockID)
    : undefined;
  if (retained && isSupportedInlineBlock(retained)) return retained;
  try {
    const current = editor.getTextCursorPosition().block;
    return isSupportedInlineBlock(current) ? current : null;
  } catch {
    return null;
  }
};
```

Reset the ID at the start of `initialize`; call `retainInsertionBlock()` before `editor.blur()` and at the start of `selectionState()`. Replace image insertion with:

```ts
insertImage(url, alt) {
  const currentBlock = retainedInsertionBlock();
  if (!currentBlock) return;
  editor.insertBlocks([{
    type: 'image',
    props: { url, name: alt, showPreview: true },
  }], currentBlock, 'after');
},
```

- [ ] **Step 6: Verify GREEN and commit web source**

```bash
npm test -- src/editor/ios
git add src/editor/ios/EmbeddedBlockNoteEditor.tsx src/editor/ios/EmbeddedBlockNoteEditor.test.tsx src/editor/ios/iosEditorAdapter.ts src/editor/ios/iosEditorAdapter.test.ts
git commit -m "fix(editor): use native mobile command surface"
```

Expected: every embedded iOS editor test passes before the commit.

- [ ] **Step 7: Regenerate and commit the native bundle**

Run from `../chorai_web_frontend`:

```bash
npm run build:ios-editor
npm run check:ios-editor
```

Run from `Chorai_IOS_Frontend`:

```bash
swift test --package-path Packages/BlockNoteEditor
git add Packages/BlockNoteEditor/Sources/BlockNoteEditor/Resources
git commit -m "chore(editor): sync native mobile editor bundle"
```

Expected: no resource drift, all package tests pass, and the iOS commit contains generated resources only.

### Task 3: Add the Native Image Source Chooser and Camera Wrapper

**Files:**
- Create: `ArcNote/CardEditor/CardEditorInlineImageSource.swift`
- Modify: `ArcNote.xcodeproj/project.pbxproj`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`

**Interfaces:**
- Produces: `CardEditorInlineImageSource.photoLibrary/.camera`.
- Produces: `View.cardEditorInlineImageSourceDialog(isPresented:isCameraAvailable:onSelect:)`.
- Produces: `CardEditorCameraPicker(onCapture:onCancel:)` returning one `UIImage` or cancellation.

- [ ] **Step 1: Write the failing source and target-membership test**

Add `CardEditorInlineImageSource.swift` to `cardEditorFiles` and add:

```swift
func testInlineImageSourceUIIsNativeAndCameraSafe() throws {
    let fileURL = Self.repositoryRoot.appendingPathComponent(
        "ArcNote/CardEditor/CardEditorInlineImageSource.swift"
    )
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        XCTFail("Missing CardEditorInlineImageSource.swift")
        return
    }
    let source = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertTrue(source.contains("enum CardEditorInlineImageSource"))
    XCTAssertTrue(source.contains("case photoLibrary"))
    XCTAssertTrue(source.contains("case camera"))
    XCTAssertTrue(source.contains("confirmationDialog("))
    XCTAssertTrue(source.contains("Take Photo — Unavailable on this device"))
    XCTAssertTrue(source.contains(".disabled(!isCameraAvailable)"))
    XCTAssertTrue(source.contains("UIImagePickerController.SourceType.camera"))
    XCTAssertTrue(source.contains("imagePickerControllerDidCancel"))
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests/testInlineImageSourceUIIsNativeAndCameraSafe
```

Expected: FAIL with `Missing CardEditorInlineImageSource.swift`.

- [ ] **Step 3: Create the source chooser and camera wrapper**

Create `CardEditorInlineImageSource.swift`:

```swift
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CardEditorInlineImageSource: Equatable {
    case photoLibrary
    case camera
}

private struct CardEditorInlineImageSourceDialog: ViewModifier {
    @Binding var isPresented: Bool
    let isCameraAvailable: Bool
    let onSelect: (CardEditorInlineImageSource) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Insert Body Image",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button {
                onSelect(.photoLibrary)
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("cardEditorInlineImagePhotoLibrary")

            Button {
                onSelect(.camera)
            } label: {
                Label(
                    isCameraAvailable
                        ? "Take Photo"
                        : "Take Photo — Unavailable on this device",
                    systemImage: "camera"
                )
            }
            .disabled(!isCameraAvailable)
            .accessibilityIdentifier("cardEditorInlineImageCamera")

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a source for the image in this note.")
        }
    }
}

extension View {
    func cardEditorInlineImageSourceDialog(
        isPresented: Binding<Bool>,
        isCameraAvailable: Bool,
        onSelect: @escaping (CardEditorInlineImageSource) -> Void
    ) -> some View {
        modifier(CardEditorInlineImageSourceDialog(
            isPresented: isPresented,
            isCameraAvailable: isCameraAvailable,
            onSelect: onSelect
        ))
    }
}

struct CardEditorCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.SourceType.camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject,
        UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(
            onCapture: @escaping (UIImage) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
```

- [ ] **Step 4: Add the new file to the app target**

Use these unused project identifiers:

```text
C0DEF3002F80000100000019  CardEditorInlineImageSource.swift in Sources
C0DEF3002F80000100000029  CardEditorInlineImageSource.swift file reference
```

Add the file reference to the `CardEditor` group and the build file to `1B48AE2D2E30967F0090CF86 /* Sources */`.

- [ ] **Step 5: Verify GREEN and compile**

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests/testInlineImageSourceUIIsNativeAndCameraSafe
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-derived
```

Expected: focused test passes and build ends with `** BUILD SUCCEEDED **`.

### Task 4: Route Photos and Camera Through One Guarded Inline Upload Flow

**Files:**
- Modify: `ArcNote/NewNoteView.swift`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift`
- Modify: `ArcNote/Info.plist`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift`

**Interfaces:**
- Consumes: `CardEditorInlineImageSource`, `CardEditorCameraPicker`, `CardEditingImage`, `CardEditingStore.uploadInlineImage`, and `BlockNoteCardEditorModel.insertImage`.
- Produces: `presentInlineImageSourceOptions()`, `selectInlineImageSource(_:)`, `requestInlineImageCamera()`, `beginInlineImageProcessing(_:)`, and shell `isInlineImageProcessing`.

- [ ] **Step 1: Write failing source-routing and plist tests**

Replace the old inline-picker assertions with:

```swift
XCTAssertTrue(source.contains("showInlineImageSourceDialog"))
XCTAssertTrue(source.contains("showInlineImagePhotoPicker"))
XCTAssertTrue(source.contains("showInlineImageCamera"))
XCTAssertTrue(source.contains("UIImagePickerController.isSourceTypeAvailable(.camera)"))
XCTAssertTrue(source.contains("AVCaptureDevice.authorizationStatus(for: .video)"))
XCTAssertTrue(source.contains("AVCaptureDevice.requestAccess(for: .video)"))
XCTAssertTrue(source.contains("UIApplication.openSettingsURLString"))
XCTAssertFalse(source.contains("showInlineImagePicker"))
```

Require both media handlers to use one helper and upload before insertion:

```swift
let library = try XCTUnwrap(Self.functionBody(
    in: source, signature: "func handleSelectedInlineImage("
))
let camera = try XCTUnwrap(Self.functionBody(
    in: source, signature: "func handleCapturedInlineImage("
))
let common = try XCTUnwrap(Self.functionBody(
    in: source, signature: "func beginInlineImageProcessing("
))
XCTAssertTrue(library.contains("beginInlineImageProcessing"))
XCTAssertTrue(camera.contains("beginInlineImageProcessing"))
let upload = try XCTUnwrap(common.range(of: "editingStore.uploadInlineImage("))
let insert = try XCTUnwrap(common.range(of: "bodyModel.insertImage("))
XCTAssertLessThan(upload.lowerBound, insert.lowerBound)
XCTAssertTrue(common.contains("guard !isProcessingInlineImage"))
```

Add this direct plist read (the test class has no generic `source(at:)` helper):

```swift
let info = try String(
    contentsOf: Self.repositoryRoot.appendingPathComponent("ArcNote/Info.plist"),
    encoding: .utf8
)
XCTAssertTrue(info.contains("<key>NSCameraUsageDescription</key>"))
XCTAssertTrue(info.contains("take a photo for a note"))
XCTAssertTrue(info.contains("profile and note images"))
```

- [ ] **Step 2: Verify RED**

```bash
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests
```

Expected: failures for missing source dialog, camera route, shared helper, and privacy copy.

- [ ] **Step 3: Add native acquisition state and modifiers**

Add `import AVFoundation` and `import UIKit`. Replace the old inline picker state with:

```swift
@State private var showInlineImageSourceDialog = false
@State private var showInlineImagePhotoPicker = false
@State private var showInlineImageCamera = false
@State private var showCameraSettingsAlert = false
@State private var selectedInlineImagePhoto: PhotosPickerItem?
@State private var isProcessingInlineImage = false
```

Include `isProcessingInlineImage` in `isBusy`, pass it to `CardEditorShell`, and add:

```swift
.cardEditorInlineImageSourceDialog(
    isPresented: $showInlineImageSourceDialog,
    isCameraAvailable: inlineImageCameraAvailable,
    onSelect: selectInlineImageSource
)
.photosPicker(
    isPresented: $showInlineImagePhotoPicker,
    selection: $selectedInlineImagePhoto,
    matching: .images
)
.fullScreenCover(isPresented: $showInlineImageCamera) {
    CardEditorCameraPicker(
        onCapture: handleCapturedInlineImage,
        onCancel: { showInlineImageCamera = false }
    )
    .ignoresSafeArea()
}
.alert("Camera Access Needed", isPresented: $showCameraSettingsAlert) {
    Button("Cancel", role: .cancel) {}
    Button("Open Settings", action: openCameraSettings)
} message: {
    Text("Allow camera access in Settings to take a photo for this note.")
}
```

Change `configureNativeActions` to call `presentInlineImageSourceOptions()`.

- [ ] **Step 4: Add source selection and camera permission methods**

```swift
private var inlineImageCameraAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
}

private func presentInlineImageSourceOptions() {
    guard !isBusy else { return }
    bodyModel.dismissKeyboard()
    showInlineImageSourceDialog = true
}

private func selectInlineImageSource(_ source: CardEditorInlineImageSource) {
    switch source {
    case .photoLibrary:
        showInlineImagePhotoPicker = true
    case .camera:
        requestInlineImageCamera()
    }
}

private func requestInlineImageCamera() {
    guard inlineImageCameraAvailable else {
        saveMessage = "Camera isn't available on this device."
        retryAction = nil
        return
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
        showInlineImageCamera = true
    case .notDetermined:
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                showInlineImageCamera = true
            } else {
                saveMessage = "Camera access is off. You can enable it in Settings."
                showCameraSettingsAlert = true
            }
        }
    case .denied, .restricted:
        saveMessage = "Camera access is off. You can enable it in Settings."
        showCameraSettingsAlert = true
    @unknown default:
        saveMessage = "Camera isn't available right now."
        retryAction = nil
    }
}

private func openCameraSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
```

- [ ] **Step 5: Normalize both media sources into one upload helper**

```swift
private func handleSelectedInlineImage(_ item: PhotosPickerItem?) {
    guard let item else { return }
    selectedInlineImagePhoto = nil
    beginInlineImageProcessing {
        try await cardEditingImage(from: item, stem: "inline-image")
    }
}

private func handleCapturedInlineImage(_ image: UIImage) {
    showInlineImageCamera = false
    beginInlineImageProcessing {
        guard let data = image.jpegData(compressionQuality: 0.9),
              !data.isEmpty else {
            throw CardEditorSessionError.imageUnavailable
        }
        return CardEditingImage(
            data: data,
            filename: "inline-camera.jpg",
            mimeType: "image/jpeg"
        )
    }
}

private func beginInlineImageProcessing(
    _ makeImage: @escaping () async throws -> CardEditingImage
) {
    guard !isProcessingInlineImage else { return }
    isProcessingInlineImage = true
    saveMessage = nil
    retryAction = nil
    Task {
        defer { isProcessingInlineImage = false }
        do {
            let image = try await makeImage()
            let uploaded = try await editingStore.uploadInlineImage(image)
            bodyModel.insertImage(
                url: uploaded.url.absoluteString,
                alt: "Inline image"
            )
        } catch {
            saveMessage = "Couldn't add that image. Your draft is unchanged."
            retryAction = nil
        }
    }
}
```

Do not modify `handleSelectedBackgroundPhoto`; it remains photo-library-only and calls `stageBackground`.

- [ ] **Step 6: Show non-covering progress and errors even without Retry**

Add `isInlineImageProcessing: Bool = false` to `CardEditorShell`. Render these before the optional save/retry button and remove message rendering from `inlineSaveAction`:

```swift
if isInlineImageProcessing {
    Label("Adding image…", systemImage: "photo.badge.arrow.down")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white.opacity(0.82))
        .accessibilityIdentifier("cardEditorInlineImageProgress")
}
if let saveMessage {
    Text(saveMessage)
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.82))
        .accessibilityIdentifier("cardEditorSaveMessage")
}
if let onSave {
    inlineSaveAction(onSave)
}
```

- [ ] **Step 7: Add accurate purpose strings**

```xml
<key>NSCameraUsageDescription</key>
<string>Chorai uses your camera when you choose to take a photo for a note.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Chorai uses your photo library when you choose profile and note images.</string>
```

- [ ] **Step 8: Verify GREEN and commit the functional flow**

```bash
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-derived
git add ArcNote/NewNoteView.swift ArcNote/CardEditor/CardEditorInlineImageSource.swift ArcNote/CardEditor/CardEditorShell.swift ArcNote/Info.plist ArcNote.xcodeproj/project.pbxproj Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift
git commit -m "feat(editor): add native inline image sources"
```

Expected: focused contracts pass and the simulator app target builds before commit.

### Task 5: Build the Liquid Glass Writing Plane and Compact Tag Visuals

**Files:**
- Create: `ArcNote/CardEditor/CardEditorGlassSurface.swift`
- Modify: `ArcNote.xcodeproj/project.pbxproj`
- Modify: `ArcNote/CardEditor/CardEditorBackground.swift`
- Modify: `ArcNote/CardEditor/CardEditorFormattingBar.swift`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift`
- Modify: `ArcNote/CardEditor/CardEditorMetadataRows.swift`
- Modify: `ArcNote/CardEditor/CardMetadataPresentation.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`

**Interfaces:**
- Produces: `CardEditorGlassSurface<SurfaceShape: Shape>(shape:isInteractive:)`.
- Extends: `CardMetadataTagCapsule(tag:showsRemoveIndicator:leadingSystemImage:)` with default `nil`.
- Consumes: Reduce Transparency, Increased Contrast, `ZenVisualTokens`, and iOS 26 `Glass.regular.interactive(_:)`.

- [ ] **Step 1: Write failing glass and compact-tag contracts**

Add `CardEditorGlassSurface.swift` to `cardEditorFiles`. Guard its existence as in Task 3, then assert:

```swift
XCTAssertTrue(glass.contains("if #available(iOS 26.0, *)"))
XCTAssertTrue(glass.contains(".glassEffect(.regular.interactive(isInteractive), in: shape)"))
XCTAssertTrue(glass.contains("shape.fill(.ultraThinMaterial)"))
XCTAssertTrue(glass.contains("@Environment(\\.accessibilityReduceTransparency)"))
XCTAssertTrue(glass.contains("@Environment(\\.colorSchemeContrast)"))
XCTAssertTrue(background.contains("CardEditorGlassSurface("))
XCTAssertTrue(formatting.contains("CardEditorGlassSurface("))
XCTAssertTrue(shell.contains("CardEditorGlassSurface(shape: Circle()"))
```

Add the `metadata` assertions to `testMetadataRowsShareViewStylingAndKeepLinksStatic`, and add the `presentation` assertions to `testAppTargetOwnsTheSixFocusedCardEditorFiles`, where those variables already exist:

```swift
XCTAssertTrue(metadata.contains("leadingSystemImage: \"plus\""))
XCTAssertFalse(metadata.contains("ZenVisualTokens.accent.opacity(0.16)"))
XCTAssertTrue(presentation.contains("let leadingSystemImage: String?"))
XCTAssertTrue(presentation.contains("if let leadingSystemImage"))
```

- [ ] **Step 2: Verify RED**

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
```

Expected: failures for the absent glass file, old solid surfaces, and bespoke Add Tag capsule.

- [ ] **Step 3: Create the shared material surface**

Create `CardEditorGlassSurface.swift`:

```swift
import SwiftUI

struct CardEditorGlassSurface<SurfaceShape: Shape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let shape: SurfaceShape
    let isInteractive: Bool

    init(shape: SurfaceShape, isInteractive: Bool = false) {
        self.shape = shape
        self.isInteractive = isInteractive
    }

    var body: some View {
        ZStack {
            material
            shape
                .stroke(
                    contrast == .increased
                        ? Color.white.opacity(0.34)
                        : Color.white.opacity(0.16),
                    lineWidth: contrast == .increased ? 1.4 : 0.8
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var material: some View {
        if reduceTransparency {
            shape.fill(ZenVisualTokens.background.opacity(0.97))
        } else if #available(iOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(.regular.interactive(isInteractive), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
```

- [ ] **Step 4: Place glass behind the transparent BlockNote body**

Keep `content()` padding and clipping. Replace the old solid background layer with:

```swift
ZStack {
    if background != .none {
        backgroundImage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }

    CardEditorGlassSurface(
        shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
        isInteractive: true
    )

    if background != .none {
        Color.black
            .opacity(veilOpacity)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
```

Use veil opacity `0.58` for Reduce Transparency/increased contrast and `0.42` otherwise. Remove the duplicate outer border because `CardEditorGlassSurface` owns the edge.

- [ ] **Step 5: Apply the material family to toolbar and floating controls**

Replace the formatting bar background with:

```swift
.background {
    CardEditorGlassSurface(shape: Rectangle(), isInteractive: true)
}
```

Replace `CardEditorFloatingControls.controlBackground` with:

```swift
CardEditorGlassSurface(shape: Circle(), isInteractive: true)
```

Keep all existing 44-point frames, selection fills, identifiers, and Reduce Motion behavior.

- [ ] **Step 6: Reuse the exact tag capsule for Add Tag**

Add `let leadingSystemImage: String? = nil` to `CardMetadataTagCapsule` and render before its text:

```swift
if let leadingSystemImage {
    Image(systemName: leadingSystemImage)
        .font(.system(size: 10, weight: .semibold))
}
```

Replace the Add Tag label/background/overlay with:

```swift
CardMetadataTagCapsule(
    tag: "Tag",
    showsRemoveIndicator: false,
    leadingSystemImage: "plus"
)
```

Keep the enclosing button's `.frame(minWidth: 44, minHeight: 44)`, `contentShape`, VoiceOver label/hint, and `cardEditorAddTag` identifier.

- [ ] **Step 7: Add the glass file to the app target**

Use:

```text
C0DEF3002F8000010000001A  CardEditorGlassSurface.swift in Sources
C0DEF3002F8000010000002A  CardEditorGlassSurface.swift file reference
```

Add it to the CardEditor group and ArcNote Sources phase.

- [ ] **Step 8: Verify GREEN and commit**

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-derived
git add ArcNote/CardEditor/CardEditorGlassSurface.swift ArcNote/CardEditor/CardEditorBackground.swift ArcNote/CardEditor/CardEditorFormattingBar.swift ArcNote/CardEditor/CardEditorShell.swift ArcNote/CardEditor/CardEditorMetadataRows.swift ArcNote/CardEditor/CardMetadataPresentation.swift ArcNote.xcodeproj/project.pbxproj Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift
git commit -m "feat(editor): add liquid glass writing surface"
```

Expected: source contracts pass and the app builds before commit.

### Task 6: Expose the Source Flow in the Deterministic Native Fixture

**Files:**
- Modify: `ArcNote/CardEditor/CardEditorShell.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`

**Interfaces:**
- Produces: fixture-only `CardEditorShellFixtureActionRouter.requestInlineImage()`.
- Produces: deterministic source dialog with `isCameraAvailable: false`.
- Consumes: existing `keyboard` fixture and `cardEditorFormatInlineImage`.

- [ ] **Step 1: Write failing XCUITests**

Add:

```swift
func testCardEditorInlineImageChooserDismissesKeyboardAndShowsSources() {
    launchCardEditorFixture(mode: "keyboard")
    let body = waitFor("cardEditorBodyWebView")
    body.coordinate(
        withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)
    ).tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
    waitForButton("cardEditorFormatInlineImage").tap()
    waitForElementToDisappear(app.keyboards.firstMatch)
    waitForMissing("cardEditorFormattingBar")
    XCTAssertTrue(app.buttons["Photo Library"].waitForExistence(timeout: 10))
    let camera = app.buttons["Take Photo — Unavailable on this device"]
    XCTAssertTrue(camera.exists)
    XCTAssertFalse(camera.isEnabled)
    captureVisual("card-editor-inline-image-sources")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(waitFor("cardEditorBodyWebView").exists)
}

func testCardEditorSlashTypesWithoutOpeningCommandMenu() {
    launchCardEditorFixture(mode: "empty")
    let body = waitFor("cardEditorBodyWebView")
    body.tap()
    body.typeText("/")
    XCTAssertFalse(app.staticTexts["Paragraph"].waitForExistence(timeout: 1))
    XCTAssertTrue(waitFor("cardEditorBodyWebView").exists)
}
```

- [ ] **Step 2: Verify chooser test RED**

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-ui-tests -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorInlineImageChooserDismissesKeyboardAndShowsSources
```

Expected: FAIL because the fixture's inline-image callback is empty.

- [ ] **Step 3: Add a fixture-only action router**

Inside `#if DEBUG`, add:

```swift
@MainActor
private final class CardEditorShellFixtureActionRouter: ObservableObject {
    var onRequestInlineImage: () -> Void = {}
    func requestInlineImage() { onRequestInlineImage() }
}
```

Add `@StateObject private var actionRouter` and `@State private var showInlineImageSourceDialog = false`. In `init`, create the router before the model:

```swift
let actionRouter = CardEditorShellFixtureActionRouter()
_actionRouter = StateObject(wrappedValue: actionRouter)
let fixtureModel = BlockNoteCardEditorModel(
    document: Self.document(for: mode),
    initialContentHeight: mode == .keyboard ? 640 : 248,
    initialSelection: initialSelection,
    initiallyFocused: false,
    initialCompatibilityBlock: blockedCode,
    onRequestInlineImage: actionRouter.requestInlineImage
)
```

Add to the fixture root:

```swift
.cardEditorInlineImageSourceDialog(
    isPresented: $showInlineImageSourceDialog,
    isCameraAvailable: false,
    onSelect: { _ in }
)
.onAppear {
    actionRouter.onRequestInlineImage = {
        bodyModel.dismissKeyboard()
        showInlineImageSourceDialog = true
    }
}
```

- [ ] **Step 4: Add fixture source assertions and verify GREEN**

Require `CardEditorShellFixtureActionRouter`, `onRequestInlineImage: actionRouter.requestInlineImage`, `.cardEditorInlineImageSourceDialog`, `bodyModel.dismissKeyboard()`, and `isCameraAvailable: false` in the fixture contract. Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests/testDebugAppRouteExposesDeterministicCardEditorFixture
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-ui-tests -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorInlineImageChooserDismissesKeyboardAndShowsSources -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorSlashTypesWithoutOpeningCommandMenu
```

Expected: source contract and both XCUITests pass.

- [ ] **Step 5: Commit fixture coverage**

```bash
git add ArcNote/CardEditor/CardEditorShell.swift ArcNoteUITests/ArcNoteUITests.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift
git commit -m "test(editor): cover native image source flow"
```

### Task 7: Full Verification, Simulator Launch, and Requirement Audit

**Files:**
- Verify only; modify implementation files only when a failing requirement identifies a concrete defect.

**Interfaces:**
- Consumes: both `main` branches, generated protocol-v3 resources, native fixtures, and simulator `86CD9628-7C27-4799-B237-3EEC82E7E9B5`.
- Produces: test evidence, dark/light screenshots under `/tmp/chorai-native-editor-liquid-glass-*.png`, and requirement-by-requirement completion evidence.

- [ ] **Step 1: Verify the complete embedded editor**

Run from `../chorai_web_frontend`:

```bash
npm test -- src/editor/ios
npm run check:ios-editor
git status --short
```

Expected: all tests pass, resource check reports no drift, and web `main` is clean.

- [ ] **Step 2: Run both Swift package suites**

```bash
swift test --package-path Packages/BlockNoteEditor
swift test --package-path Packages/CoreFlow
```

Expected: both suites pass with zero failures.

- [ ] **Step 3: Run focused editor UI regressions**

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-ui-tests -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorShellEmptyHierarchyIsHeaderlessAndAccessible -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorShellPopulatedLinksAreCollapsedThenExpanded -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorFormattingBarKeepsDismissFixedAndReflectsSelection -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorInlineImageChooserDismissesKeyboardAndShowsSources -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorSlashTypesWithoutOpeningCommandMenu -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorLongTagStaysInsideReadableWidth -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorShellSupportsAccessibilityTextSize
```

Expected: all seven UI tests pass.

- [ ] **Step 4: Build, install, and launch the native fixture**

```bash
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-ios-derived
xcrun simctl install 86CD9628-7C27-4799-B237-3EEC82E7E9B5 /tmp/chorai-ios-derived/Build/Products/Debug-iphonesimulator/ArcNote.app
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=keyboard xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 appearance dark
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-native-editor-liquid-glass-dark.png
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 appearance light
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-native-editor-liquid-glass-light.png
```

Expected: build succeeds, the native app opens directly into the editor fixture with no browser chrome, and both screenshots exist.

- [ ] **Step 5: Inspect visual and accessibility behavior**

Inspect both appearance screenshots and the live simulator for one glass writing plane without a nested opaque web card, transparent BlockNote canvas, readable text, compact Add Tag matching other tags, 44-point hit regions, glass toolbar/floating controls, both source choices, disabled unavailable camera, and no slash menu. Enable Reduce Transparency in Simulator Accessibility settings once and confirm the writing plane becomes opaque without changing layout or readability. Restore simulator appearance to dark after the comparison.

- [ ] **Step 6: Validate camera capture on physical hardware**

On a connected iPhone, run the Debug build, open a note, tap Insert Body Image → Take Photo, grant access, capture and accept a photo, wait for progress to clear, and confirm the image appears after the pre-sheet insertion block. Repeat with camera permission denied and confirm the draft remains visible with Open Settings available.

Expected: both capture and denial paths satisfy the design. If no physical device is connected, report this single verification gap explicitly and do not claim camera end-to-end completion.

- [ ] **Step 7: Audit acceptance criteria and repository state**

Run in both repositories:

```bash
git status --short
git log -8 --oneline
git diff origin/main...HEAD --stat
```

Map evidence to slash behavior, `@` retention, toolbar availability, Liquid Glass/fallback, compact tag/hit target, both body-image sources, unchanged background flow, recoverable failures, simulator build/launch, and physical camera capture. Do not mark the goal complete while any evidence is missing.
