//
//  MinecraftProfileService.swift
//  PCL.Mac XE.Core
//
//  Created by Wunanc on 2026/8/10.
//

import Foundation

/// Minecraft Services API 的玩家档案接口。
public final class MinecraftProfileService {
    private let accessToken: String

    private static let rootURL = URL(string: "https://api.minecraftservices.com/")!
    private static let profileURL = rootURL.appending(path: "/minecraft/profile")
    private static let activeCapeURL = rootURL.appending(path: "/minecraft/profile/capes/active")
    private static let sessionServerURL = URL(string: "https://sessionserver.mojang.com/")!

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    /// 获取正版账号当前可用的披风列表。
    public func fetchCapes() async throws -> [MinecraftCape] {
        let response = try await HTTPClient.shared.get(
            Self.profileURL,
            headers: ["Authorization": "Bearer \(accessToken)"],
            throwOnError: true
        )
        return try response.decode(ProfileResponse.self).capes
    }

    /// 将指定披风设置为当前使用的披风。
    public func activateCape(_ cape: MinecraftCape) async throws {
        _ = try await HTTPClient.shared.request(
            url: Self.activeCapeURL,
            method: "PUT",
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: ["capeId": cape.id],
            using: .json,
            throwOnError: true,
            revalidate: false,
            timeout: 30
        )
    }

    /// 上传皮肤。
    /// - Parameters:
    ///   - data: 皮肤 PNG 文件的数据。
    ///   - variant: 皮肤模型（经典 / 苗条）。
    public func uploadSkin(_ data: Data, variant: SkinVariant) async throws {
        var formData: HTTPClient.MultipartFormData = .init()
        formData.add(name: "variant", string: variant.rawValue)
        formData.add(name: "file", fileData: data, filename: "skin.png", contentType: "image/png")
        _ = try await HTTPClient.shared.upload(
            Self.profileURL.appending(path: "skins"),
            method: "POST",
            headers: ["Authorization": "Bearer \(accessToken)"],
            formData: formData,
            throwOnError: true
        )
    }

    /// 从 sessionserver 获取带有 textures 属性的完整档案。
    /// - Parameter uuid: 玩家的 UUID。
    public func fetchSessionProfile(for uuid: UUID) async throws -> PlayerProfile {
        let uuidString = UUIDUtils.string(of: uuid, withHyphens: false)
        let response = try await HTTPClient.shared.get(
            Self.sessionServerURL.appending(path: "/session/minecraft/profile/\(uuidString)"),
            throwOnError: true
        )
        return try response.decode(PlayerProfile.self)
    }

    private struct ProfileResponse: Decodable {
        let capes: [MinecraftCape]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.capes = try container.decodeIfPresent([MinecraftCape].self, forKey: .capes) ?? []
        }

        private enum CodingKeys: CodingKey {
            case capes
        }
    }
}

public struct MinecraftCape: Codable, Hashable, Identifiable {
    public let id: String
    public let state: String
    public let url: URL
    public let alias: String?

    public var isActive: Bool {
        state.uppercased() == "ACTIVE"
    }
}

/// 玩家皮肤模型。
public enum SkinVariant: String {
    /// 经典模型（宽手臂）。
    case classic
    /// 苗条模型（细手臂）。
    case slim
}
