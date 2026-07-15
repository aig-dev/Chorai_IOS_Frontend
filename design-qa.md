# Card Editor design QA

## Comparison target

- Source visual truth:
  - View Card metadata: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-39c2fe64-c184-436a-a5a6-3547b7c6ae3f.png`
  - Previous Card Actions structure: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-6213b855-130b-44d5-a810-c0c9e28d1836.png`
  - Previous literal-HTML failure: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-5ceed2ac-45e2-45b1-86de-fd5c75f0daef.png`
- Rendered implementation:
  - Collapsed metadata: `/tmp/ChoraiEditorUI-Task6-fix-deterministic-green-attachments-20260716/4B2CDCB0-68DE-42AA-9134-645908DF36D2.png`
  - Expanded related cards: `/tmp/ChoraiEditorUI-Task6-fix-deterministic-green-attachments-20260716/D06DDBAA-AC17-49B5-9F67-11E244B3100D.png`
  - Legacy HTML: `/tmp/ChoraiEditorUI-Task6-fix-deterministic-green-attachments-20260716/B53FE8B7-58B2-4917-A592-9E493EB9BB9A.png`
  - Default Card Actions: `/tmp/ChoraiEditorUI-Task6-live-card-actions-default-attachments-20260716/5435B5BD-3FB1-4C0D-BD6F-3C3F61EF6F1A.png`
  - Accessibility XXXL Card Actions, first and scrolled states: `/tmp/ChoraiEditorUI-Task6-live-card-actions-xxxl-final-attachments-20260716/C8C10399-91E8-41CF-9C29-CB69C40398D0.png`, `/tmp/ChoraiEditorUI-Task6-live-card-actions-xxxl-final-attachments-20260716/3B05C3F5-D01E-4B23-A075-6382ACDA5E40.png`
- Viewport: iPhone 17, 402 x 874 points, 1206 x 2622 pixels, iOS 26.2 Simulator.
- State: dark theme; populated editor with metadata collapsed/expanded; native Card Actions at default and Accessibility XXXL text sizes; legacy HTML fallback.

The source View Card and editor fixture intentionally contain different dynamic text. The comparison therefore evaluates the shared tag capsules, disclosure affordance, visual tokens, and density. Editor-only Add Tag and Save controls are intentional editing affordances.

## Comparison evidence

- Full-view evidence: the rendered screenshots above show the complete editor, direct privacy and More controls, metadata states, and actual native Card Actions.
- Focused metadata comparison: `/tmp/view-editor-metadata-final-comparison.png` places the View Card reference and final editor capture in one normalized side-by-side image.
- Focused action comparison: `/tmp/card-actions-final-comparison.png` places the previous action sheet and final native Card Actions in one comparison image. It confirms Make Public moved out, Add Background remained in Card Actions, and Link plus ID-scoped actions are present.
- Primary interactions tested: direct privacy action; direct More action; display-only related-card expand/collapse; Card Actions open/dismiss; Link and Background reachability; scrolling to Remove at Accessibility XXXL; read-only disabling; `@` and Card Actions routing to the same native link flow.

## Findings

No actionable P0, P1, or P2 visual or interaction mismatches remain.

- Fonts and typography: shared View metadata components use the same system typography and capsule text treatment. Legacy `<strong>` content renders with visible emphasis while literal HTML tags are absent. Default and Accessibility XXXL states preserve readable labels without overlap.
- Spacing and layout rhythm: tags retain compact View-style spacing; the disclosure chevron occupies the same trailing position; privacy and More are adjacent 44-point controls. Card Actions scrolls at XXXL, and its final destructive action is demonstrably reachable.
- Colors and visual tokens: the editor reuses the View Card metadata components and existing dark purple capsule/fill tokens. Disabled and destructive states remain native and legible.
- Image quality and asset fidelity: this flow introduces no raster illustration or replacement artwork. Existing SF Symbols and native controls remain sharp at the captured 3x device scale.
- Copy and content: Link is a display-only metadata row in the editor; creation remains available through Card Actions and `@`. Add Background is in Card Actions, while the direct top control communicates privacy state.
- Accessibility and responsiveness: default and Accessibility XXXL captures show no control collision. Related-card disclosure remains readable in compatibility-blocked mode; privacy, More, and Save are disabled when the editor cannot safely persist.

## Comparison history

1. Earlier P1: raw `<p>` and `</p>` markup appeared in editor content.
   - Fix: recognize raw or once-escaped legacy HTML only when canonical `content_json` is absent, then hydrate it through the BlockNote HTML parser.
   - Post-fix evidence: the legacy capture renders `Legacy rich text`, including bold `rich`, with no literal tags.
2. Earlier P1: Make Public and Add Background both lived inside Card Actions.
   - Fix: move privacy to the direct control beside More; retain Background in Card Actions and add the shared Link entry.
   - Post-fix evidence: default Card Actions and focused action comparison paths above.
3. Earlier P2: editor tags and related links did not visually align with View Card.
   - Fix: share the View Card capsule and related-row components, including colors, density, chevron, and reduced-motion behavior.
   - Post-fix evidence: focused metadata comparison plus collapsed/expanded editor captures.
4. Earlier P2 test-evidence gap: the first QA pass did not prove native Card Actions at default/XXXL sizes or prove the final action remained reachable.
   - Fix: capture the real dialog, scroll it at Accessibility XXXL, require Remove to become hittable, and verify safe dismissal.
   - Post-fix evidence: both final XXXL screenshots and passing UI result bundle `/tmp/ChoraiEditorUI-Task6-live-card-actions-xxxl-final-20260716.xcresult`.

## Open questions

None blocking. The exact Card Actions container geometry is owned by iOS and changes with Dynamic Type; the implementation deliberately uses the native scroll behavior instead of overriding it with a custom visual surface.

## Implementation checklist

- [x] Remove literal legacy HTML markup while preserving rich-text semantics.
- [x] Place privacy directly beside More and keep Background in Card Actions.
- [x] Keep editor links display-only and route creation from Card Actions or `@`.
- [x] Reuse View Card tag/link presentation.
- [x] Verify default, read-only, empty, populated, collapsed, expanded, and Accessibility XXXL states.

final result: passed
