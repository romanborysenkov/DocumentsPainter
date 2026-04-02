import Foundation
import ZIPFoundation

enum DocxPlainTextParser {
    static func parseParagraphs(from url: URL) throws -> [String] {
        guard let archive = Archive(url: url, accessMode: .read), let entry = archive["word/document.xml"] else { return [] }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        let delegate = DocxDocumentXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private final class DocxDocumentXMLDelegate: NSObject, XMLParserDelegate {
        var paragraphs: [String] = []
        private var inText = false
        private var currentParagraph = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            switch name {
            case "p": currentParagraph = ""
            case "t": inText = true
            case "tab": currentParagraph.append("    ")
            case "br": currentParagraph.append("\n")
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { currentParagraph.append(string) }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            switch name {
            case "t": inText = false
            case "p":
                paragraphs.append(currentParagraph)
                currentParagraph = ""
            default: break
            }
        }
    }
}
