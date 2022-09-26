//
//  Home.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import SwiftUI


struct Home: View {
    
    var hashComputer = HashComputer()
    
    
    @State var count: Int = 0
    @State var isComputing: Bool = false
    @State var collision: [String]? = nil
    @State var collisionFound: Bool = false
    @State private var workItem: DispatchWorkItem?
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
                
                Text(String(count))
                    .font(.system(size: 64, weight: .light, design: .default))
                    .padding(10)
            }
            .cornerRadius(10)
        
        
            Spacer()
            
            if collisionFound {
                VStack{
                    Text("Collision found !")
                        .font(.system(size: 18, weight: .heavy, design: .default))
                    VStack{
                        Text("String A: \(collision![0])")
                            .font(.system(size: 16, weight: .heavy, design: .default))
                        Text("String B: \(collision![1])")
                            .font(.system(size: 16, weight: .heavy, design: .default))
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                .padding(10)
                .background(.red)
                .cornerRadius(5)
            }
            
            Button(action: startpausseButtonOnClick){
                Text(isComputing ? "Pause" : "Start")
                    .frame(width: 100, height: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
            
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
        self.workItem = DispatchWorkItem {
            while ( (self.workItem?.isCancelled) != true ) {
                collision = hashComputer.computeOne()
                if collision != nil{
                    collisionFound = true
                    break
                }
                DispatchQueue.main.async { count += 1}
            }
        }
        
        //Start the work item
        if(workItem != nil) {
            DispatchQueue.global().async(execute: workItem!)
        }
    }
    
    func pauseCompute(){
        collision = nil
        collisionFound = false
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
