//
//  Item.swift
//  Sotto
//
//  Created by Yasas Alwis on 2026-09-02.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
