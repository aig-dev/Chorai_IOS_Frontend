# Native Editor Liquid Glass and Inline Image Design

## Status

Design approved in conversation on 2026-07-17. This document is the review checkpoint before implementation planning.

## Context

The iOS note editor currently embeds BlockNote inside a native SwiftUI editing flow, but several interactions still expose desktop-web assumptions or do not feel integrated with iOS:

- typing `/` opens BlockNote's command menu even though the mobile editor is intended to rely on the formatting bar above the keyboard;
- the visible Add Tag control is substantially larger than the surrounding tags;
- the writing surface reads as an opaque card rather than text written on a floating Liquid Glass layer;
- inserting an image into the note body opens the photo library directly and offers no camera route.

The product is a native iOS app. The embedded web editor remains an implementation detail used only for rich-text body editing; it must not define the visual shell or mobile interaction model.

## Goals

- Make the editor feel native to iOS and visually coherent with Liquid Glass.
- Make the keyboard formatting bar the sole command surface for mobile editing.
- Bring Add Tag into the same visual rhythm as existing tags without sacrificing touch accessibility.
- Let users insert a body image from either the photo library or the camera.
- Preserve the current draft through cancellation, permission denial, upload failure, and unavailable-camera states.

## Scope Boundaries

This design applies to the native iOS editor in `Chorai_IOS_Frontend`.

The BlockNote body bundle is authored in the sibling source file `chorai_web_frontend/src/editor/ios/EmbeddedBlockNoteEditor.tsx` and synchronized into `Packages/BlockNoteEditor` by `chorai_web_frontend/scripts/sync-ios-editor.mjs`. Changes there are changes to the native app's embedded editor runtime, not a redesign of the user-facing web editor.

The new image-source choice applies only to **Insert Body Image**. The existing background-image action remains photo-library-only and retains its current upload and presentation behavior.

## Architecture

Use a hybrid native-shell architecture:

- SwiftUI owns the editor chrome, Liquid Glass surface, metadata and tag controls, keyboard formatting bar, image-source sheet, permissions, media acquisition, progress, and recoverable errors.
- BlockNote inside `WKWebView` owns rich-text body state, selection, formatting execution, `@` card-link suggestions, and insertion of the final uploaded image URL.
- The bridge remains command-based: native UI requests an editor action; the embedded editor reports focus, selection, state, and command results.

This boundary keeps camera and Photos APIs in native code, where permission handling and device capability checks are reliable, while preserving BlockNote's existing document format and upload URL insertion flow.

## Mobile Command Behavior

The `/` suggestion controller is disabled in the iOS embedded editor. Typing `/` inserts an ordinary slash character and does not open a command menu.

The keyboard formatting bar remains the discoverable command surface and continues to expose the supported mobile actions, including body-image insertion. The `@` suggestion controller remains enabled because linking another card is content entry rather than a formatting command.

This behavior is scoped to the native embedded bundle; desktop/web BlockNote behavior is unchanged.

## Liquid Glass Writing Surface

The editor should feel like writing directly on a floating pane of glass rather than inside a conventional opaque card.

### Visual treatment

- On iOS 26 and later, use the system Liquid Glass APIs (`glassEffect` and, where multiple neighboring glass elements need coordinated rendering, `GlassEffectContainer`).
- Use a regular, subtly interactive glass treatment for the writing plane. Avoid strong tinting that reduces text contrast or makes the surface resemble a colored card.
- Keep the current generous corner radius, but soften the border into a restrained highlight that catches the surface edge rather than drawing a box.
- Let the underlying editor background contribute color and depth through the material. The surface may use a very light tonal veil when needed for legibility, but not a solid fill.
- Keep the transparent BlockNote canvas flush with the native glass plane so the text appears to sit on the glass. Do not add a second nested web card or visible web background.
- Match the formatting bar and compact metadata controls to the same material family so the editor reads as one native composition.

### Compatibility and accessibility

- On iOS 16 through iOS 25, fall back to `ultraThinMaterial` plus the existing restrained edge highlight.
- When Reduce Transparency is enabled, use a sufficiently opaque system background instead of simulated translucency.
- When Increase Contrast or a high-contrast appearance is active, strengthen the edge and foreground contrast without changing layout.
- Preserve Dynamic Type, VoiceOver order, and readable text contrast in both light and dark appearances.
- Glass is decorative; focus, selection, typing, and saving must not depend on an animation or transparency effect.

## Tag Controls

Existing tags and Add Tag share one compact visual system:

- Render the visible Add Tag capsule at approximately the same height, corner radius, border weight, typography, and horizontal padding as a normal tag (target visible height: about 24 points).
- Use a compact plus icon and label rather than the current full-height button treatment.
- Retain at least a 44-by-44-point invisible interactive region around every tag action, including Add Tag and tag removal.
- Keep wrapping behavior stable for long tag sets and long localized labels.
- Provide explicit VoiceOver labels and hints; the compact visible treatment must not make the control ambiguous.

## Insert Body Image Flow

### Entry

