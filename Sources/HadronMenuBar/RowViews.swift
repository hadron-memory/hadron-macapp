import SwiftUI

/// A single memory row with a class badge and an "open in portal" action.
struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let desc = memory.shortDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(memory.urn)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if let cls = memory.memoryClass {
                    Badge(text: cls)
                }
                OpenInPortalButton(urn: memory.urn)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A single graph-node row (task or search result).
struct NodeRow: View {
    let node: HadronNode

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let desc = node.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(node.loc)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let memoryName = node.memory?.name {
                        Text("· \(memoryName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Badge(text: node.nodeType)
                if let urn = node.nodeURN {
                    OpenInPortalButton(urn: urn)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Small components

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct OpenInPortalButton: View {
    let urn: String
    var body: some View {
        if let url = HadronConfig.portalURL(forURN: urn) {
            Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Open in portal")
            .accessibilityLabel("Open in portal")
        }
    }
}
