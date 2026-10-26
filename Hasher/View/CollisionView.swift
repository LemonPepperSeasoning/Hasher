//
//  CollisionView.swift
//  Hasher
//

import SwiftUI

/// Shows a found collision. Every value is a button that copies it.
struct CollisionView: View {

    @ObservedObject var search: HashSearch
    let collision: Collision
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collision found")
                            .font(.system(size: 28, weight: .semibold))
                        Text("\(Format.compact(Double(search.count))) hashes · \(Format.duration(search.elapsed)) · first \(collision.bits) of 256 bits match")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    BitGrid(matching: collision.bits)

                    VStack(spacing: 0) {
                        row("Input A", collision.inputA)
                        row("Input B", collision.inputB)
                        row("SHA-256(salt ‖ A)", collision.digestA, matching: collision.bits)
                        row("SHA-256(salt ‖ B)", collision.digestB, matching: collision.bits)
                        row("Salt", collision.salt)
                        row("Seed", search.seed, monospaced: false)
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.surface))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }

            Button("New search", action: search.newSearch)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func row(_ label: String, _ value: String, matching bits: Int = 0, monospaced: Bool = true) -> some View {
        let prefix = value.prefix(bits / 4)
        let isCopied = copied == label
        return Button {
            UIPasteboard.general.string = value
            copied = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copied == label { copied = nil }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    (Text(prefix).foregroundColor(.accentColor).fontWeight(.medium)
                     + Text(value.dropFirst(prefix.count)).foregroundColor(bits > 0 ? .secondary : .primary))
                        .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Group {
                    if isCopied {
                        Label("Copied", systemImage: "checkmark")
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(label == "Input A" ? nil : Rectangle().fill(Color.hairline).frame(height: 1), alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(label)")
        .accessibilityValue(isCopied ? "Copied" : value)
    }
}

/// All 256 bits of the digest, the matching ones lit.
private struct BitGrid: View {

    let matching: Int
    private let columns = 32, rows = 8, gap: CGFloat = 2, cell: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let width = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            for i in 0..<(columns * rows) {
                let rect = CGRect(x: CGFloat(i % columns) * (width + gap), y: CGFloat(i / columns) * (cell + gap),
                                  width: width, height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(i < matching ? .accentColor : .hairline))
            }
        }
        .frame(height: CGFloat(rows) * cell + CGFloat(rows - 1) * gap)
        .accessibilityElement()
        .accessibilityLabel("\(matching) of 256 bits match")
    }
}
