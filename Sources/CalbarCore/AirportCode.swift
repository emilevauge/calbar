import Foundation

/// IATA city codes, to title the grid's hour columns in three letters.
public enum AirportCode {
    /// "PAR" for Paris or Europe/Paris; the zone's abbreviation ("EST",
    /// "GMT+1") for a city missing from the table.
    public static func code(city: String?, zone: TimeZone) -> String {
        let zoneCity = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        for name in [city, zoneCity].compactMap({ $0 }) {
            if let code = table[name.lowercased()] { return code }
        }
        return zone.abbreviation() ?? zone.identifier
    }

    // shortcut: main cities and the zone cities of macOS only, add more when one is missing.
    static let table: [String: String] = [
        // Europe
        "paris": "PAR", "lyon": "LYS", "marseille": "MRS", "nice": "NCE", "toulouse": "TLS",
        "bordeaux": "BOD", "nantes": "NTE", "lille": "LIL", "strasbourg": "SXB", "montpellier": "MPL",
        "london": "LON", "manchester": "MAN", "edinburgh": "EDI", "dublin": "DUB", "berlin": "BER",
        "munich": "MUC", "frankfurt": "FRA", "hamburg": "HAM", "amsterdam": "AMS", "brussels": "BRU",
        "luxembourg": "LUX", "zurich": "ZRH", "geneva": "GVA", "vienna": "VIE", "prague": "PRG",
        "warsaw": "WAW", "budapest": "BUD", "rome": "ROM", "milan": "MIL", "madrid": "MAD",
        "barcelona": "BCN", "lisbon": "LIS", "porto": "OPO", "athens": "ATH", "istanbul": "IST",
        "copenhagen": "CPH", "stockholm": "STO", "oslo": "OSL", "helsinki": "HEL", "reykjavik": "REK",
        "moscow": "MOW", "kyiv": "IEV", "kiev": "IEV", "bucharest": "BUH", "sofia": "SOF",
        "belgrade": "BEG", "zagreb": "ZAG", "riga": "RIX", "vilnius": "VNO", "tallinn": "TLL",
        "monaco": "MCM", "malta": "MLA", "andorra": "ALV",
        // Americas
        "new york": "NYC", "boston": "BOS", "washington": "WAS", "chicago": "CHI", "detroit": "DTT",
        "toronto": "YTO", "montreal": "YMQ", "vancouver": "YVR", "denver": "DEN", "phoenix": "PHX",
        "los angeles": "LAX", "san francisco": "SFO", "seattle": "SEA", "las vegas": "LAS",
        "miami": "MIA", "atlanta": "ATL", "dallas": "DFW", "houston": "HOU", "austin": "AUS",
        "anchorage": "ANC", "honolulu": "HNL", "mexico city": "MEX", "cancun": "CUN",
        "sao paulo": "SAO", "são paulo": "SAO", "rio de janeiro": "RIO", "buenos aires": "BUE",
        "santiago": "SCL", "lima": "LIM", "bogota": "BOG", "bogotá": "BOG", "caracas": "CCS",
        "panama": "PTY", "havana": "HAV", "halifax": "YHZ",
        // Asia, Oceania
        "tokyo": "TYO", "osaka": "OSA", "seoul": "SEL", "shanghai": "SHA", "beijing": "BJS",
        "hong kong": "HKG", "taipei": "TPE", "singapore": "SIN", "kuala lumpur": "KUL",
        "bangkok": "BKK", "jakarta": "JKT", "manila": "MNL", "ho chi minh": "SGN", "hanoi": "HAN",
        "kolkata": "CCU", "calcutta": "CCU", "mumbai": "BOM", "delhi": "DEL", "new delhi": "DEL",
        "bangalore": "BLR", "bengaluru": "BLR", "karachi": "KHI", "dhaka": "DAC", "kathmandu": "KTM",
        "colombo": "CMB", "dubai": "DXB", "abu dhabi": "AUH", "doha": "DOH", "riyadh": "RUH",
        "tel aviv": "TLV", "jerusalem": "JRS", "tehran": "THR", "tashkent": "TAS", "almaty": "ALA",
        "sydney": "SYD", "melbourne": "MEL", "brisbane": "BNE", "perth": "PER", "adelaide": "ADL",
        "auckland": "AKL", "wellington": "WLG",
        // Africa
        "cairo": "CAI", "casablanca": "CAS", "marrakech": "RAK", "algiers": "ALG", "tunis": "TUN",
        "dakar": "DKR", "lagos": "LOS", "abidjan": "ABJ", "nairobi": "NBO", "johannesburg": "JNB",
        "cape town": "CPT", "addis ababa": "ADD", "reunion": "RUN", "mauritius": "MRU",
    ]
}
