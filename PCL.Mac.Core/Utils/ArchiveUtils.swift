//
//  ArchiveUtils.swift
//  PCL.Mac
//
//  Created by 温迪 on 2025/11/26.
//

import Foundation
import ZIPFoundation

public enum ArchiveUtils {
    public static func hasEntry(url: URL, path: String) throws -> Bool {
        return hasEntry(archive: try Archive(url: url, accessMode: .read), path: path)
    }
    
    public static func hasEntry(archive: Archive, path: String) -> Bool {
        return archive[path] != nil
    }
    
    public static func getEntry(url: URL, path: String) throws -> Data {
        return try getEntry(archive: Archive(url: url, accessMode: .read), path: path)
    }
    
    public static func getEntry(archive: Archive, path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw Archive.ArchiveError.invalidEntryPath
        }
        var entryData: Data = .init()
        _ = try archive.extract(entry, consumer: { data in
            entryData.append(data)
        })
        return entryData
    }
}
