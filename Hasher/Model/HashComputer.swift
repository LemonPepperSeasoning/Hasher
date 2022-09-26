//
//  Computer.swift
//  Hasher
//
//  Created by Birth of Venus on 5/09/22.
//

import Foundation
import CryptoKit

extension String {
    
    func hash256() -> String {
        let inputData = Data(utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
}


class HashComputer {

    var counter = 0
    var hashSet: [String: String] = [:]

    func compute(stopClause: Int ){
        while ( counter < stopClause) {
            counter += 1
            
            
            let randomString = generateRandomString(length: 10)
            let hexString = randomString.hash256()
                
            if (hashSet[hexString] != nil){
                // Duplicate found
                let value = hashSet[hexString]
                if (value != randomString){
                    // Found hash collision
                    print("--- HASH COLLISION FOUND ---")
                    print(value)
                    print(randomString)
                }
            }
            hashSet[hexString] = randomString
        }
    }
    

    func computeOne(){
        counter += 1
        
        let randomString = generateRandomString(length: 10)
        let hexString = randomString.hash256()
            
        if (hashSet[hexString] != nil){
            // Duplicate found
            let value = hashSet[hexString]
            if (value != randomString){
                // Found hash collision
                print("--- HASH COLLISION FOUND ---")
                print(value)
                print(randomString)
            }
        }
        hashSet[hexString] = randomString
    }
    

    func generateRandomString(length : Int) -> String{
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomCharacters = (0..<length).map{_ in characters.randomElement()!}
        return String(randomCharacters)
    }

    func printState(){
        print(hashSet)
        print(counter)
    }
}
