//
//  CurseForgeMod.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/5/4.
//

import Foundation

public struct CurseForgeMod: Codable {
    public let id: Int32
    public let name: String
    public let summary: String
    public let logo: CurseForgeModAsset
    public let classId: Int?
    
    public var projectType: ResourceType? {
        switch classId {
        case 12: .resourcepack
        case 6: .mod
        case 4471: .modpack
        case 6552: .shader
        default: nil
        }
    }
}

public struct CurseForgeModAsset: Codable {
    public let id: Int32
    public let title: String
    public let url: URL?
    public let thumbnailURL: URL?
    
    private enum CodingKeys: String, CodingKey {
        case id, title, url, thumbnailURL = "thumbnailUrl"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int32.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.url = try? container.decode(URL.self, forKey: .url)
        self.thumbnailURL = try? container.decode(URL.self, forKey: .thumbnailURL)
    }
}

public struct CurseForgeModFile: Codable {
    public struct FileHash: Codable {
        public let value: String
        public let algo: Int
    }
    
    public let id: Int32
    public let modId: Int32
    public let available: Bool
    public let fileName: String
    public let displayName: String?
    public let fileDate: Date?
    public let hashes: [FileHash]
    public let downloadURL: URL
    
    public var checksums: [String: String] {
        return hashes.reduce(into: [:]) { result, hash in
            switch hash.algo {
            case 1: result["sha1"] = hash.value
            case 2: result["md5"] = hash.value
            default: break
            }
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, modId, fileName, displayName, fileDate, hashes
        case available = "isAvailable", downloadURL = "downloadUrl"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int32.self, forKey: .id)
        self.modId = try container.decode(Int32.self, forKey: .modId)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.displayName = try? container.decode(String.self, forKey: .displayName)
        self.fileDate = (try? container.decode(String.self, forKey: .fileDate)).flatMap(Self.parseDate)
        self.hashes = try container.decode([CurseForgeModFile.FileHash].self, forKey: .hashes)
        self.available = try container.decode(Bool.self, forKey: .available)
        self.downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL) ?? .init(string: "https://edge.forgecdn.net/files/\(id / 1000)/\(id % 1000)/\(fileName)")!
    }
    
    private static func parseDate(_ string: String) -> Date? {
        let formatter: ISO8601DateFormatter = .init()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// 指纹反查命中的资源。
public struct CurseForgeFingerprintMatch: Codable {
    public let id: Int32
    public let file: CurseForgeModFile
}

/// 指纹反查接口的返回数据。
public struct CurseForgeFingerprintMatches: Codable {
    public let exactMatches: [CurseForgeFingerprintMatch]
}
