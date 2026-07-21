# iOS Edit Profile Media Sync Design

## Outcome

The iOS Personal Data screen reads the canonical Go own-profile payload used by
Web, displays both `avatar_url` and `background_url`, stages replacement images,
and persists them through the dedicated multipart profile endpoints when Save
is tapped. The custom back control reliably returns to Settings and discards
unsaved local edits.

The screen keeps the current quiet glass form and dark-violet atmosphere. A
restrained cover-photo surface above the form makes profile background media
visible and editable without turning the page into a second profile viewer.

## Scope

In scope:

- Decode `background_url` from `GET /api/v1/profile/me` and keep the returned
  profile as the single in-memory source of truth.
- Resolve both avatar and background media through
  `APIConfiguration.resourceURLString(_:)` so absolute URLs, API-relative
  uploads, and Local MinIO resource paths render consistently.
- Stage avatar and background selections locally and upload them only after
  Save.
- Upload avatar with `PUT /api/v1/profile/me/avatar`, multipart field
  `avatar`, and background with `PUT /api/v1/profile/me/background`, multipart
  field `background`.
- Preserve the existing text update through `PUT /api/v1/profile/me`.
- Normalize a Go RFC 3339 birthday value to `YYYY-MM-DD` before presenting and
  resubmitting it.
- Give Back and all media controls effective `44 x 44` point targets and clear
  VoiceOver labels.
- Add focused UI regressions for navigation, the empty-background upload
  affordance, profile-media state, and the dedicated background upload route.

Out of scope:

- Backend or Web changes; their current contracts are the reference.
- Profile-background removal; the Go contract currently requires a non-empty
  `background_url` and exposes no delete route.
- Changes to public profile, My Profile, side-menu layout, or Chora profile.
- Camera capture, crop editing, filters, or a new image-processing dependency.

## Root cause

Web already maps `background_url`, resolves stored media safely, and uploads a
background through `/api/v1/profile/me/background`. The iOS Go migration only
mapped `avatar_url`: `UserProfile` has no background property, the editor uses a
static `home_bg`, and `NetworkManager` has no profile-background upload method.
The editor also passes the raw avatar string directly to `URL(string:)`, unlike
working iOS surfaces that canonicalize backend-relative media first.

The edit destination is owned by `SettingsView.navigateToEditProfile`, but the
custom back control tries to dismiss through the legacy `presentationMode`
environment value. Its label is only the intrinsic chevron size and has no
explicit accessibility identity. This leaves the visible navigation source of
truth and the action that tries to close it disconnected, while also making the
control easy to miss physically.

## Data model and API flow

`UserProfile` gains `background: String?`, decoded and encoded as
`background_url`. Existing fields remain the same. The view derives display
URLs at the presentation boundary and does not store a second canonical URL.

Opening the screen performs one `GET /api/v1/profile/me`. When the response
arrives, the view populates text fields and both media previews. Birthday text
uses the leading `YYYY-MM-DD` date when the server returns an RFC 3339 value.

Selecting either image updates a local `UIImage` preview only. Save executes a
deterministic sequence:

1. Upload a staged avatar, if present.
2. Upload a staged background, if present.
3. Update username, bio, city, and optional birthday.
4. Store every returned profile in `UserProfileManager.userProfile`; the final
   text response becomes the canonical state.
5. Close the destination only after the complete sequence succeeds.

Sequential writes avoid racing two profile mutations. A failure stops later
steps, leaves the editor open, shows one concise error, and permits retry. Save
is disabled while the sequence runs. Returning before Save does not issue any
write.

## Background and avatar design

The header remains visually subordinate to the form:

- A continuous 18-point rounded cover surface sits below the title bar and
  above the glass form.
- Existing background media fills the surface with a soft dark gradient for
  legibility. A compact `camera.fill` control sits at the lower trailing edge.
- Without background media, the same surface uses a low-contrast glass fill,
  one fine border, `photo.badge.plus`, and the copy “Add background photo”. The
  whole surface is a button, with a minimum height comfortably above 44 points.
- The 72-point avatar overlaps the lower edge of the cover and keeps a small
  camera badge. The selected local image wins over the remote preview.
- The form moves below the overlapping avatar and remains a single rounded
  glass group. The screen scrolls on compact devices and with larger Dynamic
  Type.

Only SF Symbols are introduced. No synthetic bitmap or custom icon asset is
needed. Material falls back to a quiet opaque violet fill when Reduce
Transparency is enabled. Images are decorative inside separately labelled
buttons, so VoiceOver hears “Change profile photo” and either “Add background
photo” or “Change background photo”.

## Navigation

`SettingsView` passes an explicit close action that sets
`navigateToEditProfile = false`. `EditProfileView` uses that action for both
Back and successful Save; a default environment `dismiss()` fallback keeps
previews and direct embedding usable. The back control is a real SwiftUI
`Button`, has a `44 x 44` frame, the identifier `edit-profile.back`, and the
label “Back”.

This makes the presentation binding the single navigation source of truth and
removes reliance on the deprecated presentation-mode path.

## Errors and privacy

- Do not log actor IDs, profile payloads, tokens, or media URLs.
- JPEG conversion failure produces a local, readable error without a request.
- Network validation and rate-limit failures remain on the screen and can be
  retried.
- A failed remote image load uses the existing avatar asset or empty cover
  treatment without changing stored data.
- Back remains available after errors and discards only local staged edits.

## Test and verification strategy

Implementation follows red-green-refactor:

1. Add a Settings fixture UI test that requires an accessible 44-point Back
   button, taps it, and observes Settings as the destination owner again.
2. Add a fixture UI test that requires the no-background cover upload control
   and verifies its minimum hit target and label.
3. Add profile-contract fixture assertions for `background_url`, canonical
   avatar/background resource URLs, and birthday normalization.
4. Add a live Go smoke test for the background multipart route using an
   in-process JPEG, then restore the prior URL through the JSON background
   endpoint when one exists.
5. Run the focused UI tests, existing profile save/avatar tests, and the full
   relevant UI test class when local prerequisites permit.
6. Build both `ArcNote` and `ArcNote Production` for an iOS Simulator.
7. Inspect the real Simulator in empty-background and populated-background
   states, including Back, Save, loading, error, Reduce Transparency, and large
   Dynamic Type.

## Acceptance criteria

- Web-owned avatar and background values returned by `GET /api/v1/profile/me`
  appear on the iOS editor without relaunching or falling back for valid
  relative paths.
- Selecting media only changes the local preview; Back performs no upload.
- Save uploads each selected image to its dedicated canonical endpoint, then
  saves text, updates shared profile state, and returns to Settings.
- With no background, a visible, calm, accessible background-upload control is
  present; with a background, the same area shows the image and a change
  control.
- The custom Back control responds across the real Settings navigation path and
  has at least a `44 x 44` point hit area.
- Existing avatar selection, text-profile saving, Settings navigation, and
  unrelated Spark work remain intact.
- Focused tests and both iOS schemes build with fresh passing evidence, and the
  final Simulator capture shows no clipping, contrast, or spacing regression.
