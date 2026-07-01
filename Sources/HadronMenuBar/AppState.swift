import Foundation
import SwiftUI

/// Observable app state backing the menu bar UI. Owns auth lifecycle and the
/// loaded data (memories, tasks, search results).
@MainActor
final class AppState: ObservableObject {
    enum AuthState {
        case signedOut
        case signingIn
        case signedIn
    }

    @Published var authState: AuthState = .signedOut
    @Published var me: MeUser?
    @Published var memories: [Memory] = []
    @Published var tasks: [HadronNode] = []
    @Published var searchResults: [HadronNode] = []
    @Published var searchQuery: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let oauth = OAuthService()
    private var searchTask: Task<Void, Never>?

    init() {
        if KeychainStore.get(.accessToken) != nil {
            authState = .signedIn
            Task { await loadAll() }
        }
    }

    private var client: HadronClient? {
        guard let token = KeychainStore.get(.accessToken) else { return nil }
        return HadronClient(token: token)
    }

    // MARK: - Auth

    func signIn() {
        guard authState != .signingIn else { return }
        authState = .signingIn
        errorMessage = nil
        Task {
            do {
                let token = try await oauth.authenticate()
                KeychainStore.set(token, for: .accessToken)
                authState = .signedIn
                await loadAll()
            } catch OAuthService.OAuthError.userCancelled {
                authState = .signedOut
            } catch {
                errorMessage = error.localizedDescription
                authState = .signedOut
            }
        }
    }

    func signOut() {
        KeychainStore.delete(.accessToken)
        me = nil
        memories = []
        tasks = []
        searchResults = []
        searchQuery = ""
        errorMessage = nil
        authState = .signedOut
    }

    // MARK: - Data loading

    func loadAll() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let meResult = client.me()
            async let memoriesResult = client.myMemories()
            async let tasksResult = client.taskNodes()
            self.me = try await meResult
            self.memories = try await memoriesResult.sorted { $0.name.lowercased() < $1.name.lowercased() }
            self.tasks = try await tasksResult
        } catch {
            handle(error)
        }
    }

    func refresh() {
        Task { await loadAll() }
    }

    // MARK: - Search (debounced)

    func search(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let client else { return }
            do {
                let results = try await client.findNodes(search: trimmed)
                guard !Task.isCancelled else { return }
                self.searchResults = results
            } catch {
                handle(error)
            }
        }
    }

    // MARK: - Error handling

    private func handle(_ error: Error) {
        if case HadronError.unauthorized = error {
            errorMessage = HadronError.unauthorized.localizedDescription
            signOut()
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
