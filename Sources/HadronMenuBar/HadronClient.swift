import Foundation

/// Errors surfaced to the UI. `unauthorized` means the token was rejected and
/// the app should drop back to the signed-out state (there is no refresh in v1).
enum HadronError: LocalizedError {
    case notAuthenticated
    case unauthorized
    /// The server rejected the request as malformed (GraphQL BAD_USER_INPUT),
    /// e.g. findNodes' boolean-query parser on unbalanced syntax. Split out
    /// from `.graphQL` so callers can retry with sanitized input.
    case badUserInput(String)
    case transport(String)
    case graphQL(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in."
        case .unauthorized: return "Your session expired. Please sign in again."
        case .badUserInput(let m): return m
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
        // myMemories and returns an { items, total } page (limit cap 200).
        // The old query returned the complete list, so offset-page until the
        // envelope's total is reached — the menu bar shows all memories.
        let query = """
        query($limit: Int, $offset: Int) {
          memories(limit: $limit, offset: $offset) {
            total
            items { id urn name shortDescription class }
          }
        }
        """
        return try await fetchAllPages { limit, offset in
            try await run(
                query, Payload.self,
                variables: ["limit": limit, "offset": offset]
            ).memories
        }
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
        // The menu bar's search box is free-form text, but findNodes' keyword
        // mode parses a boolean query grammar — send a literal-safe form so
        // no user input is rejected as malformed syntax.
        let safe = Self.literalSafeQuery(search)
        do {
            return try await keywordSearch(safe, limit: limit)
        } catch HadronError.badUserInput(let message) {
            // Defensive backstop: if the sanitizer missed a parser edge case,
            // retry once with the whole input as a quoted phrase (the
            // grammar's literal form) so user input never surfaces as an
            // error dialog.
            let quoted = Self.quotedPhrase(search)
            guard quoted != safe else { throw HadronError.badUserInput(message) }
            return try await keywordSearch(quoted, limit: limit)
        }
    }

    private func keywordSearch(_ search: String, limit: Int) async throws -> [HadronNode] {
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

    // MARK: Boolean-query sanitizing

    /// findNodes' keyword mode parses a boolean grammar (hadron-server
    /// src/lib/retrieval/tsquery.ts): parentheses group, double quotes
    /// delimit phrases, bare AND / OR / NOT words are operators (matched
    /// case-insensitively), and a leading `-` negates. Malformed input —
    /// an unmatched parenthesis or quote, a dangling operator — is rejected
    /// with BAD_USER_INPUT. The old `nodes(search:)` did literal substring
    /// matching, so when free-form input contains any of that syntax, send
    /// the whole thing as one quoted phrase instead — the parser's literal
    /// form, closest to the old semantics. Plain input passes through
    /// unchanged (implicit AND of stemmed terms).
    static func literalSafeQuery(_ raw: String) -> String {
        hasBooleanSyntax(raw) ? quotedPhrase(raw) : raw
    }

    private static func hasBooleanSyntax(_ s: String) -> Bool {
        if s.contains("(") || s.contains(")") || s.contains("\"") { return true }
        // The server tokenizer splits bare runs on whitespace (parens/quotes
        // are handled above) and uppercases words before operator matching.
        return s.split(whereSeparator: \.isWhitespace).contains { word in
            let upper = word.uppercased()
            if upper == "AND" || upper == "OR" || upper == "NOT" { return true }
            return word.count > 1 && word.first == "-"
        }
    }

    /// Wrap the input in double quotes, dropping embedded quotes (replaced
    /// with spaces — the grammar has no escape sequence for them).
    private static func quotedPhrase(_ raw: String) -> String {
        "\"" + raw.replacingOccurrences(of: "\"", with: " ") + "\""
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
        let total: Int
    }

    /// Accumulate offset pages from a #473 find-many query until the
    /// envelope's `total` is reached (or a short/empty page says the server
    /// has no more). `maxPages` is a defensive cap on round-trips so a
    /// misbehaving `total` can never loop forever: 25 × 200 = 5,000 items,
    /// far beyond what the menu bar can usefully show.
    private func fetchAllPages<Item>(
        pageSize: Int = 200,
        maxPages: Int = 25,
        fetch: (_ limit: Int, _ offset: Int) async throws -> Page<Item>
    ) async throws -> [Item] {
        var items: [Item] = []
        for _ in 0..<maxPages {
            let page = try await fetch(pageSize, items.count)
            items.append(contentsOf: page.items)
            if page.items.count < pageSize || items.count >= page.total { break }
        }
        return items
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
            if errors.contains(where: { $0.extensions?.code == "BAD_USER_INPUT" }) {
                throw HadronError.badUserInput(message)
            }
            throw HadronError.graphQL(message)
        }
        guard let payload = decoded.data else {
            throw HadronError.graphQL("The server returned no data.")
        }
        return payload
    }
}
