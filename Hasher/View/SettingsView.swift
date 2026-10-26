//
//  SettingsView.swift
//  Hasher
//

import SwiftUI

/// Edits a draft of the search settings and applies it on leaving, which starts a new search if anything changed.
struct SettingsView: View {

    @ObservedObject var search: HashSearch
    @Environment(\.dismiss) private var dismiss
    @State private var bits: Int
    @State private var usesGPU: Bool
    @State private var seedText: String

    init(search: HashSearch) {
        self.search = search
        _bits = State(initialValue: search.bits)
        _usesGPU = State(initialValue: search.usesGPU)
        _seedText = State(initialValue: search.seedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            section("Match the first", caption: "bits of SHA-256 · ≈ \(Format.compact(HashSearch.expectedHashes(bits: bits))) hashes expected") {
                Segmented(options: HashSearch.bitOptions, selection: $bits) { Text("\($0)").font(.system(size: 13)) }
            }

            if search.isGPUAvailable {
                section("Compute on", caption: usesGPU
                        ? "Metal · \(GPUWalker.threadCount.formatted()) walkers"
                        : "\(DistinguishedPointSearch.defaultWalkers) walkers across \(ProcessInfo.processInfo.activeProcessorCount) cores") {
                    Segmented(options: [true, false], selection: $usesGPU) { Text($0 ? "GPU" : "CPU").font(.system(size: 15)) }
                }
            }

            section("Seed", caption: "The same seed and settings rerun the exact same search. Leave it empty for a random seed.") {
                HStack(spacing: 8) {
                    TextField("Random", text: $seedText)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hairline))
                    Button {
                        seedText = Seed.random().text
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundColor(.primary)
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hairline))
                    }
                    .accessibilityLabel("Random seed")
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Text("Changing settings starts a new search.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .onDisappear {
            search.configure(bits: bits, usesGPU: usesGPU,
                             seedText: seedText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func section<Content: View>(_ title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            content()
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row of equal-width options with the selected one filled, like the bit picker in the design.
private struct Segmented<Option: Hashable>: View {

    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Text

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    label(option)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundColor(selected ? .appBackground : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.white.opacity(0.95) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
    }
}
