import Foundation

/// The parts of a GTFS-realtime feed the app reads: the feed's time; from TripUpdates (TT-131, D36), each trip's
/// cancellation, skipped stops, delays and times; from Alerts (TT-132, D37), each service alert's id, active periods,
/// informed routes and text. Decoded by hand from the protobuf wire format, because the app takes no runtime
/// dependencies (D6). Field numbers follow `gtfs-realtime.proto`. Feed types stay inside the GTFS repository, and
/// screens read `LiveSnapshot` and `LineNotice`.
struct GTFSRealtimeFeed: Sendable, Equatable {
    struct TripUpdate: Sendable, Equatable {
        var tripId = ""
        /// The service date, "20261109". Nil when the feed leaves it out.
        var startDate: String?
        /// CANCELED or DELETED.
        var isCancelled = false
        var stopTimeUpdates: [StopTimeUpdate] = []
        var timestamp: Date?
        /// A delay in seconds for the whole trip (an experimental field), used only when no stop says more.
        var delay: Int?
    }

    struct StopTimeUpdate: Sendable, Equatable {
        enum Relationship: Sendable, Equatable {
            case scheduled
            case skipped
            /// NO_DATA or UNSCHEDULED: there is no estimate for this stop.
            case noData
        }

        var stopId: String?
        var arrival: Event?
        var departure: Event?
        var relationship = Relationship.scheduled
    }

    struct Event: Sendable, Equatable {
        /// Seconds late; negative is early.
        var delay: Int?
        var time: Date?
    }

    /// A service alert (TT-132).
    struct Alert: Sendable, Equatable {
        /// The feed entity's id. Dismissing a line notice hides this id only.
        var id = ""
        /// When it applies; none means always.
        var activePeriods: [ActivePeriod] = []
        var informedEntities: [InformedEntity] = []
        /// The English header text, else the first translation.
        var header: String?
        var description: String?
    }

    struct ActivePeriod: Sendable, Equatable {
        /// Nil: open-ended.
        var start: Date?
        var end: Date?
    }

    /// What an alert is about: a route, a stop, a trip, or several of them together.
    struct InformedEntity: Sendable, Equatable {
        var routeId: String?
        var stopId: String?
        /// The entity names a trip, so it is about that trip, not the whole line.
        var hasTrip = false
    }

    /// When the producer wrote the feed.
    var timestamp: Date?
    var tripUpdates: [TripUpdate] = []
    var alerts: [Alert] = []
}

extension GTFSRealtimeFeed {
    enum DecodingError: Error, Equatable {
        case truncated
        case unsupportedWireType(Int)
    }

    /// Decodes a `FeedMessage`. Fields the app does not read are skipped.
    init(protobuf data: Data) throws {
        var message = ProtobufReader(data)
        while let field = try message.next() {
            switch (field.number, field.wireType) {
            case (1, 2): // header
                var header = try message.message()
                while let field = try header.next() {
                    if field.number == 3, field.wireType == 0 {
                        timestamp = try Self.date(header.varint())
                    } else {
                        try header.skip(field)
                    }
                }
            case (2, 2): // entity
                switch try Self.entity(message.message()) {
                case .tripUpdate(let update): tripUpdates.append(update)
                case .alert(let alert): alerts.append(alert)
                case nil: break
                }
            default:
                try message.skip(field)
            }
        }
    }

    private enum Entity {
        case tripUpdate(TripUpdate)
        case alert(Alert)
    }

    private static func entity(_ reader: ProtobufReader) throws -> Entity? {
        var reader = reader
        var id = ""
        var entity: Entity?
        var isDeleted = false
        while let field = try reader.next() {
            switch (field.number, field.wireType) {
            case (1, 2): id = try reader.string()
            case (2, 0): isDeleted = try reader.varint() != 0
            case (3, 2): entity = try .tripUpdate(tripUpdate(reader.message()))
            case (5, 2): entity = try .alert(alert(reader.message()))
            default: try reader.skip(field)
            }
        }
        guard !isDeleted else { return nil }
        if case .alert(var alert) = entity {
            alert.id = id
            return .alert(alert)
        }
        return entity
    }

    private static func alert(_ reader: ProtobufReader) throws -> Alert {
        var reader = reader
        var alert = Alert()
        while let field = try reader.next() {
            switch (field.number, field.wireType) {
            case (1, 2): // active_period
                var range = try reader.message()
                var period = ActivePeriod()
                while let field = try range.next() {
                    switch (field.number, field.wireType) {
                    case (1, 0): period.start = try date(range.varint())
                    case (2, 0): period.end = try date(range.varint())
                    default: try range.skip(field)
                    }
                }
                alert.activePeriods.append(period)
            case (5, 2): // informed_entity
                var selector = try reader.message()
                var entity = InformedEntity()
                while let field = try selector.next() {
                    switch (field.number, field.wireType) {
                    case (2, 2): entity.routeId = try selector.string()
                    case (4, 2):
                        entity.hasTrip = true
                        try selector.skip(field)
                    case (5, 2): entity.stopId = try selector.string()
                    default: try selector.skip(field)
                    }
                }
                alert.informedEntities.append(entity)
            case (10, 2): alert.header = try translated(reader.message())
            case (11, 2): alert.description = try translated(reader.message())
            default: try reader.skip(field)
            }
        }
        return alert
    }

