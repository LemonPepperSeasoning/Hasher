//
//  Home.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import SwiftUI


struct Home: View {
    
    @StateObject private var search = HashSearch()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if let collision = search.collision {
                CollisionView(search: search, collision: collision)
                    .padding(.top, 24)
            } else {
                progress
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .onChange(of: scenePhase) { phase in
            // iOS suspends the app in the background anyway; pausing saves the search first.
            if phase != .active {
                search.pause()
            }
        }
    }
    
    private var header: some View {
        HStack(spacing: 8) {
            Image("logo")
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityLabel("Hasha")
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text(search.usesGPU ? "GPU" : "CPU")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Color.surface))
            .overlay(Capsule().stroke(Color.hairline))
            NavigationLink(destination: SettingsView(search: search)) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .padding(.trailing, -10)
        }
        .frame(height: 44)
        .padding(.top, 8)
    }
    
    private var progress: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 10) {
                Text(statusText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text(Format.compact(Double(search.count)))
                    .font(.system(size: 80, weight: .light).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("hashes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            HStack(spacing: 0) {
                stat(search.hashesPerSecond > 0 ? "\(Format.compact(search.hashesPerSecond))/s" : "—", "speed")
                Rectangle().fill(Color.hairline).frame(width: 1)
                stat("≈ \(Format.compact(HashSearch.expectedHashes(bits: search.bits)))", "expected")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 16)
            .overlay(Rectangle().fill(Color.hairline).frame(height: 1), alignment: .top)
            .overlay(Rectangle().fill(Color.hairline).frame(height: 1), alignment: .bottom)
            .padding(.bottom, 24)
            
            Button(search.isComputing ? "Pause" : "Start", action: search.toggle)
                .buttonStyle(PrimaryButtonStyle())
        }
    }
    
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .medium).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
    
    private var statusText: String {
        let state = search.isComputing ? "Searching" : search.count == 0 ? "Ready" : "Paused"
        return "\(state) · SHA-256 · \(search.bits) bits"
    }
    
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
