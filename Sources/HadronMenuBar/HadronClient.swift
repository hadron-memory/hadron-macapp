import Foundation

/// Errors surfaced to the UI. `unauthorized` means the token was rejected and
/// the app should drop back to the signed-out state (there is no refresh in v1).
enum HadronError: LocalizedError {
    case notAuthenticated
    case unauthorized
    case transport(String)
    case graphQL(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in."
        case .unauthorized: return "Your session expired. Please sign in again."
        case .transport(let m): return m
        case .graphQL(let m): return m
        }
    }
}

/// Thin GraphQL client for the Hadron API. Stateless apart from the bearer
/// token it is constructed with.
struct HadronClient {
    let token: String

    // MARK: Typed operations

    func me() async throws -> MeUser? {
        struct Payload: Decodable { let me: MeUser? }
        let query = "query { me { id name email handle } }"
        return try await run(query, Payload.self).me
    }

    func myMemories() async throws -> [Memory] {
        struct Payload: Decodable { let memories: Page<Memory> }
        // Uniform read surface (hadron-server #473): memories() replaces
        // myMemories and returns an { items, total } page. limit: 200 is the
        // server cap — the old query returned the complete list, so ask for
        // as much as one page allows. (A user with >200 memories would need
        // offset paging; the menu bar list isn't built for that anyway.)
        let query = """
        query($limit: Int) {
          memories(limit: $limit) { items { id urn name shortDescription class } }
        }
        """
        return try await run(query, Payload.self, variables: ["limit": 200]).memories.items
    }

    func taskNodes(memoryId: String? = nil, limit: Int = 200) async throws -> [HadronNode] {
        struct Payload: Decodable { let findNodes: FindNodesResult }
        // Query omitted → findNodes returns a deterministic filtered list
        // (subsumes the old `nodes` query). Scope is a structured NodeFilter:
        // runnable-only, optionally narrowed to one memory.
        let query = """
        query($filter: NodeFilter, $limit: Int) {
          findNodes(filter: $filter, limit: $limit) {
            hits { node { \(Self.nodeFields) } }
          }
        }
        """
        var filter: [String: Any] = ["isRunnable": true]
        if let memoryId { filter["memoryIds"] = [memoryId] }
        let variables: [String: Any] = ["filter": filter, "limit": limit]
        return try await run(query, Payload.self, variables: variables).findNodes.nodes
    }

    func findNodes(search: String, limit: Int = 50) async throws -> [HadronNode] {
        struct Payload: Decodable { let findNodes: FindNodesResult }
        // mode:keyword keeps the old substring-search intent (now stemmed,
        // relevance-ranked Postgres FTS) without pulling in the vector index.
        let query = """
        query($query: String, $limit: Int) {
          findNodes(query: $query, mode: keyword, limit: $limit) {
            hits { node { \(Self.nodeFields) } }
          }
        }
        """
        let variables: [String: Any] = ["query": search, "limit": limit]
        return try await run(query, Payload.self, variables: variables).findNodes.nodes
    }

    private static let nodeFields = """
    id loc name description nodeType memory { urn name }
    """

    /// findNodes envelope: a scored-hit list. The app only needs the nodes, so
    /// `nodes` flattens `hits[].node` back to the `[HadronNode]` the callers use.
    private struct FindNodesResult: Decodable {
        struct Hit: Decodable { let node: HadronNode }
        let hits: [Hit]
        var nodes: [HadronNode] { hits.map(\.node) }
    }

    /// Uniform { items, total } page envelope shared by every find-many query
    /// on the #473 read surface (memories, apps, organizations, users, …).
    private struct Page<Item: Decodable>: Decodable {
        let items: [Item]
    }

    // MARK: Transport

    private func run<T: Decodable>(
        _ query: String,
        _ type: T.Type,
        variables: [String: Any] = [:]
    ) async throws -> T {
        var request = URLRequest(url: HadronConfig.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["query": query]
        // Drop nil values — NSNull or a Swift Optional.none wrapped in Any — so
        // ID-typed optionals serialize as absent rather than null.
        let cleaned = variables.filter { _, value in
            if value is NSNull { return false }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional { return !mirror.children.isEmpty }
            return true
        }
        if !cleaned.isEmpty { body["variables"] = cleaned }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HadronError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw HadronError.unauthorized
        }
        guard (200..<300).contains(status) else {
            throw HadronError.transport("HTTP \(status)")
        }

        let decoded: GraphQLResponse<T>
        do {
            decoded = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
        } catch {
            throw HadronError.graphQL("Couldn't parse the server response.")
        }
        if let errors = decoded.errors, !errors.isEmpty {
            let message = errors.map(\.message).joined(separator: "; ")
            if message.lowercased().contains("unauth") || message.lowercased().contains("forbidden") {
                throw HadronError.unauthorized
            }
            throw HadronError.graphQL(message)
        }
        guard let payload = decoded.data else {
            throw HadronError.graphQL("The server returned no data.")
        }
        return payload
    }
}
