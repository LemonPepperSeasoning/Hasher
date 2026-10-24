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
        
        VStack() {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame( minWidth:0, maxWidth: .infinity, minHeight: 0, maxHeight: 50, alignment: .leading)
                .padding(.bottom, 20)
            
        
            Text("Search hash collision : SHA 256")
                .font(.system(size: 20, weight: .heavy, design: .default))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            
            HStack {
                Text("Compare the first")
                    .font(.system(size: 16, weight: .regular, design: .default))
                Picker("Bits", selection: Binding(get: { search.bits }, set: { search.newSearch(bits: $0) })) {
                    ForEach(HashSearch.bitOptions, id: \.self) { bits in
                        Text("\(bits) bits").tag(bits)
                    }
                }
                .pickerStyle(.menu)
                .disabled(search.isComputing)
                Spacer()
            }
            
            if search.isGPUAvailable {
                Toggle("Use GPU", isOn: Binding(get: { search.usesGPU }, set: { search.setUsesGPU($0) }))
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .disabled(search.isComputing)
            }
            
            Text(expectedWorkText)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.secondary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20)
        
            VStack(){
                Text("Number of Hash searched:")
                    .font(.system(size: 18, weight: .heavy, design: .default))
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                
                Text(String(search.count))
                    .font(.system(size: 64, weight: .light, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .padding(10)
                
                Text(statusText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .cornerRadius(10)
        
        
            Spacer()
            
            if let collision = search.collision {
                VStack(spacing: 6){
                    Text("Collision found !")
                        .font(.system(size: 18, weight: .heavy, design: .default))
                    Text("First \(collision.bits) bits of SHA-256(salt ‖ input) match")
                        .font(.system(size: 13, weight: .regular, design: .default))
                    VStack(alignment: .leading, spacing: 4){
                        Text("Input A: \(collision.inputA)")
                        Text("Input B: \(collision.inputB)")
                        digestText("H(A)", collision.digestA, bits: collision.bits)
                        digestText("H(B)", collision.digestB, bits: collision.bits)
                        Text("Salt: \(collision.salt)")
                    }
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                .padding(10)
                .background(.red)
                .cornerRadius(5)
                .textSelection(.enabled)
            }
            
            HStack {
                Button(action: search.toggle){
                    Text(search.isComputing ? "Pause" : "Start")
                        .frame(width: 100, height: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                
                Button(action: { search.newSearch(bits: search.bits) }){
                    Text("New search")
                        .frame(height: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                .disabled(search.isComputing)
            }
            .padding(.bottom, 40)
            
        }
        .padding()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .onChange(of: scenePhase) { phase in
            // iOS suspends the app in the background anyway; pausing saves the search first.
            if phase != .active {
                search.pause()
            }
        }
    }
    
    private var expectedWorkText: String {
        let expected = HashSearch.expectedHashes(bits: search.bits)
        var text = "Expected ≈ \(Self.abbreviated(expected)) hashes"
        if search.hashesPerSecond > 0 {
            text += ", ≈ \(Self.duration(expected / search.hashesPerSecond)) at this speed"
        }
        return text
    }
    
    private var statusText: String {
        let rate = search.hashesPerSecond > 0 ? "\(Self.abbreviated(search.hashesPerSecond)) hashes/s · " : ""
        let walkers = search.usesGPU ? "GPU · \(GPUWalker.threadCount) walkers" : "CPU · \(search.walkers) walkers"
        return rate + walkers + " · \(search.storedPoints) points stored"
    }
    
    private func digestText(_ label: String, _ hex: String, bits: Int) -> Text {
        let prefix = hex.prefix(bits / 4)
        return Text("\(label): ") + Text(prefix).bold().foregroundColor(.yellow) + Text(hex.dropFirst(prefix.count))
    }
    
    static func abbreviated(_ value: Double) -> String {
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        if value >= 1e15 {
            return "10^\(Int(log10(value).rounded()))"
        }
        for (scale, suffix) in units where value >= scale {
            return String(format: "%.1f%@", value / scale, suffix)
        }
        return String(Int(value))
    }
    
    static func duration(_ seconds: Double) -> String {
        let year = 365.25 * 86_400
        switch seconds {
        case ..<60: return "\(max(Int(seconds), 1)) s"
        case ..<3_600: return "\(Int(seconds / 60)) min"
        case ..<86_400: return "\(Int(seconds / 3_600)) h"
        case ..<year: return "\(Int(seconds / 86_400)) days"
        case ..<(1e6 * year): return "\(Int(seconds / year)) years"
        default: return "10^\(Int(log10(seconds / year).rounded())) years"
        }
    }
    
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
