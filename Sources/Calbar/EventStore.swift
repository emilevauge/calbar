import AppKit
import SwiftUI
import CalbarCore

/// Events of today and tomorrow for every enabled calendar. Polls Google
/// every 5 minutes (every 30 seconds while offline), publishes `now` every
/// 15 seconds so countdowns move. Other days, browsed in the popover, are
/// fetched on demand into an in-memory cache.
@MainActor
final class EventStore: ObservableObject {
    /// Every event fetched, before deduplication and filtering.
    @Published private(set) var rawEvents: [CalendarEvent] = []
    @Published private(set) var lastFetch: Date?
    @Published private(set) var isOffline = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var now = Date()
    /// Accounts for which a refresh pass completed at least once, from this
    /// launch or from the cache. The others have no events to show yet.
    @Published private(set) var settledAccounts: Set<String> = []
    /// Event the popover should open expanded, set by the alert panel.
    @Published var requestedEventID: String?
    /// Raw events of days outside the regular window, fetched on demand.
    @Published private var dayCache = DayCache<[CalendarEvent]>()
    /// Days with a fetch scheduled or running. Not published: it is set
    /// while a view reads `events(for:)`.
    private var pendingDays: Set<Date> = []
    /// Invitations being answered, by event id: the pills dim meanwhile.
    @Published private(set) var pendingAnswers: Set<String> = []
    /// Last failed answer per event id, shown under the RSVP control for a
    /// few seconds.
    @Published private(set) var answerErrors: [String: String] = [:]
    /// Events answered since the popover opened. A declined one stays in
    /// the list until the popover closes, so the row does not vanish under
    /// the pointer.
    @Published private(set) var recentlyAnswered: Set<String> = []
    /// Answers laid over fetched events: while in flight, and once
    /// confirmed until a fetch started after the confirmation brings them
    /// back from Google. A fetch that started earlier may carry the old
    /// answer and must not flip the control back.
    private var answerOverlay: [String: (response: ResponseStatus, confirmedAt: Date?)] = [:]

    let accounts: AccountStore
    /// Set by `AppDelegate`, replaced when another OAuth client is imported.
    var auth: GoogleAuth?
    private let api = CalendarAPI()
    /// Set when `refresh()` is called while a refresh is running.
    private var needsAnotherPass = false

    init(accounts: AccountStore, auth: GoogleAuth?) {
        self.accounts = accounts
        self.auth = auth
        loadCache()
    }

    /// Deduplicated, sorted, limited to enabled calendars.
    var events: [CalendarEvent] {
        visible(rawEvents)
    }

    private func visible(_ raw: [CalendarEvent]) -> [CalendarEvent] {
        let enabled = raw.filter {
            accounts.isEnabled(calendarID: $0.calendarID, email: $0.accountEmail) && !isBeingDeleted($0)
        }
        return EventMerger.merge(enabled, showDeclined: Prefs.showDeclined, keeping: recentlyAnswered)
    }

    /// A refresh runs and some account has never been fetched: the popover
    /// shows "Loading…" rather than an empty day. Later background
    /// refreshes of settled accounts do not count.
    var isLoading: Bool {
        isRefreshing && accounts.accounts.contains { !settledAccounts.contains($0.email) }
    }

    var agenda: DayAgenda {
        DayAgenda.build(from: events, now: now, calendar: .current)
    }

    // MARK: other days

