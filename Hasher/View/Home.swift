//
//  Home.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import SwiftUI


struct Home: View {
    
    @State var count: Int = 0
    @State var isComputing: Bool = false
    var hashComputer = HashComputer()
    @State private var workItem: DispatchWorkItem?
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
            

            Text(String(count))
                .font(.system(size: 20))
            
            Button(action: startpausseButtonOnClick){
                Text(isComputing ? "Pause" : "Start")
                    .frame(width: 100, height: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            
        }
        .padding()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        
    }
    
    func startpausseButtonOnClick(){
        isComputing = !isComputing
        if (isComputing){
            print("Starting async function")
            startCompute()
        }else{
            print("Pausing async function")
            pauseCompute()
        }
    }
    
    func startCompute() {
        let plus10 = count + 10
        self.workItem = DispatchWorkItem {
            while ( (self.workItem?.isCancelled) != true ) {
                hashComputer.computeOne()
                DispatchQueue.main.async { count += 1}
            }
        }
        
        //Start the work item
        if(workItem != nil) {
            DispatchQueue.global().async(execute: workItem!)
        }
    }
    
    func pauseCompute(){
        DispatchQueue.global().asyncAfter(deadline: .now()) {
            self.workItem?.cancel()
        }
    }
    

    
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
