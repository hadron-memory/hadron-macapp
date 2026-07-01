import SwiftUI
import AppKit

/// Root of the menu bar popover. Switches between signed-out and the three
/// authenticated tabs (Memories / Tasks / Find).
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    enum Tab: String, CaseIterable, Identifiable {
        case memories = "Memories"
        case tasks = "Tasks"
        case find = "Find"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .memories: return "books.vertical"
            case .tasks: return "checklist"
            case .find: return "magnifyingglass"
            }
        }
    }

    @State private var tab: Tab = .memories

    var body: some View {
        VStack(spacing: 0) {
            switch state.authState {
            case .signedOut:
                SignedOutView()
            case .signingIn:
                signingIn
            case .signedIn:
                signedIn
            }
        }
        .frame(width: 360, height: 460)
    }

    private var signingIn: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Signing in…")
                .foregroundStyle(.secondary)
            Text("Complete the sign-in in the browser window.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var signedIn: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Label(t.rawValue, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            if let error = state.errorMessage {
                ErrorBanner(message: error)
            }

            Divider()

            Group {
                switch tab {
                case .memories: MemoriesView()
                case .tasks: TasksView()
                case .find: FindView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            FooterView()
        }
    }
}

// MARK: - Signed out

private struct SignedOutView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Hadron")
                .font(.title2.bold())
            Text("Sign in to browse your memories, tasks, and search the knowledge graph.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                state.signIn()
            } label: {
                Text("Sign in with Hadron")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)

            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Header / Footer

private struct HeaderView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.me?.displayName ?? "Signed in")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let email = state.me?.email {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct FooterView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack {
            Button("Sign Out") { state.signOut() }
                .buttonStyle(.borderless)
                .font(.caption)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
