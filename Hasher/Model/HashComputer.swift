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
    
    subscript(value: CountableClosedRange<Int>) -> Substring {
        self[index(at: value.lowerBound)...index(at: value.upperBound)]
    }

    subscript(value: CountableRange<Int>) -> Substring {
        self[index(at: value.lowerBound)..<index(at: value.upperBound)]
    }

    subscript(value: PartialRangeUpTo<Int>) -> Substring {
        self[..<index(at: value.upperBound)]
    }

    subscript(value: PartialRangeThrough<Int>) -> Substring {
        self[...index(at: value.upperBound)]
    }

    subscript(value: PartialRangeFrom<Int>) -> Substring {
        self[index(at: value.lowerBound)...]
    }
    
}

private extension String {
    func index(at offset: Int) -> String.Index {
        index(startIndex, offsetBy: offset)
    }
}



class HashComputer {

    let stringLength: Int = 20
    
    var counter = 0
    var hashSet: [String: String] = [:]
    
    func computeOne() -> [String]? {
        counter += 1
        
        let randomString = generateRandomString(length: stringLength)
        let hexString = randomString.hash256()
            
        if (hashSet[hexString] != nil){
            // Duplicate found
            let value: String = hashSet[hexString]!
            print("DUPLICATE")
            if (value != randomString){
                // Found hash collision
                print("--- HASH COLLISION FOUND ---")

                return [value, randomString]
            }
        }
        hashSet[hexString] = randomString
        return nil
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
