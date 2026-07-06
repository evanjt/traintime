import Compression
import Foundation
import WatchConnectivity

// Port of android/core data/sbb/SbbTripDecoder.kt + SbbShareService.kt +
// data/prefs/PendingRouteStore.kt. One file so everything rides one target
// membership (phone + watch).

/// An SBB Mobile trip link found in shared text. Three shapes carry the same
/// payload: the a.sbbmobile.ch short link (resolved via its splash page), the
/// sbbmobile:// app link, and the www.sbb.ch web link.
enum SBBShareLink: Equatable {
    case short(String)
    case blob(String)

    static func find(in text: String) -> SBBShareLink? {
        if let url = text.firstMatch(of: #"https?://a\.sbbmobile\.ch/s/[A-Za-z0-9]+"#) {
            return .short(url)
        }
        if let blob = text.firstMatchGroup(of: #"sbbmobile://trip\?recon=([A-Za-z0-9_.\-]+)"#) {
            return .blob(blob)
        }
        if let blob = text.firstMatchGroup(of: #"https?://[^\s"']*sbb\.ch/[^\s"']*trip\?tripId=([A-Za-z0-9_.\-]+)"#) {
            return .blob(blob)
        }
        return nil
    }
}

enum SBBDecodeError: Error {
    case unsupportedVersion
    case malformed
    case noRideLegs
}

/// Decodes the SBB Mobile trip blob: `3HA.<recon>.<query>`, each segment
/// base64url + zlib deflate. The recon segment is a HAFAS reconstruction
/// context: `¶`-separated sections, the HKI section holds `§`-separated legs
/// with `$`-separated fields and `@`-separated k=v locations. Times are
/// Swiss-local `yyyyMMddHHmm`. Proprietary and undocumented, hence the
/// version guard and the blanket malformed catch.
enum SBBTripDecoder {
    static let supportedVersion = "3HA"

    private static let zurich = TimeZone(identifier: "Europe/Zurich")!

    static func extractBlob(fromHTML html: String) -> String? {
        html.firstMatchGroup(of: #"sbbmobile://trip\?recon=([A-Za-z0-9_.\-]+)"#)
            ?? html.firstMatchGroup(of: #"sbb\.ch/[^\s"']*trip\?tripId=([A-Za-z0-9_.\-]+)"#)
    }

    static func decode(blob: String) throws -> SharedRoute {
        let parts = blob.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { throw SBBDecodeError.malformed }
        guard parts[0] == supportedVersion else { throw SBBDecodeError.unsupportedVersion }
        guard let recon = inflate(parts[1]),
              let hki = section(recon, name: "HKI") else { throw SBBDecodeError.malformed }
        let legs = try hki.components(separatedBy: "§").map { try parseLeg($0) }
        guard legs.contains(where: { $0.type == .ride }) else { throw SBBDecodeError.noRideLegs }
        return SharedRoute(legs: legs, sourceBlob: blob)
    }

    private static func inflate(_ segment: String) -> String? {
        var b64 = segment.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let raw = Data(base64Encoded: b64), let out = raw.zlibInflated() else { return nil }
        // Lossy on purpose: the recon carries binary sections (protobuf tail)
        // that aren't valid UTF-8; the HKI text we parse is. Matches Kotlin's
        // replacing String(bytes, UTF_8).
        return String(decoding: out, as: UTF8.self)
    }

    /// Sections come as ¶NAME¶value¶NAME¶value…
    private static func section(_ recon: String, name: String) -> String? {
        let parts = recon.components(separatedBy: "¶")
        var i = 1
        while i < parts.count - 1 {
            if parts[i] == name { return parts[i + 1] }
            i += 2
        }
        return nil
    }

    /// Leg shape: <kind>$<fromLoc>$<toLoc>$<dep>$<arr>$<line>$… where kind is
    /// T (ride), W (walk) or G@F (footpath with raw coordinates).
    private static func parseLeg(_ raw: String) throws -> RouteLeg {
        guard let kind = raw.first, let dollar = raw.firstIndex(of: "$") else {
            throw SBBDecodeError.malformed
        }
        let fields = raw[raw.index(after: dollar)...].components(separatedBy: "$")
        guard fields.count >= 5 else { throw SBBDecodeError.malformed }
        let from = parseLocation(fields[0])
        let to = parseLocation(fields[1])
        guard let dep = epoch(fromLocal: fields[2]), let arr = epoch(fromLocal: fields[3]) else {
            throw SBBDecodeError.malformed
        }
        let line = fields[4].trimmingCharacters(in: .whitespaces)
        let lineParts = line.split(separator: " ").map(String.init)
        let isRide = kind == "T" && !line.isEmpty
        return RouteLeg(
            type: kind == "T" ? .ride : .walk,
            originId: from.id,
            originName: from.name,
            originLat: from.lat,
            originLon: from.lon,
            destId: to.id,
            destName: to.name,
            destLat: to.lat,
            destLon: to.lon,
            depTs: dep,
            arrTs: arr,
            category: isRide ? lineParts.first : nil,
            lineNumber: isRide && lineParts.count > 1 ? lineParts[1] : nil,
            trainNumber: isRide && lineParts.count > 2 ? lineParts[2] : nil
        )
    }

    /// A=1@O=Sion@X=7359199@Y=46227549@L=8501506@a=128@
    private static func parseLocation(_ token: String) -> (name: String, id: String?, lat: Double?, lon: Double?) {
        var fields: [String: String] = [:]
        for part in token.components(separatedBy: "@") {
            guard let eq = part.firstIndex(of: "=") else { continue }
            fields[String(part[..<eq])] = String(part[part.index(after: eq)...])
        }
        return (
            name: fields["O"] ?? "",
            id: fields["L"],
            lat: fields["Y"].flatMap(Double.init).map { $0 / 1e6 },
            lon: fields["X"].flatMap(Double.init).map { $0 / 1e6 }
        )
    }

    static func epoch(fromLocal value: String) -> Int? {
        guard value.count == 12,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.dropFirst(6).prefix(2)),
              let hour = Int(value.dropFirst(8).prefix(2)),
              let minute = Int(value.dropFirst(10).prefix(2)) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zurich
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: comps).map { Int($0.timeIntervalSince1970) }
    }
}

