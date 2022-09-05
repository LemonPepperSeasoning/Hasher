//
//  Home.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import SwiftUI

struct Home: View {
    
    var body: some View {
        Text("Hello world 1".hash256())
            .font(.system(size: 10))
    }
    
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
