import Foundation

/// A Hadron memory as returned by `myMemories`.
struct Memory: Decodable, Identifiable, Hashable {
    let id: String
    let urn: String
    let name: String
    let shortDescription: String?
    /// Memory class: system | app | knowledge | personal | group | private.
    let memoryClass: String?

    private enum CodingKeys: String, CodingKey {
        case id, urn, name, shortDescription
        case memoryClass = "class"
    }
}

/// A graph node as returned by `nodes`.
struct HadronNode: Decodable, Identifiable, Hashable {
    let id: String
    let loc: String
    let name: String
    let description: String?
    let nodeType: String
    let memory: NodeMemory?

    struct NodeMemory: Decodable, Hashable {
        let urn: String
        let name: String
    }

    /// Fully-qualified node URN, composed from the owning memory's URN and the
    /// node's loc (`hrn:memory:…` → `hrn:node:…::<loc>`).
    var nodeURN: String? {
        guard let memoryURN = memory?.urn else { return nil }
        let prefix = "hrn:memory:"
        guard memoryURN.hasPrefix(prefix) else { return nil }
        let base = "hrn:node:" + memoryURN.dropFirst(prefix.count)
        return "\(base)::\(loc)"
    }
}

/// The authenticated user (`me`).
struct MeUser: Decodable {
    let id: String
    let name: String?
    let email: String?
    let handle: String?

    var displayName: String {
        handle ?? name ?? email ?? "Signed in"
    }
}

// MARK: - GraphQL envelope

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}
