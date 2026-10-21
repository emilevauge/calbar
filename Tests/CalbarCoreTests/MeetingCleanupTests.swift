import Foundation
import Testing
@testable import CalbarCore

@Suite struct MeetingCleanupTests {
    @Test func zoomInvitationComesOut() {
        let notes = """
        Agenda: roadmap

        Join Zoom Meeting
        https://traefik.zoom.us/j/81234567890?pwd=abc

        Meeting ID: 812 3456 7890
        Passcode: 123456

        Bring the numbers.
        """
        #expect(MeetingCleanup.notes(notes, removing: .zoom) == "Agenda: roadmap\n\nBring the numbers.")
        #expect(MeetingCleanup.location("https://traefik.zoom.us/j/81234567890?pwd=abc", removing: .zoom) == "")
        #expect(MeetingCleanup.location("Everest, https://traefik.zoom.us/j/8123", removing: .zoom) == "Everest")
    }

    @Test func meetLinesComeOutOtherLinksStay() {
        let notes = "Join with Google Meet\nhttps://meet.google.com/abc-defg-hij\nDoc: https://docs.google.com/d/1"
        #expect(MeetingCleanup.notes(notes, removing: .meet) == "Doc: https://docs.google.com/d/1")
        #expect(MeetingCleanup.location("https://teams.microsoft.com/l/meetup-join/x", removing: .zoom)
                == "https://teams.microsoft.com/l/meetup-join/x")
        #expect(MeetingCleanup.regenerates(.zoom) && MeetingCleanup.regenerates(.meet) && !MeetingCleanup.regenerates(.teams))
    }
}
