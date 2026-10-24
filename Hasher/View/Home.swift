//
//  Home.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import SwiftUI


struct Home: View {
    
    @StateObject private var search = HashSearch()
    
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
                
                if search.isTableFull {
                    Text("Hash table full: new hashes are still checked, but no longer stored.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .cornerRadius(10)
        
        
            Spacer()
            
            if let collision = search.collision {
                VStack{
                    Text("Collision found !")
                        .font(.system(size: 18, weight: .heavy, design: .default))
                    VStack{
                        Text("String A: \(collision.stringA)")
                            .font(.system(size: 16, weight: .heavy, design: .default))
                        Text("String B: \(collision.stringB)")
                            .font(.system(size: 16, weight: .heavy, design: .default))
                        Text("SHA-256: \(collision.hash)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                .padding(10)
                .background(.red)
                .cornerRadius(5)
                .textSelection(.enabled)
            }
            
            Button(action: search.toggle){
                Text(search.isComputing ? "Pause" : "Start")
                    .frame(width: 100, height: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
            
        }
        .padding()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
    
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
