import SwiftUI

// MARK: - Memories

struct MemoriesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.memories.isEmpty {
            EmptyState(
                icon: "books.vertical",
                title: state.isLoading ? "Loading memories…" : "No memories",
                subtitle: state.isLoading ? nil : "Memories you can access will appear here."
            )
        } else {
            List(state.memories) { memory in
                MemoryRow(memory: memory)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Tasks

struct TasksView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.tasks.isEmpty {
            EmptyState(
                icon: "checklist",
                title: state.isLoading ? "Loading tasks…" : "No task nodes",
                subtitle: state.isLoading ? nil : "Runnable task nodes will appear here."
            )
        } else {
            List(state.tasks) { node in
                NodeRow(node: node)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Find

struct FindView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search nodes…", text: Binding(
                    get: { state.searchQuery },
                    set: { state.search($0) }
                ))
                .textFieldStyle(.plain)
                if !state.searchQuery.isEmpty {
                    Button {
                        state.search("")
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            Divider()

            if state.searchQuery.trimmingCharacters(in: .whitespaces).count < 2 {
                EmptyState(icon: "magnifyingglass", title: "Find nodes",
                           subtitle: "Type at least two characters to search names, locs, descriptions, and tags.")
            } else if state.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.searchResults.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "No matches",
                           subtitle: "Nothing matched “\(state.searchQuery)”.")
            } else {
                List(state.searchResults) { node in
                    NodeRow(node: node)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Shared empty state

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
