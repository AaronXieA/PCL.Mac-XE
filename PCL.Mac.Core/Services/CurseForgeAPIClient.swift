//
//  CurseForgeAPIClient.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/5/4.
//

import Foundation
import SwiftyJSON

public class CurseForgeAPIClient {
    private let semaphore: AsyncSemaphore = .init(value: 8)
    private let apiRoot: URL
    private let apiKey: String
    
    public init(apiRoot: URL = .init(string: "https://api.curseforge.com")!, apiKey: String) {
        self.apiRoot = apiRoot
        self.apiKey = apiKey
    }
    
    public func mod(id modId: Int) async throws -> CurseForgeMod? {
        let response = try await request("/v1/mods/\(modId)")
        if response.statusCode == 404 { return nil }
        return try response.decode(Response<CurseForgeMod>.self).data
    }
    
    public func modFile(modId: Int, fileId: Int) async throws -> CurseForgeModFile? {
        let response = try await request("/v1/mods/\(modId)/files/\(fileId)")
        if response.statusCode == 404 { return nil }
        return try response.decode(Response<CurseForgeModFile>.self).data
    }
    
    /// 使用 MurmurHash2 指纹批量反查已安装的资源。
    public func matches(fingerprints: [UInt32], gameId: Int = 432) async throws -> [CurseForgeFingerprintMatch] {
        let values: [Int] = fingerprints.map { Int(Int32(bitPattern: $0)) }
        let response = try await request("/v1/fingerprints/\(gameId)", method: "POST", body: ["fingerprints": values])
        guard response.statusCode == 200 else { return [] }
        return try response.decode(Response<CurseForgeFingerprintMatches>.self).data.exactMatches
    }
    
    /// 获取某个模组在指定游戏版本与加载器下可用的文件列表。
    public func files(ofMod modId: Int32, gameVersion: String, modLoader: ModLoader?) async throws -> [CurseForgeModFile] {
        var body: [String: Any] = ["gameVersion": gameVersion]
        if let modLoader {
            body["modLoaderType"] = modLoader.curseForgeType
        }
        let response = try await request("/v1/mods/\(modId)/files", body: body)
        guard response.statusCode == 200 else { return [] }
        return try response.decode(Response<[CurseForgeModFile]>.self).data
    }
    
    private func request(
        _ path: String,
        method: String = "GET",
        headers: [String: String?] = [:],
        body: [String: Any]? = nil
    ) async throws -> HTTPClient.Response {
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }
        var headers: [String: String?] = headers
        headers["x-api-key"] = apiKey
        
        let response = try await HTTPClient.shared.request(
            url: apiRoot.appending(path: path),
            method: method,
            headers: headers,
            body: body,
            revalidate: true,
            timeout: 30
        )
        
        return response
    }
    
    public struct Response<Body: Codable>: Codable {
        public let data: Body
    }
}