    /// A `TranslatedString`: the English text, else the one with no language, else the first.
    private static func translated(_ reader: ProtobufReader) throws -> String? {
        var reader = reader
        var texts: [(text: String, language: String)] = []
        while let field = try reader.next() {
            guard field.number == 1, field.wireType == 2 else {
                try reader.skip(field)
                continue
            }
            var translation = try reader.message()
            var text = ""
            var language = ""
            while let field = try translation.next() {
                switch (field.number, field.wireType) {
                case (1, 2): text = try translation.string()
                case (2, 2): language = try translation.string()
                default: try translation.skip(field)
                }
            }
            texts.append((text, language.lowercased()))
        }
        let english = texts.first { $0.language == "en" || $0.language.hasPrefix("en-") } ?? texts.first { $0.language.isEmpty }
        return (english ?? texts.first)?.text
    }

    private static func tripUpdate(_ reader: ProtobufReader) throws -> TripUpdate {
        var reader = reader
        var update = TripUpdate()
        while let field = try reader.next() {
            switch (field.number, field.wireType) {
            case (1, 2): // trip
                var trip = try reader.message()
                while let field = try trip.next() {
                    switch (field.number, field.wireType) {
                    case (1, 2): update.tripId = try trip.string()
                    case (3, 2): update.startDate = try trip.string()
                    case (4, 0):
                        let relationship = try trip.varint()
                        update.isCancelled = relationship == 3 || relationship == 7 // CANCELED, DELETED
                    default: try trip.skip(field)
                    }
                }
            case (2, 2): try update.stopTimeUpdates.append(stopTimeUpdate(reader.message()))
            case (4, 0): update.timestamp = try date(reader.varint())
            case (5, 0): update.delay = try int32(reader.varint())
            default: try reader.skip(field)
            }
        }
        return update
    }

    private static func stopTimeUpdate(_ reader: ProtobufReader) throws -> StopTimeUpdate {
        var reader = reader
        var update = StopTimeUpdate()
        while let field = try reader.next() {
            switch (field.number, field.wireType) {
            case (2, 2): update.arrival = try event(reader.message())
            case (3, 2): update.departure = try event(reader.message())
            case (4, 2): update.stopId = try reader.string()
            case (5, 0):
                let relationship = try reader.varint()
                update.relationship = switch relationship {
                case 0: .scheduled
                case 1: .skipped
                default: .noData
                }
            default: try reader.skip(field)
            }
        }
        return update
    }

    private static func event(_ reader: ProtobufReader) throws -> Event {
        var reader = reader
        var event = Event()
        while let field = try reader.next() {
            switch (field.number, field.wireType) {
            case (1, 0): event.delay = try int32(reader.varint())
            case (2, 0): event.time = try date(reader.varint())
            default: try reader.skip(field)
            }
        }
        return event
    }

    /// int32 travels as a 64-bit two's complement varint, so -60 is ten bytes.
    private static func int32(_ value: UInt64) -> Int { Int(Int32(truncatingIfNeeded: value)) }

    /// POSIX seconds; 0 means unset.
    private static func date(_ value: UInt64) -> Date? {
        let seconds = Int64(bitPattern: value)
        return seconds > 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil
    }
}

/// Reads protobuf fields from bytes: varints, length-delimited values and nested messages.
struct ProtobufReader {
    struct Field {
        let number: Int
        let wireType: Int
    }

    private let bytes: [UInt8]
    private var index: Int
    private let end: Int

    init(_ data: Data) {
        bytes = Array(data)
        index = 0
        end = bytes.count
    }

    private init(bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes
        index = range.lowerBound
        end = range.upperBound
    }

    /// The next field's key; nil at the end.
    mutating func next() throws -> Field? {
        guard index < end else { return nil }
        let key = try varint()
        return Field(number: Int(key >> 3), wireType: Int(key & 7))
    }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < end, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw GTFSRealtimeFeed.DecodingError.truncated
    }

    /// A length-delimited field as a reader of its own.
    mutating func message() throws -> ProtobufReader {
        let range = try lengthDelimited()
        return ProtobufReader(bytes: bytes, range: range)
    }

    mutating func string() throws -> String {
        let range = try lengthDelimited()
        return String(decoding: bytes[range], as: UTF8.self)
    }

    mutating func skip(_ field: Field) throws {
        switch field.wireType {
        case 0: _ = try varint()
        case 1: try advance(8)
        case 2: _ = try lengthDelimited()
        case 5: try advance(4)
        default: throw GTFSRealtimeFeed.DecodingError.unsupportedWireType(field.wireType)
        }
    }

    private mutating func lengthDelimited() throws -> Range<Int> {
        let length = try varint()
        guard length <= UInt64(end - index) else { throw GTFSRealtimeFeed.DecodingError.truncated }
        let range = index..<(index + Int(length))
        index = range.upperBound
        return range
    }

    private mutating func advance(_ count: Int) throws {
        guard end - index >= count else { throw GTFSRealtimeFeed.DecodingError.truncated }
        index += count
    }
}