    /// Events of `day`. Today and tomorrow come from the regular refresh.
    /// Other days come from the day cache; a missing or stale day is
    /// fetched in the background and published when it arrives, while a
    /// stale one keeps showing its previous events.
    func events(for day: Date) -> DayContent {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)
        let regular = DayWindow.interval(for: now, days: 2, calendar: calendar)
        if day >= regular.start && day < regular.end {
            return isLoading ? .loading : .loaded(DayListing.build(events: events, day: day, calendar: calendar))
        }
        if dayCache.needsFetch(day, now: Date()) { scheduleFetch(day) }
        guard let entry = dayCache.entry(for: day) else { return .loading }
        if let raw = entry.value {
            return .loaded(DayListing.build(events: visible(raw), day: day, calendar: calendar))
        }
        return entry.failed ? .failed : .loading
    }

    /// Events of each day of a week, for the week view. The days outside
    /// the regular refresh that need it are fetched together, in one
    /// request window, rather than one fetch per day.
    func events(forWeek days: [Date]) -> [DayContent] {
        let calendar = Calendar.current
        let regular = DayWindow.interval(for: now, days: 2, calendar: calendar)
        let missing = days.map { calendar.startOfDay(for: $0) }.filter {
            !($0 >= regular.start && $0 < regular.end)
                && dayCache.needsFetch($0, now: Date()) && !pendingDays.contains($0)
        }
        if missing.count > 1 { scheduleFetch(days: missing) }
        return days.map { events(for: $0) }
    }

    /// One fetch for several days, from the first to the last.
    private func scheduleFetch(days: [Date]) {
        guard let auth, let first = days.min(), let last = days.max() else { return }
        pendingDays.formUnion(days)
        Task {
            let calendar = Calendar.current
            for day in days { dayCache.begin(day) }
            let span = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
            let window = DayWindow.interval(for: first, days: span, calendar: calendar)
            let started = Date()
            let result = await fetch(window, auth: auth, label: "week")
            if result.reachedGoogle || accounts.accounts.isEmpty {
                let collected = result.collected.filter { accounts.account($0.accountEmail) != nil }
                for day in days {
                    let dayWindow = DayWindow.interval(for: day, calendar: calendar)
                    let previous = dayCache.entry(for: day)?.value ?? []
                    let merged = RefreshMerge.merge(
                        collected: collected.filter { DayWindow.contains($0, in: dayWindow) },
                        previous: previous,
                        failedAccounts: result.failedAccounts,
                        failedCalendars: result.failedCalendars)
                    dayCache.finish(day, value: overlayAnswers(merged, fetchStarted: started), at: Date())
                }
            } else {
                for day in days { dayCache.fail(day) }
            }
            pendingDays.subtract(days)
            NSLog("Calbar: week fetch of %d days done in %.2fs", days.count, Date().timeIntervalSince(started))
        }
    }

    /// Fetches `day` again after a failure.
    func retry(_ day: Date) {
        scheduleFetch(Calendar.current.startOfDay(for: day))
    }

    /// Deferred to a task: `events(for:)` runs while SwiftUI renders, when
    /// published properties must not change.
    private func scheduleFetch(_ day: Date) {
        guard let auth, !pendingDays.contains(day) else { return }
        pendingDays.insert(day)
        Task {
            await fetchDay(day, auth: auth)
            pendingDays.remove(day)
        }
    }

    private func fetchDay(_ day: Date, auth: GoogleAuth) async {
        dayCache.begin(day)
        let started = Date()
        let window = DayWindow.interval(for: day, calendar: .current)
        let result = await fetch(window, auth: auth, label: "day")
        guard result.reachedGoogle || accounts.accounts.isEmpty else {
            NSLog("Calbar: day fetch reached no account in %.2fs", Date().timeIntervalSince(started))
            dayCache.fail(day)
            return
        }
        let previous = dayCache.entry(for: day)?.value ?? []
        let merged = RefreshMerge.merge(collected: result.collected, previous: previous,
                                        failedAccounts: result.failedAccounts,
                                        failedCalendars: result.failedCalendars)
            .filter { accounts.account($0.accountEmail) != nil }
        dayCache.finish(day, value: overlayAnswers(merged, fetchStarted: started), at: Date())
        NSLog("Calbar: day fetch done in %.2fs: %d fetched, %d kept",
              Date().timeIntervalSince(started), result.collected.count, merged.count)
    }

    // MARK: refresh

    func start() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.tick()
            }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // After a wake the network is often not up yet: retry soon
                // rather than waiting for the next regular poll.
                let offline = self?.isOffline ?? false
                try? await Task.sleep(for: .seconds(offline ? 30 : 300))
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
                Task { await self?.refresh() }
            }
        }
    }

    /// Fetches every account. A call made while a refresh runs is not
    /// dropped: the running refresh does one more pass at the end, so a
    /// just-added account or a toggled calendar is picked up.
    func refresh() async {
        guard let auth else { return }
        if isRefreshing {
            needsAnotherPass = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            needsAnotherPass = false
            await refreshPass(auth)
        } while needsAnotherPass
    }

    /// Result of one account in a refresh pass.
    private enum AccountOutcome {
        case fetched(email: String, events: [CalendarEvent], failedCalendars: Set<CalendarKey>)
        case needsReconnect(email: String)
        case failed(email: String)
    }

    /// Upper bound on event requests in flight for one account.
    private nonisolated static let maxConcurrentFetches = 6

    /// Events of every account over one window, and what failed.
    private struct WindowFetch {
        let emails: [String]
        var collected: [CalendarEvent] = []
        var failedAccounts: Set<String> = []
        var failedCalendars: Set<CalendarKey> = []
        /// At least one account got an answer from Google.
        var reachedGoogle = false
    }

    /// Fetches `window` from every account in parallel and records which
    /// accounts need reconnecting. Shared by the refresh pass and the
    /// on-demand fetch of other days.
    private func fetch(_ window: DateInterval, auth: GoogleAuth, label: String) async -> WindowFetch {
        let calendar = Calendar.current
        // Read on every call, so a repeat pass sees accounts added meanwhile.
        let emails = accounts.accounts.map(\.email)
        let outcomes = await withTaskGroup(of: AccountOutcome.self) { group in
            for (index, email) in emails.enumerated() {
                group.addTask {
                    await self.fetchAccount(email, index: index, auth: auth, window: window,
                                            calendar: calendar, label: label)
                }
            }
            var all: [AccountOutcome] = []
            for await outcome in group { all.append(outcome) }
            return all
        }

        var result = WindowFetch(emails: emails)
        for outcome in outcomes {
            switch outcome {
            case let .fetched(email, events, failed):
                result.collected += events
                result.failedCalendars.formUnion(failed)
                accounts.setNeedsReconnect(false, email: email)
                result.reachedGoogle = true
            case let .needsReconnect(email):
                accounts.setNeedsReconnect(true, email: email)
                result.reachedGoogle = true
            case let .failed(email):
                result.failedAccounts.insert(email)
            }
        }
        return result
    }

    private func refreshPass(_ auth: GoogleAuth) async {
        let started = Date()
        let window = DayWindow.interval(for: Date(), days: 2, calendar: .current)
        let result = await fetch(window, auth: auth, label: "refresh")
        let emails = result.emails
        let collected = result.collected
        // Other days are fetched again when shown, to pick up changes and
        // toggled calendars.
        dayCache.invalidate()
        let elapsed = Date().timeIntervalSince(started)
        // Settled even when failed or offline: a failed account then shows
        // what the cache has instead of loading forever.
        settledAccounts.formUnion(emails)

        if result.reachedGoogle || accounts.accounts.isEmpty {
            // An account removed during the pass must not come back.
            let merged = RefreshMerge.merge(collected: collected, previous: rawEvents,
                                            failedAccounts: result.failedAccounts,
                                            failedCalendars: result.failedCalendars)
                .filter { accounts.account($0.accountEmail) != nil }
            rawEvents = overlayAnswers(merged, fetchStarted: started)
            dropConfirmedAnswers(fetchedSince: started)
            lastFetch = Date()
            isOffline = false
            saveCache()
            NSLog("Calbar: refresh done in %.2fs: %d fetched, %d kept, %d shown, %d today",
                  elapsed, collected.count, rawEvents.count, events.count,
                  agenda.allDay.count + agenda.current.count + agenda.past.count)
        } else {
            // Keep showing the cache; alerts keep working on it.
            NSLog("Calbar: refresh reached no account in %.2fs, offline", elapsed)
            isOffline = true
        }
    }

    /// Calendar list, then the events of every enabled calendar, fetched
    /// concurrently with one access token. Diagnostics log counts and
    /// positions only, never calendar names, ids or event content.
    private func fetchAccount(
        _ email: String, index accountIndex: Int, auth: GoogleAuth,
        window: DateInterval, calendar: Calendar, label: String
    ) async -> AccountOutcome {
        let from = window.start, to = window.end
        do {
            var token = try await auth.accessToken(for: email)
            let fresh: [CalendarInfo]
            do {
                fresh = try await api.calendars(token: token)
            } catch APIError.unauthorized {
                token = try await auth.accessToken(for: email, forceRefresh: true)
                fresh = try await api.calendars(token: token)
            }
            accounts.setCalendars(fresh, for: email)
            let known = accounts.account(email)?.calendars ?? []
            let enabled = known.filter(\.enabled)
            NSLog("Calbar: %@ account %d: %d calendars, %d enabled", label, accountIndex, known.count, enabled.count)

            var results = await Self.fetchEvents(enabled, api: api, token: token, email: email,
                                                 from: from, to: to, calendar: calendar)
            // A 401 on some requests: refresh the token once and retry
            // only those calendars.
            let rejected = results.indices.filter {
                if case .failure(APIError.unauthorized) = results[$0] { return true }
                return false
            }
            if !rejected.isEmpty {
                do {
                    let retryToken = try await auth.accessToken(for: email, forceRefresh: true)
                    let retried = await Self.fetchEvents(rejected.map { enabled[$0] }, api: api, token: retryToken,
                                                         email: email, from: from, to: to, calendar: calendar)
                    for (k, i) in rejected.enumerated() { results[i] = retried[k] }
                } catch {
                    for i in rejected { results[i] = .failure(error) }
                }
            }

            var events: [CalendarEvent] = []
            var failed: Set<CalendarKey> = []
            for (source, result) in zip(enabled, results) {
                let position = known.firstIndex { $0.id == source.id } ?? -1
                switch result {
                case .success(let fetched):
                    NSLog("Calbar: %@ account %d calendar %d: %d events", label, accountIndex, position, fetched.count)
                    events += fetched
                case .failure(let error):
                    NSLog("Calbar: %@ account %d calendar %d failed: %@", label, accountIndex, position, "\(error)")
                    failed.insert(CalendarKey(email: email, calendarID: source.id))
                }
            }
            return .fetched(email: email, events: events, failedCalendars: failed)
        } catch OAuthError.invalidGrant {
            NSLog("Calbar: %@ account %d needs reconnect", label, accountIndex)
            return .needsReconnect(email: email)
        } catch {
            NSLog("Calbar: %@ of account %d failed: %@", label, accountIndex, "\(error)")
            return .failed(email: email)
        }
    }

    /// Events of each source, in the same order, with at most
    /// `maxConcurrentFetches` requests in flight. Runs off the main actor.
    private nonisolated static func fetchEvents(
        _ sources: [CalendarInfo], api: CalendarAPI, token: String, email: String,
        from: Date, to: Date, calendar: Calendar
    ) async -> [Result<[CalendarEvent], Error>] {
        func operation(_ i: Int) -> @Sendable () async -> (Int, Result<[CalendarEvent], Error>) {
            let source = sources[i]
            return {
                do {
                    return (i, .success(try await api.events(token: token, source: source, accountEmail: email,
                                                             from: from, to: to, calendar: calendar)))
                } catch {
                    return (i, .failure(error))
                }
            }
        }
        return await withTaskGroup(of: (Int, Result<[CalendarEvent], Error>).self) { group in
            var results = [Result<[CalendarEvent], Error>](repeating: .success([]), count: sources.count)
            var next = 0
            while next < min(maxConcurrentFetches, sources.count) {
                group.addTask(operation: operation(next))
                next += 1
            }
            for await (i, result) in group {
                results[i] = result
                if next < sources.count {
                    group.addTask(operation: operation(next))
                    next += 1
                }
            }
            return results
        }
    }

    // MARK: answers

    /// Answers an invitation: yes, maybe or no. The answer shows at once;
    /// a failure puts the previous one back and shows a short error.
    func respond(to event: CalendarEvent, with response: ResponseStatus) {
        guard let auth, event.canRespond, response != .needsAction, response != event.selfResponse,
              !pendingAnswers.contains(event.id), accounts.canReply(event.accountEmail) else { return }
        let id = event.id
        let previous = event.selfResponse
        pendingAnswers.insert(id)
        recentlyAnswered.insert(id)
        answerErrors[id] = nil
        answerOverlay[id] = (response, nil)
        apply(response, to: id)
        NSLog("Calbar: answering an invitation")

        Task {
            do {
                try await withAccessToken(event.accountEmail, auth: auth) { [api] token in
                    try await api.respond(token: token, calendarID: event.calendarID,
                                          eventID: event.googleEventID, response: response)
                }
                pendingAnswers.remove(id)
                answerOverlay[id] = (response, Date())
                NSLog("Calbar: invitation answered")
                await refresh()
            } catch {
                NSLog("Calbar: answering an invitation failed: %@", "\(error)")
                pendingAnswers.remove(id)
                answerOverlay[id] = nil
                apply(previous, to: id)
                switch error {
                case APIError.insufficientScope:
                    accounts.markReadOnly(event.accountEmail)
                case OAuthError.invalidGrant:
                    accounts.setNeedsReconnect(true, email: event.accountEmail)
                default:
                    break
                }
                showAnswerError(describeReply(error), for: id)
            }
        }
    }

    // MARK: deleting

    /// A deletion waiting `undoDelay`: one occurrence, or a series from
    /// one occurrence on, or a whole series.
    struct Deletion: Equatable {
        let event: CalendarEvent
        let scope: RecurrenceScope
        var key: String { "\(event.occurrenceKey)|\(scope.rawValue)" }

        /// Copies across accounts share the iCalUID, as do occurrences.
        func hides(_ other: CalendarEvent) -> Bool {
            switch event.isRecurring ? scope : .this {
            case .this: return other.occurrenceKey == event.occurrenceKey
            case .following: return other.iCalUID == event.iCalUID && other.start >= event.start
            case .all: return other.iCalUID == event.iCalUID
            }
        }
    }

    /// Deletions made in Calbar, hidden while they wait `undoDelay` to be
    /// sent, and until the next refresh drops them.
    @Published private(set) var deleting: [String: Deletion] = [:]
    /// The last deletion, for the "Undo" bar, until it is sent or undone.
    @Published private(set) var lastDeleted: Deletion?
    @Published private(set) var deleteError: String?
    /// A recurring event ⌫ was pressed on: the panel asks which
    /// occurrences to delete.
    @Published var askingDeleteScope: CalendarEvent?
    private var deleteTasks: [String: Task<Void, Never>] = [:]

    /// The event editor beside the week grid: what it edits, and the
    /// times and guests it has now, which the grid draws, with the
    /// guests' availability, and changes on a click.
    struct Composing: Identifiable {
        enum Mode {
            case create
            case edit(CalendarEvent)
            case duplicate(CalendarEvent)
        }

        let id = UUID()
        let mode: Mode
        var start: Date
        var end: Date
        /// Lowercased guest emails, the user's account first.
        var people: [String] = []
        var names: [String: String] = [:]
        /// The account that asks Google.
        var account: String?
        var availability: [String: FreeBusy.Availability] = [:]
        /// The people and days `availability` was read for.
        var loadedKey: String?
        var isLoading = false

        /// The event being changed, if any.
        var original: CalendarEvent? {
            if case .edit(let event) = mode { return event }
            return nil
        }

        /// Busy times of the guests and the user, the edited event's old
        /// time left out.
        var busy: [String: [DateInterval]] {
            let own = original.map { DateInterval(start: $0.start, end: max($0.end, $0.start)) }
            var result: [String: [DateInterval]] = [:]
            for email in people {
                if case .busy(let spans) = availability[email] {
                    result[email] = own.map { FreeBusy.removing($0, from: spans) } ?? spans
                }
            }
            return result
        }

        /// Names of the people whose calendar Google does not share.
        var unknown: [String] {
            people.filter { availability[$0] == .unknown }.map { names[$0] ?? $0 }
        }
    }

    @Published var composing: Composing?

    func compose(_ mode: Composing.Mode, start: Date, end: Date) {
        findTime = nil
        askingDeleteScope = nil
        withAnimation(Motion.resize) { composing = Composing(mode: mode, start: start, end: end) }
    }

    func edit(_ event: CalendarEvent) {
        compose(.edit(event), start: event.start, end: event.end)
    }

    func duplicate(_ event: CalendarEvent) {
        compose(.duplicate(event), start: event.start, end: event.end)
    }

    func endComposing() {
        withAnimation(Motion.resize) { composing = nil }
    }

    /// From the editor: its times, account and guests.
    func composingChanged(start: Date, end: Date, account: String?, guests: [(email: String, name: String?)]) {
        guard var session = composing else { return }
        session.start = start
        session.end = end
        session.account = account
        var people: [String] = []
        var names: [String: String] = [:]
        if let account {
            people.append(account.lowercased())
            names[account.lowercased()] = "You"
        }
        for guest in guests where !people.contains(guest.email.lowercased()) {
            let key = guest.email.lowercased()
            people.append(key)
            names[key] = FindTimeBar.firstName(Person(email: guest.email, name: guest.name))
        }
        session.people = people
        session.names = names
        if session.start != composing?.start || session.end != composing?.end || session.people != composing?.people
            || session.account != composing?.account {
            composing = session
        }
    }

    /// From the grid: new times for the editor.
    func setComposingTimes(start: Date, end: Date) {
        composing?.start = start
        composing?.end = end
    }

    /// Reads the guests' availability over `days`, unless already read.
    func loadComposingAvailability(days: [Date]) async {
        guard let session = composing, let account = session.account, let auth,
              session.people.count > 1, let first = days.min(), let last = days.max() else { return }
        let calendar = Calendar.current
        let range = DateInterval(start: calendar.startOfDay(for: first),
                                 end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last)
        let key = "\(account)|\(session.people.joined(separator: ","))|\(range.start.timeIntervalSince1970)"
        guard session.loadedKey != key else { return }
        // Guests come one chip at a time: wait for a pause.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, composing?.id == session.id else { return }
        composing?.isLoading = true
        do {
            var result: [String: FreeBusy.Availability] = [:]
            try await withAccessToken(account, auth: auth) { [api] token in
                result = try await api.freeBusy(token: token, emails: session.people, from: range.start, to: range.end)
            }
            guard composing?.id == session.id else { return }
            composing?.availability = result
            composing?.loadedKey = key
        } catch {
            NSLog("Calbar: reading availability failed: %@", "\(error)")
        }
        if composing?.id == session.id { composing?.isLoading = false }
    }
    static let undoDelay: Duration = .seconds(10)

    private func isBeingDeleted(_ event: CalendarEvent) -> Bool {
        deleting.values.contains { $0.hides(event) }
    }

    /// The user's own event on a calendar they may write.
    func canDelete(_ event: CalendarEvent) -> Bool {
        let own = Set(accounts.accounts.map { $0.email.lowercased() })
        return accounts.canReply(event.accountEmail) && event.isDeletable(own: own)
    }

    /// Same rule as deleting: the user's own event, writable.
    func canEdit(_ event: CalendarEvent) -> Bool { canDelete(event) }

    /// ⌫ on `event`: deletes a single event, asks first for a recurring one.
    func deleteFromKey(_ event: CalendarEvent) {
        if event.isRecurring {
            askingDeleteScope = event
        } else {
            delete(event)
        }
    }

    /// Hides `event` at once and deletes it in Google after `undoDelay`,
    /// unless `undoDelete()` comes first: nothing to recreate, no guest
    /// told twice. A quit within the delay keeps the event.
    func delete(_ event: CalendarEvent, scope: RecurrenceScope = .this) {
        guard canDelete(event), let auth else { return }
        askingDeleteScope = nil
        let deletion = Deletion(event: event, scope: event.isRecurring ? scope : .this)
        let key = deletion.key
        guard deleting[key] == nil else { return }
        deleting[key] = deletion
        lastDeleted = deletion
        deleteError = nil
        NSLog("Calbar: event deleted (%@), sending in %d s", deletion.scope.rawValue, 10)
        deleteTasks[key] = Task {
            try? await Task.sleep(for: Self.undoDelay)
            guard !Task.isCancelled else { return }
            if lastDeleted?.key == key { lastDeleted = nil }
            do {
                try await withAccessToken(event.accountEmail, auth: auth) { [api] token in
                    try await api.delete(token: token, event: event, scope: deletion.scope)
                }
                NSLog("Calbar: event deletion sent")
                deleteTasks[key] = nil
                await refresh()
                deleting[key] = nil
            } catch {
                NSLog("Calbar: event deletion failed: %@", "\(error)")
                deleteTasks[key] = nil
                deleting[key] = nil
                deleteError = describeCreate(error).replacingOccurrences(of: "add the event", with: "delete the event")
            }
        }
    }

    /// Brings back the last deletion while it still waits.
    func undoDelete() {
        guard let deletion = lastDeleted else { return }
        deleteTasks[deletion.key]?.cancel()
        deleteTasks[deletion.key] = nil
        deleting[deletion.key] = nil
        lastDeleted = nil
        NSLog("Calbar: deletion undone")
    }

    func dismissDeleteError() {
        deleteError = nil
    }

    /// Events loaded so far, today's window and the cached days.
    var loadedEvents: [CalendarEvent] { rawEvents + dayCache.values.flatMap { $0 } }

    /// Each account's primary calendar from 60 days back to 30 ahead, for
    /// guest suggestions. Failures are skipped: suggestions are a bonus.
    func recentPrimaryEvents() async -> [CalendarEvent] {
        guard let auth else { return [] }
        let now = Date()
        let from = now.addingTimeInterval(-60 * 86_400), to = now.addingTimeInterval(30 * 86_400)
        var result: [CalendarEvent] = []
        for account in accounts.accounts where !account.needsReconnect {
            guard let primary = account.calendars.first(where: \.isPrimary) else { continue }
            do {
                let token = try await auth.accessToken(for: account.email)
                result += try await api.events(token: token, source: primary, accountEmail: account.email,
                                               from: from, to: to, calendar: .current)
            } catch {
                NSLog("Calbar: recent events for suggestions failed: %@", "\(error)")
            }
        }
        return result
    }

    /// People matching `query` in the Google contacts, other contacts and
    /// directory of every account granted them, searched concurrently.
    /// A failing source is skipped: suggestions are a bonus. Logs counts
    /// only.
    func searchPeople(_ query: String) async -> [ContactIndex.Contact] {
        guard let auth, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let people = PeopleAPI()
        let targets = accounts.accounts.filter { !$0.needsReconnect && !$0.contactSources.isEmpty }
        return await withTaskGroup(of: [ContactIndex.Contact].self) { group in
            for account in targets {
                group.addTask {
                    guard let token = try? await auth.accessToken(for: account.email) else { return [] }
                    var found: [ContactIndex.Contact] = []
                    for source in account.contactSources {
                        do {
                            found += try await people.search(source, query: query, token: token)
                        } catch {
                            NSLog("Calbar: a people search source failed: %@", "\(error)".prefix(160).description)
                        }
                    }
                    return found
                }
            }
            var all: [ContactIndex.Contact] = []
            for await found in group { all += found }
            return all
        }
    }

    /// Creates `event` in one of `email`'s calendars, then refreshes so
    /// it shows. Throws for the form to show the error.
    func create(_ event: NewEvent, in email: String) async throws {
        guard let auth else { throw OAuthError.invalidGrant }
        NSLog("Calbar: creating an event")
        do {
            try await withAccessToken(email, auth: auth) { [api] token in
                try await api.insert(token: token, event: event)
            }
        } catch APIError.insufficientScope {
            accounts.markReadOnly(email)
            throw APIError.insufficientScope
        } catch OAuthError.invalidGrant {
            accounts.setNeedsReconnect(true, email: email)
            throw OAuthError.invalidGrant
        }
        NSLog("Calbar: event created")
        await refresh()
    }

    /// Saves the editor's changes to `original`, or to its whole series,
    /// then refreshes. Throws for the form to show the error.
    func update(_ original: CalendarEvent, to draft: NewEvent, notesText: String, scope: RecurrenceScope) async throws {
        guard let auth else { throw OAuthError.invalidGrant }
        let email = original.accountEmail
        NSLog("Calbar: updating an event (%@)", scope.rawValue)
        do {
            try await withAccessToken(email, auth: auth) { [api] token in
                try await api.update(token: token, original: original, draft: draft, notesText: notesText, scope: scope)
            }
        } catch APIError.insufficientScope {
            accounts.markReadOnly(email)
            throw APIError.insufficientScope
        } catch OAuthError.invalidGrant {
            accounts.setNeedsReconnect(true, email: email)
            throw OAuthError.invalidGrant
        }
        NSLog("Calbar: event updated")
        await refresh()
    }

    // MARK: finding a time

    /// The week grid shows the guests' availability for `event`: their
    /// busy times, and the slots where it fits for everyone shown.
    struct FindTime {
        let event: CalendarEvent
        /// The guests and the user, in the event's order, the user first.
        let people: [Person]
        /// Lowercased emails shown; everyone at first.
        var shown: Set<String>
        var availability: [String: FreeBusy.Availability] = [:]
        var loaded: DateInterval?
        var isLoading = false
        var error: String?
        /// The user may move it: their own event.
        let canMove: Bool

        /// Busy times of the people shown whose calendar Google shares,
        /// the meeting's own time left out.
        var busy: [String: [DateInterval]] {
            let own = DateInterval(start: event.start, end: max(event.end, event.start))
            var result: [String: [DateInterval]] = [:]
            for email in shown {
                if case .busy(let spans) = availability[email] { result[email] = FreeBusy.removing(own, from: spans) }
            }
            return result
        }
    }

    @Published var findTime: FindTime?

    func startFindingTime(for event: CalendarEvent) {
        var seen = Set<String>()
        let me = event.attendees.first(where: \.isSelf)?.person ?? Person(email: event.accountEmail, name: nil)
        let people = ([me] + event.attendees.filter { !$0.isSelf }.map(\.person))
            .filter { seen.insert($0.email.lowercased()).inserted }
        composing = nil
        findTime = FindTime(event: event, people: people, shown: Set(people.map { $0.email.lowercased() }),
                            canMove: canEdit(event))
    }

    func endFindingTime() {
        findTime = nil
    }

    /// Everyone shown, or only `email` when everyone was; otherwise
    /// `email` in or out.
    func toggleShown(_ email: String) {
        guard var session = findTime else { return }
        let key = email.lowercased()
        let everyone = Set(session.people.map { $0.email.lowercased() })
        if session.shown == everyone {
            session.shown = [key]
        } else if session.shown.contains(key) {
            session.shown.remove(key)
            if session.shown.isEmpty { session.shown = everyone }
        } else {
            session.shown.insert(key)
        }
        findTime = session
    }

    func showEveryone() {
        guard var session = findTime else { return }
        session.shown = Set(session.people.map { $0.email.lowercased() })
        findTime = session
    }

    /// Reads the availability of everyone over `days`, unless already
    /// read; asked as the event's account.
    func loadAvailability(days: [Date]) async {
        guard let session = findTime, let auth, let first = days.min(), let last = days.max() else { return }
        let calendar = Calendar.current
        let range = DateInterval(start: calendar.startOfDay(for: first),
                                 end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last)
        if let loaded = session.loaded, loaded.start <= range.start, loaded.end >= range.end { return }
        let id = session.event.id
        findTime?.isLoading = true
        findTime?.error = nil
        do {
            var result: [String: FreeBusy.Availability] = [:]
            try await withAccessToken(session.event.accountEmail, auth: auth) { [api] token in
                result = try await api.freeBusy(token: token, emails: session.people.map(\.email),
                                                from: range.start, to: range.end)
            }
            guard findTime?.event.id == id else { return }
            findTime?.availability = result
            findTime?.loaded = range
            findTime?.isLoading = false
            NSLog("Calbar: availability of %d people read", result.count)
        } catch {
            guard findTime?.event.id == id else { return }
            NSLog("Calbar: reading availability failed: %@", "\(error)")
            findTime?.isLoading = false
            findTime?.error = describe(error)
        }
    }

    /// Moves the occurrence to start at `start`, same length, guests told.
    func move(_ event: CalendarEvent, to start: Date) async throws {
        let notes = HTMLText.plainText(event.notes ?? "")
        var draft = NewEvent(title: event.title == "(No title)" ? "" : event.title, start: start,
                             end: start.addingTimeInterval(event.end.timeIntervalSince(event.start)),
                             calendarID: event.calendarID, addMeet: false, location: event.location ?? "",
                             notes: notes, guests: event.attendees.filter { !$0.isSelf }.map(\.person.email))
        draft.isAllDay = event.isAllDay
        try await update(event, to: draft, notesText: notes, scope: .this)
    }

    /// Declined events answered while the popover was open leave the list.
    func popoverDidClose() {
        composing = nil
        findTime = nil
        recentlyAnswered = recentlyAnswered.intersection(pendingAnswers)
    }

    /// Runs `body` with the account's access token, once more with a fresh
    /// token after a 401.
    private func withAccessToken(
        _ email: String, auth: GoogleAuth, _ body: (String) async throws -> Void
    ) async throws {
        do {
            try await body(try await auth.accessToken(for: email))
        } catch APIError.unauthorized {
            try await body(try await auth.accessToken(for: email, forceRefresh: true))
        }
    }

    private func apply(_ response: ResponseStatus, to id: String) {
        func change(_ events: inout [CalendarEvent]) {
            for i in events.indices where events[i].id == id {
                events[i] = events[i].answering(response)
            }
        }
        change(&rawEvents)
        dayCache.modifyValues(change)
    }

    private func overlayAnswers(_ events: [CalendarEvent], fetchStarted: Date) -> [CalendarEvent] {
        guard !answerOverlay.isEmpty else { return events }
        return events.map { event in
            guard let answer = answerOverlay[event.id], event.selfResponse != answer.response else { return event }
            if let confirmed = answer.confirmedAt, confirmed <= fetchStarted { return event }
            return event.answering(answer.response)
        }
    }

    /// A refresh started after the confirmation has Google's own answer.
    private func dropConfirmedAnswers(fetchedSince started: Date) {
        answerOverlay = answerOverlay.filter { _, answer in
            guard let confirmed = answer.confirmedAt else { return true }
            return confirmed > started
        }
    }

    private func showAnswerError(_ message: String, for id: String) {
        answerErrors[id] = message
        Task {
            try? await Task.sleep(for: .seconds(5))
            if answerErrors[id] == message { answerErrors[id] = nil }
        }
    }

    func forget(_ email: String) {
        rawEvents.removeAll { $0.accountEmail == email }
        dayCache.modifyValues { $0.removeAll { $0.accountEmail == email } }
        settledAccounts.remove(email)
        saveCache()
    }

    private func tick() {
        let previous = now
        now = Date()
        if !Calendar.current.isDate(previous, inSameDayAs: now) {
            Task { await refresh() }
        }
    }

    // MARK: cache

    private struct Cache: Codable {
        let fetchedAt: Date
        let events: [CalendarEvent]
        /// Accounts settled when the cache was written. Missing in caches
        /// written before this field: every saved account counts then.
        var accounts: [String]?
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Calbar/events.json")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        rawEvents = cache.events
        lastFetch = cache.fetchedAt
        settledAccounts = Set(cache.accounts ?? accounts.accounts.map(\.email))
    }

    private func saveCache() {
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Cache(fetchedAt: lastFetch ?? Date(), events: rawEvents,
                                                                  accounts: Array(settledAccounts))) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
