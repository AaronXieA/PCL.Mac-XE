//
//  Encodable+Dictionary.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/5/16.
//

import Foundation

public extension Encodable {
    func toDictionary() throws -> [String: Any]? {
        let data = try JSONEncoder.shared.encode(self)
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [String: Any]
    }
}
