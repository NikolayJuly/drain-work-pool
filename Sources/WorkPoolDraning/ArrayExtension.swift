//
//  ArrayExtension.swift
//  
//
//  Created by Nikolay Dzhulay on 18/12/2022.
//

import Foundation

extension Array {
    /// Remove first element form array, if ti exists, and returns it
    mutating func popFirst() -> Element? {
        guard let first else {
            return nil
        }
        remove(at: 0)
        return first
    }
}
