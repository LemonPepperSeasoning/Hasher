//
//  Home.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import SwiftUI


struct Home: View {
    
    @State var isComputing: Bool = false
    @ObservedObject var hashComputer = HashComputer()
    var body: some View {
        
        VStack {
            Text("Search hash collision")
                .font(.system(size: 22, weight: .heavy, design: .default))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(10)
            

                
            Text("Number of Hash searched:")
                .font(.system(size: 16, weight: .light, design: .default))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(10)
            

            Text(String(hashComputer.counter))
                .font(.system(size: 20))

            Button(action: startpausseButtonOnClick){
                Text(isComputing ? "Pause" : "Start")
                    .frame(width: 100, height: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            
            Text(String(isComputing))
          
        }
        .padding()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        
    }
    
    func startpausseButtonOnClick() async{
        isComputing = !isComputing
        if (isComputing){
            print("Starting async function")
            startCompute()
        }else{
            print("Pausing async function")
        }
    }
    
    func startCompute() async{
        while (isComputing){
            print("loop")
            sleep(1)
        }
    }
    

    
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
