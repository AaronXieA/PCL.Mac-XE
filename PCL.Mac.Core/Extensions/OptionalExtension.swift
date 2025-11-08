//
//  OptionalExtension.swift
//  PCL.Mac
//
//  Created by 温迪 on 2025/11/8.
//

import Foundation

public extension Optional {
    func unwrap(_ errorMessage: String? = nil, file: String = #file, line: Int = #line) throws -> Wrapped {
        guard let value = self else {
            throw SimpleError(errorMessage ?? "\(file.split(separator: "/").last!):\(line) 解包失败。")
        }
        return value
    }
    
    func forceUnwrap(_ errorMessage: String? = nil, file: String = #file, line: Int = #line) -> Wrapped {
        guard let value = self else {
            fatalError(errorMessage ?? "\(file.split(separator: "/").last!):\(line) 强制解包失败。")
        }
        return value
    }
}
