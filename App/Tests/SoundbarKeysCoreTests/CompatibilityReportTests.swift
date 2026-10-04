import Foundation
import Testing
@testable import SoundbarKeysCore

struct CompatibilityReportTests {
    /// Shape of a Soundbar 700 `/system/info` body, with made-up private values.
    private let systemInfo: [String: Any] = [
        "productName": "Bose Soundbar 700", "productType": "ginger-cheevers",
        "softwareVersion": "25.0.40-42+51e3125", "name": "Living Room", "guid": "abcd-1234",
        "serialNumber": "SN-SECRET", "countryCode": "DE", "regionCode": "DE", "productColor": 2,
    ]

    private func report() -> CompatibilityReport {
        let fields = CompatibilityReport.soundbarFields(fromSystemInfo: systemInfo)
        var report = CompatibilityReport()
        report.appVersion = "1.1"
        report.macOSVersion = "26.7.1"
        report.architecture = "arm64"
        report.outputIsHDMI = true
        (report.productName, report.productType, report.firmware) = (fields.name, fields.type, fields.firmware)
        report.volumeRange = "0–100 (soft 10–70)"
        report.soundModes = ["NORMAL", "DIALOG"]
        report.endpoints = CompatibilityReport.endpoints(fromCapabilities: [
            "group": [["endpoints": [["endpoint": "/audio/volume"], ["endpoint": "/audio/mode"]]],
                      ["endpoints": [["endpoint": "/audio/volume"]]]],
        ])
        return report
    }

    @Test func containsTheTechnicalFacts() {
        let text = report().markdown
        #expect(text.contains("Bose Soundbar 700"))
        #expect(text.contains("25.0.40-42+51e3125"))
        #expect(text.contains("NORMAL, DIALOG"))
        #expect(text.contains("| API endpoints | 2 |"))
    }

    /// Allow list: private fields of /system/info never end up in the report.
    @Test func leavesOutPrivateFields() {
        let text = report().markdown
        for secret in ["Living Room", "abcd-1234", "SN-SECRET", "DE"] {
            #expect(!text.contains(secret), "report must not contain \(secret)")
        }
    }

    @Test func endpointsAreUniqueAndSorted() {
        #expect(report().endpoints == ["/audio/mode", "/audio/volume"])
    }

    @Test func issueURLPrefillsTheForm() throws {
        let url = try #require(report().issueURL(repository: URL(string: "https://github.com/owner/repo")!))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.path == "/owner/repo/issues/new")
        #expect(items.first(where: { $0.name == "template" })?.value == "compatibility.yml")
        #expect(items.first(where: { $0.name == "model" })?.value == "Bose Soundbar 700")
        #expect(items.first(where: { $0.name == "report" })?.value?.contains("Firmware") == true)
    }
}