/// Resolves a shared SBB link into a route. Short links return a splash page
/// (plain 200, no redirect) whose HTML embeds the blob in two anchors, one
/// GET plus a regex. This talks to a.sbbmobile.ch, not api.traintime.ch, so
/// no API key is sent.
enum SBBShareService {
    static func resolve(_ link: SBBShareLink) async throws -> SharedRoute {
        switch link {
        case .blob(let blob):
            return try SBBTripDecoder.decode(blob: blob)
        case .short(let url):
            guard let requestURL = URL(string: url) else { throw SBBDecodeError.malformed }
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            guard let blob = SBBTripDecoder.extractBlob(fromHTML: html) else {
                throw SBBDecodeError.malformed
            }
            return try SBBTripDecoder.decode(blob: blob)
        }
    }
}

/// Persists the queued shared route (FavouritesStore pattern). Stored as a
/// JSON array so a later multi-route version is a cap change, not a
/// migration; 0.6.0 keeps exactly one. Phone-owned: the phone publishes it
/// over WCSession applicationContext, the watch only applies.
class PendingRouteStore: ObservableObject {
    static let shared = PendingRouteStore()

    private static let key = "pendingRoutes_v1"
    private static let contextKey = "pendingRoute"

    @Published private(set) var pending: PendingRoute?

    init() {
        pending = Self.load()
    }

    func reload() {
        pending = Self.load()
    }

    func save(_ route: PendingRoute) {
        pending = route
        persist()
        syncToCounterpart()
    }

    /// Transform the stored route; returning nil clears it.
    func update(_ transform: (PendingRoute) -> PendingRoute?) {
        guard let current = pending else { return }
        let next = transform(current)
        guard next != current else { return }
        pending = next
        persist()
        syncToCounterpart()
    }

    /// Toggle a leg's track/notify state from the route view. The caller
    /// reschedules the reminder afterwards (notifyTs now skips muted legs).
    func setLegMuted(_ index: Int, muted: Bool) {
        update { route in
            var set = Set(route.mutedLegIndices ?? [])
            if muted { set.insert(index) } else { set.remove(index) }
            var next = route
            next.mutedLegIndices = set.sorted()
            return next
        }
    }

    func clear() {
        guard pending != nil else { return }
        pending = nil
        persist()
        syncToCounterpart()
    }

    private func persist() {
        let store = SharedDefaults.store
        if let route = pending, let data = try? JSONEncoder().encode([route]) {
            store.set(data, forKey: Self.key)
        } else {
            store.removeObject(forKey: Self.key)
        }
    }

    private static func load() -> PendingRoute? {
        guard let data = SharedDefaults.store.data(forKey: key) else { return nil }
        return (try? JSONDecoder().decode([PendingRoute].self, from: data))?.first
    }

    // MARK: - WCSession sync (phone → watch only)

    /// updateApplicationContext merges our copied dict, so a cleared route
    /// needs an explicit empty-Data tombstone (unlike favourites, which are
    /// never absent once set).
    func syncToCounterpart() {
        #if os(iOS)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var context = WCSession.default.applicationContext
        if let route = pending, let data = try? JSONEncoder().encode(route) {
            context[Self.contextKey] = data
        } else {
            context[Self.contextKey] = Data()
        }
        try? WCSession.default.updateApplicationContext(context)
        #endif
    }

    func handleReceivedContext(_ context: [String: Any]) {
        #if os(watchOS)
        guard let data = context[Self.contextKey] as? Data else { return }
        pending = data.isEmpty ? nil : try? JSONDecoder().decode(PendingRoute.self, from: data)
        persist()
        #endif
    }
}

// MARK: - Helpers

extension String {
    /// First whole-pattern match in the string.
    func firstMatch(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range, in: self) else { return nil }
        return String(self[range])
    }

    /// First capture group of the first match.
    func firstMatchGroup(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }
}

extension Data {
    /// zlib-wrapped deflate → plain bytes. Compression's COMPRESSION_ZLIB is
    /// raw deflate, so skip the 2-byte zlib header; the raw decoder stops at
    /// end-of-stream, ignoring the adler32 trailer.
    func zlibInflated() -> Data? {
        guard count > 2, self[startIndex] == 0x78 else { return nil }
        let source = Data(dropFirst(2))
        return source.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { streamPointer.deallocate() }
            guard compression_stream_init(streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(streamPointer) }
            streamPointer.pointee.src_ptr = base
            streamPointer.pointee.src_size = source.count

            let bufferSize = 64 * 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            var output = Data()
            while true {
                streamPointer.pointee.dst_ptr = buffer
                streamPointer.pointee.dst_size = bufferSize
                let status = compression_stream_process(streamPointer, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: bufferSize - streamPointer.pointee.dst_size)
                switch status {
                case COMPRESSION_STATUS_END: return output
                case COMPRESSION_STATUS_OK: continue
                default: return nil
                }
            }
        }
    }
}
