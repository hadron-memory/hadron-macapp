import Foundation

/// A Hadron memory as returned by `memories` (the uniform #473 read surface).
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

/// A graph node as returned by `findNodes` hits.
struct HadronNode: Decodable, Identifiable, Hashable {
    let id: String
    let loc: String
    let name: String
    let description: String?
    let nodeType: String
    /// Fully-qualified node URN, composed server-side from the node's memory
    /// URN + loc (#481) and carried by every Node-returning surface. We consume
    /// it as-is rather than re-deriving it so the app stays agnostic to the URN
    /// grammar (the server owns composition; cf. hadron-server#691).
    let nodeURN: String?
    let memory: NodeMemory?

    struct NodeMemory: Decodable, Hashable {
        let urn: String
        let name: String
    }

    private enum CodingKeys: String, CodingKey {
        case id, loc, name, description, nodeType, memory
        case nodeURN = "urn"
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
    /// Apollo-style error metadata; `code` carries machine-readable kinds
    /// like BAD_USER_INPUT (used to retry sanitized searches).
    let extensions: Extensions?

    struct Extensions: Decodable {
        let code: String?
    }
}
