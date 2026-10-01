import Foundation
import Testing
@testable import CalbarCore

@Suite struct HTMLTextTests {
    @Test func decodesNamedAndNumericEntities() {
        #expect(HTMLText.decodeEntities("a &amp; b &lt;c&gt; &#39;d&#39; &#x41;") == "a & b <c> 'd' A")
    }

    @Test func leavesUnknownEntitiesAlone() {
        #expect(HTMLText.decodeEntities("&bogus; ok") == "&bogus; ok")
    }

    @Test func convertsLineBreaksAndStripsTags() {
        let html = "<b>Agenda</b><br>1. Intro<br/>2. Demo<p>Bye</p>"
        #expect(HTMLText.plainText(html) == "Agenda\n1. Intro\n2. Demo\nBye")
    }

    @Test func keepsLinkTargets() {
        let html = #"Notes: <a href="https://docs.google.com/d/x">the doc</a> and <a href="https://a.io">https://a.io</a>"#
        #expect(HTMLText.plainText(html) == "Notes: the doc (https://docs.google.com/d/x) and https://a.io")
    }

    @Test func rendersListItems() {
        #expect(HTMLText.plainText("<ul><li>one</li><li>two</li></ul>") == "• one\n• two")
    }

    @Test func collapsesBlankLines() {
        #expect(HTMLText.plainText("a<br><br><br><br>b") == "a\n\nb")
    }

    @Test func linkifyMarksURLs() {
        let text = "see https://example.com/x here"
        let attributed = Linkify.attributed(text)
        let links = attributed.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com/x")!])
    }

    @Test func keepsAngleBracketedURLs() {
        // Not a tag: the brackets stay, the URL survives.
        #expect(HTMLText.plainText("Link: <https://zoom.us/j/1>") == "Link: <https://zoom.us/j/1>")
    }

    @Test func keepsComparisonsInPlainText() {
        #expect(HTMLText.plainText("a < b and c > d") == "a < b and c > d")
    }

    @Test func stripsCommentsContainingBrackets() {
        #expect(HTMLText.plainText("a<!-- x > y\n z -->b") == "ab")
    }

    @Test func convertsLineBreakWithAttributes() {
        #expect(HTMLText.plainText(#"a<Br class="x">b"#) == "a\nb")
    }

    @Test func decodesAnchorLabelOnce() {
        #expect(HTMLText.plainText(#"<a href="x">&lt;b&gt;</a>"#) == "<b> (x)")
    }

    @Test func comparesDecodedLabelAndHref() {
        #expect(HTMLText.plainText(#"<a href="https://a.io/?x=1&amp;y=2">https://a.io/?x=1&amp;y=2</a>"#) == "https://a.io/?x=1&y=2")
    }

    @Test func acceptsSingleQuotedHref() {
        #expect(HTMLText.plainText("<a href='https://d.io/x'>doc</a>") == "doc (https://d.io/x)")
    }

    @Test func leavesNullAndControlCharacterEntitiesAlone() {
        #expect(HTMLText.decodeEntities("a&#0;b") == "a&#0;b")
        #expect(HTMLText.decodeEntities("a&#x7;b") == "a&#x7;b")
        #expect(HTMLText.decodeEntities("a&#10;b&#9;c") == "a\nb\tc")
    }
}
