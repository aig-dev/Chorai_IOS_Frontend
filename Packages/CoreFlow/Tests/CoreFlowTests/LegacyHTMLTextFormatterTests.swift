import XCTest
@testable import CoreFlow

final class LegacyHTMLTextFormatterTests: XCTestCase {
    func testPreservesExistingTagEntityAndWhitespaceSemantics() {
        let samples: [(String, String)] = [
            ("", ""),
            (" <p>Hello<br>world</p><div>next</div><li>end</li> ", "Hello world next end"),
            ("a<br/>b<br />c", "a b c"),
            ("a<BR>b</P>c<h2>d</h2>e", "abcde"),
            ("&nbsp;&amp;&lt;&gt;&quot;&#39;&apos;", "&<>\"''"),
            ("&amp;nbsp; &amp;lt; &amp;amp;", "&nbsp; < &amp;"),
            ("&lt;b&gt;bold&lt;/b&gt;", "<b>bold</b>"),
            ("one\n\t two\u{00a0}三 🧘🏽‍♀️", "one two 三 🧘🏽‍♀️"),
            ("**markdown** [link](url) &unknown; &#x41;", "**markdown** [link](url) &unknown; &#x41;"),
            ("<script>keep text</script><img alt='ignored'>tail", "keep texttail"),
            ("<unfinished and 3 > 2 <> ok", "2 <> ok")
        ]
        for (html, expected) in samples {
            XCTAssertEqual(LegacyHTMLTextFormatter.presentation(html).plainText, expected, html)
        }
    }
}
