//
//  UpdateModel.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/3/26.
//

import Foundation

struct UpdateModel: Codable {
    public struct Link: Codable {
        public let name: String
        public let url: URL
    }

    public struct Version: Codable {
        public struct Downloads: Codable {
            public let github: URL
            public let mirror: URL
            public let size: Int
            public let sha1: String?
        }

        public let name: String
        public let bundleVersion: Int
        public let summary: String
        public let updateLogLinks: [Link]
        public let downloads: Downloads
    }

    public let latestVersion: Version
}

// MARK: - GitHub Releases 更新源

struct GitHubRelease: Codable {
    public struct Asset: Codable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let body: String?
    public let htmlURL: URL
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
