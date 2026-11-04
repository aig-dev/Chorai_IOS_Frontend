import Foundation

/// A presentation-only layer over the signed editor bundle. It never changes
/// the document, its stored styles, or the bridge's command/snapshot protocol.
enum BlockNoteEditorAppearance {
    static let stylesheet = """
    :root {
        font: -apple-system-body;
        --chorai-editor-scale: 1.352941;
        --chorai-editor-block-gap: 29px;
        --chorai-editor-line-height: 1.66;
        color-scheme: light dark;
        --chorai-editor-ink: #1c1c1e;
        --chorai-editor-muted: #6c6c70;
        --chorai-editor-surface: #f0f0ea;
        --chorai-editor-edge: #d9dfd7;
        --chorai-editor-gold: #846838;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --chorai-editor-ink: #f5f5f7;
            --chorai-editor-muted: #98989e;
            --chorai-editor-surface: #35363b;
            --chorai-editor-edge: #4c514f;
            --chorai-editor-gold: #d6b378;
        }
    }
    body, .ios-blocknote-view .bn-editor {
        color: var(--chorai-editor-ink);
        caret-color: var(--chorai-editor-ink);
    }
    .ios-blocknote-view .bn-editor {
        box-sizing: border-box;
        min-height: var(--chorai-editor-writing-height, 0px);
        font-family: ui-serif, 'New York', 'Songti SC', Georgia, serif;
        font-size: calc(var(--chorai-editor-scale) * 1rem);
        line-height: 1.55;
        padding: 8px 0 24px;
    }
    .ios-blocknote-view .bn-block-content[data-content-type=paragraph] {
        font-size: inherit;
        line-height: inherit;
    }
    .ios-blocknote-view [data-content-type=paragraph] .bn-inline-content {
        line-height: var(--chorai-editor-line-height);
    }
    .ios-blocknote-view .bn-block-outer + .bn-block-outer {
        margin-top: var(--chorai-editor-block-gap);
    }
    .ios-blocknote-view [data-content-type=codeBlock] {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 15px;
    }
    .ios-blocknote-view .bn-container {
        --bn-colors-editor-text: var(--chorai-editor-ink);
        --bn-colors-side-menu: var(--chorai-editor-muted);
        --bn-colors-menu-text: var(--chorai-editor-ink);
        --bn-colors-menu-background: var(--chorai-editor-surface);
        --bn-colors-hovered-background: var(--chorai-editor-surface);
        --bn-colors-border: var(--chorai-editor-edge);
    }
    .ios-blocknote-view .bn-inline-content a {
        color: var(--chorai-editor-ink);
        text-decoration: underline;
    }
    .ios-blocknote-view [data-content-type=quote] blockquote {
        color: var(--chorai-editor-muted);
        border-left-color: var(--chorai-editor-gold);
    }
    .ios-blocknote-view [data-content-type=image] .bn-visual-media-wrapper,
    .ios-readonly-custom-block {
        border-color: var(--chorai-editor-edge);
        background: var(--chorai-editor-surface);
        color: var(--chorai-editor-muted);
    }
    .ios-readonly-custom-block__kind { color: var(--chorai-editor-gold); }
    """

    static var installationScript: String {
        // The stylesheet is local static code; JSON encoding keeps CSS quoting
        // separate from the JavaScript program without interpolating note data.
        let encoded = (try? JSONEncoder().encode(stylesheet)) ?? Data("\"\"".utf8)
        let css = String(decoding: encoded, as: UTF8.self)
        return """
        (() => {
            let style = document.getElementById('chorai-native-appearance');
            if (!style) {
                style = document.createElement('style');
                style.id = 'chorai-native-appearance';
                document.head.appendChild(style);
            }
            style.textContent = \(css);
        })();
        """
    }

    static func installationScript(fontScale: Double, minimumWritingHeight: Double = 0) -> String {
        let scale = fontScale.isFinite ? max(1, min(fontScale, 2)) : 23.0 / 17.0
        // The 17-point Merge surface keeps its compact rhythm; the 23-point
        // writing surface follows the approved native TextEditor line spacing.
        let blockGap = scale > 1 ? 29 : 16
        let lineHeight = scale > 1 ? 1.66 : 1.55
        return installationScript + """

        document.documentElement.style.setProperty('--chorai-editor-scale', '\(scale)');
        document.documentElement.style.setProperty('--chorai-editor-block-gap', '\(blockGap)px');
        document.documentElement.style.setProperty('--chorai-editor-line-height', '\(lineHeight)');
        """ + minimumWritingHeightScript(minimumWritingHeight)
    }

    static func normalizedMinimumWritingHeight(_ height: Double) -> Double {
        height.isFinite ? max(0, height) : 0
    }

    static func minimumWritingHeightScript(_ height: Double) -> String {
        // An explicit border-box floor fills the editable DOM, without tying
        // ResizeObserver's content measurement to the WebView viewport (100vh).
        """

        document.documentElement.style.setProperty('--chorai-editor-writing-height', '\(normalizedMinimumWritingHeight(height))px');
        """
    }
}
