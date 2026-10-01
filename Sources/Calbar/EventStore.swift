import AppKit
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
        let enabled = raw.filter { accounts.isEnabled(calendarID: $0.calendarID, email: $0.accountEmail) }
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

    /// Declined events answered while the popover was open leave the list.
    func popoverDidClose() {
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
