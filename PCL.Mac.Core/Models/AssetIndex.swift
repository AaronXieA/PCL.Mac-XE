//
//  AssetIndex.swift
//  PCL.Mac
//
//  Created by 温迪 on 2025/12/4.
//

import Foundation
import SwiftyJSON

/// https://zh.minecraft.wiki/w/散列资源文件#资源索引
public struct AssetIndex {
    public let objects: [Object]
    
    public init(json: JSON) {
        self.objects = json["objects"].dictionaryValue.map { Object(path: $0.key, json: $0.value) }
    }
    
    public struct Object {
        public let path: String
        public let hash: String
        public let size: Int
        
        public init(path: String, json: JSON) {
            self.path = path
            self.hash = json["hash"].stringValue
            self.size = json["size"].intValue
        }
    }
}