Tapping the body-image button in the keyboard formatting bar:

1. asks the embedded editor to retain the current BlockNote selection or insertion anchor before focus is cleared;
2. dismisses the keyboard cleanly;
3. presents a native glass-styled source sheet with **Photo Library** and **Take Photo**;
4. leaves the background-image flow untouched.

The source sheet must remain recognizably native and use system presentation semantics. It should not be implemented inside the `WKWebView`.

### Photo Library

- Present `PhotosPicker` for a single image.
- Convert the selected item into `CardEditingImage` with data, filename, and MIME type.
- Reuse the existing inline-image upload path.
- After a successful upload, send the returned URL through the BlockNote bridge and insert it at the preserved body insertion point.

### Camera

- Keep **Take Photo** visible in the source sheet.
- On a physical device with camera support, present a native `UIImagePickerController` configured with `.camera` through a SwiftUI wrapper.
- Convert the captured image into the same `CardEditingImage` representation and send it through the same upload and insertion path as a library image.
- On the simulator or a device where `.camera` is unavailable, keep the row visible but disabled and label it as unavailable on this device; never attempt to present an unsupported picker.
- Check camera authorization before presenting capture. A first use requests access; a denied or restricted result stays in the editor and offers recoverable guidance rather than opening an empty picker.
- Add `NSCameraUsageDescription`. Update `NSPhotoLibraryUsageDescription` so it accurately covers note images as well as profile images.

### State and error handling

The body document is mutated only after upload succeeds and the bridge accepts the final image URL.

- Cancelling the source sheet, photo picker, or camera returns to the unchanged draft.
- Denied or restricted permission produces a recoverable editor-level message and, when appropriate, a route to Settings.
- Invalid image data, conversion failure, upload failure, or bridge insertion failure produces a recoverable message and leaves the draft unchanged.
- The source action is guarded while an inline image is being processed so repeated taps cannot create duplicate uploads or insertions.
- Progress is shown by native editor UI without covering or replacing the draft.
- Focus restoration must not discard the preserved insertion anchor; after completion or cancellation, the user can resume typing normally.

## Data Flow

```text
Formatting bar: Insert Body Image
             |
             v
Native source sheet ---- cancel/unavailable/denied ----> unchanged draft + recoverable feedback
       |                    |
       |                    +---- Photo Library (PhotosPicker)
       +------------------------- Camera (UIImagePickerController)
                                      |
                                      v
                              CardEditingImage
                                      |
                                      v
                         existing inline image upload
                                      |
                         success URL / recoverable error
                                      |
                                      v
                    BlockNote bridge inserts image URL
                                      |
                                      v
                              updated body draft
```

## Testing Strategy

### Embedded editor tests

- Verify typing `/` does not open a suggestion menu and preserves the slash in the document.
- Verify `@` card-link suggestions still open and insert a link.
- Verify the native image insertion bridge still inserts the supplied URL at the intended location.

### Swift and unit tests

- Verify body-image source routing distinguishes photo library and camera while background-image routing is unchanged.
- Verify camera availability controls whether capture can be presented.
- Verify both media sources normalize to the same `CardEditingImage` upload input.
- Verify cancellation and all failure branches do not send an insertion command or mutate the body.
- Verify duplicate actions are rejected while an image is processing.

### UI and visual validation

- Extend the native card-editor fixture to open the editor without authentication and exercise the keyboard formatting bar.
- Verify there is no slash command menu in the native fixture.
- Verify Add Tag is visually aligned with tags while its accessibility hit target remains at least 44 points.
- Verify the image button exposes both Photo Library and Take Photo, and that the unavailable-camera state behaves correctly on the simulator.
- Build and launch the app on the iOS simulator, capture the editor in light and dark appearances, and inspect the writing plane, toolbar, tag wrapping, keyboard transition, and Reduce Transparency fallback.
- Complete the final Take Photo end-to-end validation on a physical device because the iOS simulator does not provide a usable camera capture flow.

## Acceptance Criteria

- In the native app, `/` types as text and never opens the BlockNote command menu; `@` linking still works.
- All supported formatting actions remain available from the keyboard formatting bar.
- The editor body visually reads as one native Liquid Glass writing plane on iOS 26, with an accessible material fallback on earlier supported iOS versions.
- Add Tag matches existing tag proportions, and all tag actions retain 44-point minimum hit targets.
- Insert Body Image offers Photo Library and Take Photo; both successful paths reuse the existing upload service and insert the returned URL into the body.
- Background image selection remains photo-library-only.
- Cancellation, denied permissions, unavailable camera, conversion failure, upload failure, and insertion failure preserve the draft and show recoverable feedback.
- The app builds and launches in the native iOS simulator; camera capture is additionally verified on real hardware.

## Non-goals

- No redesign of the desktop or mobile web editor.
- No new backend image endpoint or document schema.
- No camera option for background images.
- No replacement of BlockNote with a native rich-text engine.
- No broad redesign of note metadata, navigation, or save semantics beyond the tag and editor-surface changes described here.
