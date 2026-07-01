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
        struct Payload: Decodable { let myMemories: [Memory] }
        let query = """
        query { myMemories { id urn name shortDescription class } }
        """
        return try await run(query, Payload.self).myMemories
    }

    func taskNodes(memoryId: String? = nil, limit: Int = 200) async throws -> [HadronNode] {
        struct Payload: Decodable { let nodes: [HadronNode] }
        let query = """
        query($memory: ID, $limit: Int) {
          nodes(isRunnable: true, memory: $memory, limit: $limit) {
            \(Self.nodeFields)
          }
        }
        """
        var variables: [String: Any] = ["limit": limit]
        if let memoryId { variables["memory"] = memoryId }
        return try await run(query, Payload.self, variables: variables).nodes
    }

    func findNodes(search: String, limit: Int = 50) async throws -> [HadronNode] {
        struct Payload: Decodable { let nodes: [HadronNode] }
        let query = """
        query($search: String, $limit: Int) {
          nodes(search: $search, limit: $limit) {
            \(Self.nodeFields)
          }
        }
        """
        let variables: [String: Any] = ["search": search, "limit": limit]
        return try await run(query, Payload.self, variables: variables).nodes
    }

    private static let nodeFields = """
    id loc name description nodeType memory { urn name }
    """

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
        // Drop nil values so ID-typed optionals serialize as absent, not null.
        let cleaned = variables.filter { !($0.value is NSNull) }
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
