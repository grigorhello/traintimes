import Foundation

/// GO's seven rail lines and their stations, shipped in the app (TT-206): the first launch lists a line's stations at once,
/// with the timetable not downloaded yet. Ids and names are the GO GTFS feed's (Nov 4, 2026); each line runs from Union
/// outward in the order its trains call (Lakeshore West and Kitchener are checked against `go-gtfs-sample.zip`).
enum GONetwork {
    /// A line with its stations from Union outward; Union itself is not listed.
    struct LineStations: Identifiable, Sendable {
        let line: Line
        let stations: [Station]

        var id: String { line.id }
    }

    /// Union Station GO, where every line meets.
    static let union = Station(id: "UN", name: "Union Station GO", lines: GOLineColor.lines.map(\.name))

    /// The seven lines in GO's map order round Union, west to east (`GOLineColor.lines`): LW, MI, KI, BR, RH, ST, LE.
    static let lines: [LineStations] = GOLineColor.lines.map { id, name in
        LineStations(
            line: Line(id: id, name: name, colorHex: nil),
            stations: (stops[id] ?? []).map { Station(id: $0.0, name: $0.1, lines: [name]) }
        )
    }

    static func line(_ id: String) -> LineStations? {
        lines.first { $0.id == id }
    }

    /// Station id and name by line id, from Union outward.
    private static let stops: [String: [(String, String)]] = [
        "LW": [
            ("EX", "Exhibition GO"),
            ("MI", "Mimico GO"),
            ("LO", "Long Branch GO"),
            ("PO", "Port Credit GO"),
            ("CL", "Clarkson GO"),
            ("OA", "Oakville GO"),
            ("BO", "Bronte GO"),
            ("AP", "Appleby GO"),
            ("BU", "Burlington GO"),
            ("AL", "Aldershot GO"),
            ("WR", "West Harbour GO"),
            ("HA", "Hamilton GO Centre"),
            ("CF", "Confederation GO"),
            ("SCTH", "St. Catharines GO"),
            ("NI", "Niagara Falls GO"),
        ],
        "MI": [
            ("KP", "Kipling GO"),
            ("DI", "Dixie GO"),
            ("CO", "Cooksville GO"),
            ("ER", "Erindale GO"),
            ("SR", "Streetsville GO"),
            ("ME", "Meadowvale GO"),
            ("LS", "Lisgar GO"),
            ("ML", "Milton GO"),
        ],
        "KI": [
            ("BL", "Bloor GO"),
            ("MD", "Mount Dennis GO"),
            ("WE", "Weston GO"),
            ("ET", "Etobicoke North GO"),
            ("MA", "Malton GO"),
            ("BE", "Bramalea GO"),
            ("BR", "Brampton Innovation District GO"),
            ("MO", "Mount Pleasant GO"),
            ("GE", "Georgetown GO"),
            ("AC", "Acton GO"),
            ("GL", "Guelph Central GO"),
            ("KI", "Kitchener GO"),
            ("SF", "Stratford GO"),
        ],
        "BR": [
            ("DW", "Downsview Park GO"),
            ("RU", "Rutherford GO"),
            ("MP", "Maple GO"),
            ("KC", "King City GO"),
            ("AU", "Aurora GO"),
            ("NE", "Newmarket GO"),
            ("EA", "East Gwillimbury GO"),
            ("BD", "Bradford GO"),
            ("BA", "Barrie South GO"),
            ("AD", "Allandale Waterfront GO"),
        ],
        "RH": [
            ("OR", "Oriole GO"),
            ("OL", "Old Cummer GO"),
            ("LA", "Langstaff GO"),
            ("RI", "Richmond Hill GO"),
            ("GO", "Gormley GO"),
            ("BM", "Bloomington GO"),
        ],
        "ST": [
            ("KE", "Kennedy GO"),
            ("AG", "Agincourt GO"),
            ("MK", "Milliken GO"),
            ("UI", "Unionville GO"),
            ("CE", "Centennial GO"),
            ("MR", "Markham GO"),
            ("MJ", "Mount Joy GO"),
            ("ST", "Stouffville GO"),
            ("LI", "Old Elm GO"),
        ],
        "LE": [
            ("DA", "Danforth GO"),
            ("SC", "Scarborough GO"),
            ("EG", "Eglinton GO"),
            ("GU", "Guildwood GO"),
            ("RO", "Rouge Hill GO"),
            ("PIN", "Pickering GO"),
            ("AJ", "Ajax GO"),
            ("WH", "Whitby GO"),
            ("OS", "Durham College Oshawa GO"),
        ],
    ]
}
