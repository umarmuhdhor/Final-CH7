import Foundation

/// A JSON array decoded one element at a time (issue #493 part 1). An element that does not decode
/// (a wrong type, a missing field, a value or nested object this build does not know, `null`) is left out
/// and the rest are kept, so one row from a newer server can't make a whole list fail to load.
///
/// Only the elements are forgiven: a value that is not an array still throws, so a response that
/// breaks the contract is still `RepositoryError.decoding`.
struct LossyList<Element: Decodable>: Decodable {
    let elements: [Element]
    /// How many elements were left out.
    let dropped: Int
    /// Where the first left-out element failed, as contract field names only (logged; never a row value).
    let firstProblem: String?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var dropped = 0
        var firstProblem: String?
        while !container.isAtEnd {
            let index = container.currentIndex
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                dropped += 1
                if firstProblem == nil { firstProblem = Self.field(of: error, below: decoder.codingPath.count) }
                // A failed decode leaves the container on the same element (both Foundation JSONDecoders do;
                // the protocol does not promise it, hence the index check): step over it.
                if container.currentIndex == index, try !container.decodeNil() {
                    _ = try container.decode(Skipped.self)
                }
                // Never loop on one element (a decoder that neither decodes nor skips it).
                guard container.currentIndex > index else { throw error }
            }
        }
        self.elements = elements
        self.dropped = dropped
        self.firstProblem = firstProblem
        if dropped > 0 {
            // Field names from the contract and counts only: never a value from the row (P6).
            let list = decoder.codingPath.map(\.stringValue).joined(separator: ".")
            Log.data.error(
                "List rows did not match the contract and were left out",
                "\(list): \(dropped) of \(dropped + elements.count), first at \(firstProblem ?? "?")"
            )
        }
    }

    /// Where in the row decoding failed, as contract field names (`signals.[].label`); `[]` stands for an index.
    /// Keys are only ever struct field names: if a row ever gets a `[String: X]` field, its keys are data and
    /// must not be printed here.
    private static func field(of error: any Error, below depth: Int) -> String {
        guard let error = error as? DecodingError else { return "?" }
        var path: [any CodingKey]
        switch error {
        case .keyNotFound(let key, let context): path = context.codingPath + [key]
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): path = context.codingPath
        @unknown default: return "?"
        }
        // Drop the list's own path and the row index.
        path = Array(path.dropFirst(depth + 1))
        guard !path.isEmpty else { return "(row)" }
        return path.map { $0.intValue == nil ? $0.stringValue : "[]" }.joined(separator: ".")
    }

    /// Decodes from any JSON value without reading it: moves the container past an element it could not decode.
    private struct Skipped: Decodable {
        init(from decoder: Decoder) {}
    }
}

extension LossyList: Sendable where Element: Sendable {}
