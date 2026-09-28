import Foundation
import Testing
@testable import Vocelo

// The menu shows the text compiled into the binary, so the embedded copies have to match
// the LICENSE and THIRD-PARTY-NOTICES.txt that are committed. Regenerating writes the Swift
// file from both; editing one by hand, or forgetting to regenerate, fails here.
@Test func embeddedTextsMatchTheCommittedFiles() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func committed(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }
    // A multi-line string literal drops the newline before its closing delimiter.
    #expect(try ThirdPartyNotices.text + "\n" == committed("THIRD-PARTY-NOTICES.txt"))
    #expect(try ThirdPartyNotices.appLicense + "\n" == committed("LICENSE"))
    #expect(ThirdPartyNotices.text.hasPrefix("THIRD-PARTY NOTICES\n"))
    #expect(ThirdPartyNotices.appLicense.hasPrefix("MIT License\n"))
}
