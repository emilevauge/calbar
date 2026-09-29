import Foundation
import Testing
@testable import MacalCore

@Suite struct ReleaseTests {
    let page = URL(string: "https://github.com/emilevauge/macal/releases/latest")!

    @Test func comparesComponentsNumerically() {
        #expect(AppVersion.isNewer("0.1.10", than: "0.1.9"))
        #expect(AppVersion.isNewer("0.2.0", than: "0.1.99"))
        #expect(AppVersion.isNewer("1.0.0", than: "0.9.9"))
        #expect(!AppVersion.isNewer("0.1.9", than: "0.1.10"))
    }

    @Test func equalVersionsAreNotNewer() {
        #expect(!AppVersion.isNewer("0.1.0", than: "0.1.0"))
        #expect(!AppVersion.isNewer("0.1", than: "0.1.0"))
        #expect(!AppVersion.isNewer("0.1.0", than: "0.1"))
    }

    @Test func ignoresTagPrefixAndSuffix() {
        #expect(AppVersion.isNewer("v0.2.0", than: "0.1.0"))
        #expect(AppVersion.normalized("v1.2.3") == "1.2.3")
        #expect(AppVersion.components("1.2.3-beta.1") == [1, 2, 3])
    }

    @Test func malformedVersionIsNeverNewer() {
        #expect(!AppVersion.isNewer("latest", than: "0.1.0"))
        #expect(!AppVersion.isNewer("", than: "0.1.0"))
    }

    @Test func parsesLatestReleaseWithDMG() throws {
        let json = #"""
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/emilevauge/macal/releases/tag/v0.2.0",
          "assets": [
            {"name": "Macal.app.zip", "browser_download_url": "https://github.com/emilevauge/macal/releases/download/v0.2.0/Macal.app.zip"},
            {"name": "Macal.dmg", "browser_download_url": "https://github.com/emilevauge/macal/releases/download/v0.2.0/Macal.dmg"}
          ]
        }
        """#
        let release = try GitHubRelease.parse(Data(json.utf8), assetName: "Macal.dmg", fallbackPage: page)
        #expect(release.version == "0.2.0")
        #expect(release.pageURL.absoluteString == "https://github.com/emilevauge/macal/releases/tag/v0.2.0")
        #expect(release.dmgURL?.absoluteString == "https://github.com/emilevauge/macal/releases/download/v0.2.0/Macal.dmg")
    }

    @Test func releaseWithoutDMGFallsBackToThePage() throws {
        let json = #"{"tag_name": "0.3.0", "assets": []}"#
        let release = try GitHubRelease.parse(Data(json.utf8), assetName: "Macal.dmg", fallbackPage: page)
        #expect(release.version == "0.3.0")
        #expect(release.pageURL == page)
        #expect(release.dmgURL == nil)
    }

    @Test func onlyAnHTTPSAssetIsDownloaded() throws {
        let json = #"{"tag_name": "0.3.0", "assets": [{"name": "Macal.dmg", "browser_download_url": "http://example.com/Macal.dmg"}]}"#
        let release = try GitHubRelease.parse(Data(json.utf8), assetName: "Macal.dmg", fallbackPage: page)
        #expect(release.dmgURL == nil)
    }

    @Test func rejectsAPayloadWithoutTag() {
        #expect(throws: (any Error).self) {
            try GitHubRelease.parse(Data(#"{"message": "Not Found"}"#.utf8), assetName: "Macal.dmg", fallbackPage: page)
        }
    }

    @Test func backgroundCheckHonoursTheCooldown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdatePolicy.shouldCheck(lastCheck: nil, now: now, interval: 86_400))
        #expect(!UpdatePolicy.shouldCheck(lastCheck: now.addingTimeInterval(-3_600), now: now, interval: 86_400))
        #expect(UpdatePolicy.shouldCheck(lastCheck: now.addingTimeInterval(-86_400), now: now, interval: 86_400))
        // A clock set back must not block checks forever.
        #expect(UpdatePolicy.shouldCheck(lastCheck: now.addingTimeInterval(86_400 * 3), now: now, interval: 86_400))
    }

    @Test func notifiesEachNewVersionOnce() {
        #expect(UpdatePolicy.shouldNotify(latest: "0.2.0", current: "0.1.0", lastNotified: nil))
        #expect(!UpdatePolicy.shouldNotify(latest: "0.2.0", current: "0.1.0", lastNotified: "0.2.0"))
        #expect(UpdatePolicy.shouldNotify(latest: "0.3.0", current: "0.1.0", lastNotified: "0.2.0"))
        #expect(!UpdatePolicy.shouldNotify(latest: "0.1.0", current: "0.1.0", lastNotified: nil))
    }
}

@Suite struct SelfUpdateScriptTests {
    @Test func quotesForTheShell() {
        #expect(SelfUpdateScript.quote("/Applications/Macal.app") == "'/Applications/Macal.app'")
        #expect(SelfUpdateScript.quote("it's") == #"'it'\''s'"#)
    }

    @Test func scriptSwapsWithBackupAndRelaunches() {
        let script = SelfUpdateScript.make(
            bundlePath: "/Users/me/Apps/My 'Macal'.app", dmgPath: "/tmp/u/Macal.dmg",
            workDir: "/tmp/u", pid: 4242
        )
        #expect(script.hasPrefix("#!/bin/zsh\n"))
        #expect(script.contains(#"BUNDLE='/Users/me/Apps/My '\''Macal'\''.app'"#))
        #expect(script.contains(#"BACKUP='/Users/me/Apps/My '\''Macal'\''.app.macal-update-backup'"#))
        #expect(script.contains("kill -0 4242"))
        #expect(script.contains(#"mv "$BACKUP" "$BUNDLE""#))
        #expect(script.contains("xattr -dr com.apple.quarantine"))
        #expect(script.hasSuffix(#"rm -rf "$WORK""#))
    }

    @Test func scriptChecksTheNewAppBeforeRemovingTheOldOne() throws {
        let script = SelfUpdateScript.make(bundlePath: "/Applications/Macal.app", dmgPath: "/tmp/u/Macal.dmg",
                                           workDir: "/tmp/u", pid: 1)
        let check = try #require(script.range(of: #"[ ! -x "$NEW/Contents/MacOS/Macal" ]"#))
        let move = try #require(script.range(of: #"mv "$BUNDLE" "$BACKUP""#))
        #expect(check.lowerBound < move.lowerBound)
    }
}
