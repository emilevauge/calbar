import Foundation
import Testing
@testable import CalbarCore

@Suite struct FreeBusyTests {
    let cal = TestClock.paris
    func at(_ s: String) -> Date { TestClock.date("2026-10-06T\(s):00+02:00") }
    func span(_ a: String, _ b: String) -> DateInterval { DateInterval(start: at(a), end: at(b)) }

    @Test func parsesBusyAndUnknown() throws {
        let json = #"{"calendars": {"Ann@x.com": {"busy": [{"start": "2026-10-06T08:00:00Z", "end": "2026-10-06T09:00:00Z"}]}, "out@y.com": {"errors": [{"domain": "global", "reason": "notFound"}], "busy": []}}}"#
        let result = try FreeBusy.parse(Data(json.utf8))
        #expect(try FreeBusy.parseGroups(Data(json.utf8)).isEmpty)
        #expect(result["ann@x.com"] == .busy([span("10:00", "11:00")]))
        #expect(result["out@y.com"] == .unknown)
    }

    @Test func removesTheMeetingItself() {
        #expect(FreeBusy.removing(span("10:00", "11:00"), from: [span("09:30", "11:30"), span("14:00", "15:00")])
                == [span("09:30", "10:00"), span("11:00", "11:30"), span("14:00", "15:00")])
    }

    @Test func commonFreeSlots() {
        let busy = [[span("09:00", "10:00"), span("12:00", "13:00")], [span("09:30", "10:30"), span("15:00", "18:00")]]
        let free = FreeBusy.commonFree(busy: busy, days: [at("00:00")], startHour: 9, endHour: 19,
                                       duration: 3600, notBefore: at("00:00"), calendar: cal)
        #expect(free == [span("10:30", "12:00"), span("13:00", "15:00"), span("18:00", "19:00")])
        // Too short for an hour once past 11:30.
        let later = FreeBusy.commonFree(busy: busy, days: [at("00:00")], startHour: 9, endHour: 19,
                                        duration: 3600, notBefore: at("11:30"), calendar: cal)
        #expect(later == [span("13:00", "15:00"), span("18:00", "19:00")])
    }

    @Test func conflicts() {
        let busy = ["ann@x.com": [span("10:00", "11:00")], "bob@x.com": [span("11:00", "12:00")]]
        #expect(FreeBusy.conflicts(span("10:30", "11:30"), busy: busy) == ["ann@x.com", "bob@x.com"])
        #expect(FreeBusy.conflicts(span("12:00", "13:00"), busy: busy).isEmpty)
    }

    @Test func queriesInBatches() async throws {
        let empty = #"{"calendars": {}}"#
        let http = StubHTTP([(200, empty), (200, empty)])
        let emails = (0..<60).map { "p\($0)@x.com" }
        _ = try await CalendarAPI(http: http).freeBusy(token: "t", emails: emails, from: at("00:00"), to: at("23:00"))
        #expect(http.requests.count == 2)
        #expect(http.requests[0].url?.path.hasSuffix("/freeBusy") == true)
        let body = try #require(JSONSerialization.jsonObject(with: http.requests[1].httpBody!) as? [String: Any])
        #expect((body["items"] as? [Any])?.count == 10)
    }

    @Test func groupsStandForTheirMembers() async throws {
        let json = #"{"groups": {"Head@x.com": {"calendars": ["ann@x.com", "Bob@x.com"]}}, "calendars": {"head@x.com": {"errors": [{"reason": "notFound"}]}, "ann@x.com": {"busy": [{"start": "2026-10-06T08:00:00Z", "end": "2026-10-06T09:00:00Z"}]}, "bob@x.com": {"busy": []}}}"#
        let http = StubHTTP([(200, json)])
        let result = try await CalendarAPI(http: http).freeBusy(token: "t", emails: ["head@x.com"], from: at("00:00"), to: at("23:00"))
        #expect(result.groups == ["head@x.com": ["ann@x.com", "bob@x.com"]])
        #expect(result.availability["head@x.com"] == nil)
        let body = try #require(JSONSerialization.jsonObject(with: http.requests[0].httpBody!) as? [String: Any])
        #expect(body["groupExpansionMax"] as? Int == 100)
        // The group shown: every member counts; one member picked: that one.
        let all = FreeBusy.busy(people: ["me@x.com", "head@x.com"], shown: ["me@x.com", "head@x.com"], result: result, removing: nil)
        #expect(Set(all.keys) == ["ann@x.com", "bob@x.com"])
        let ann = FreeBusy.busy(people: ["me@x.com", "head@x.com"], shown: ["ann@x.com"], result: result, removing: nil)
        #expect(Array(ann.keys) == ["ann@x.com"])
    }

    @Test func toggling() {
        let everyone: Set<String> = ["me", "head"]
        let groups = ["head": ["ann", "bob", "cy"]]
        #expect(FreeBusy.toggle("ann", shown: everyone, everyone: everyone, groups: groups) == ["ann"])
        #expect(FreeBusy.toggle("bob", shown: ["ann"], everyone: everyone, groups: groups) == ["ann", "bob"])
        #expect(FreeBusy.toggle("ann", shown: ["ann"], everyone: everyone, groups: groups) == everyone)
        // Out of a shown group: the other members stay.
        #expect(FreeBusy.toggle("ann", shown: ["head"], everyone: everyone, groups: groups) == ["bob", "cy"])
    }
}
