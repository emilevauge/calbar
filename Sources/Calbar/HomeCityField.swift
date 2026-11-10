import SwiftUI
import MapKit
import CalbarCore

/// "Home" in the settings: type a city, pick one of Apple Maps'
/// suggestions, and its time zone becomes home.
struct HomeCityField: View {
    @AppStorage(Prefs.homeTimeZoneKey) private var homeTimeZone = ""
    @AppStorage(Prefs.homeCityKey) private var homeCity = ""
    @StateObject private var search = CitySearch()
    @State private var query = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Home") {
                if homeTimeZone.isEmpty {
                    TextField("", text: $query, prompt: Text("Type your city"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .onChange(of: query) { _, text in
                            error = nil
                            search.find(text)
                        }
                } else {
                    HStack(spacing: 6) {
                        Text(label).foregroundStyle(.secondary)
                        Button {
                            homeTimeZone = ""
                            homeCity = ""
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Change the home city")
                    }
                }
            }
            if homeTimeZone.isEmpty, !query.isEmpty {
                ForEach(search.results.prefix(5), id: \.self) { result in
                    Button {
                        pick(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        // The window gives its first field the focus: not this one.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    private var label: String {
        let zone = TimeZone(identifier: homeTimeZone).map { HomeClock.name($0, at: Date()) } ?? homeTimeZone
        return homeCity.isEmpty ? zone : "\(homeCity) · \(zone)"
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        Task {
            let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start()
            guard let zone = response?.mapItems.first?.timeZone else {
                error = "No time zone found for \(result.title)."
                return
            }
            homeCity = result.title
            homeTimeZone = zone.identifier
        }
    }
}

/// Apple Maps' city suggestions for what is typed.
@MainActor
private final class CitySearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.delegate = self
    }

    func find(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
        } else {
            completer.queryFragment = text
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        // Cities and regions, not street addresses.
        let places = found.filter { !$0.title.contains(where: \.isNumber) }
        Task { @MainActor in self.results = places }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
