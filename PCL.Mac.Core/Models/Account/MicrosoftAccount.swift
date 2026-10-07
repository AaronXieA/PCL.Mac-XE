//
//  MicrosoftAccount.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/2/2.
//

import Foundation

public class MicrosoftAccount: Account {
    public private(set) var profile: PlayerProfile
    public private(set) var accessToken: String
    private var refreshToken: String
    private var lastRefresh: Date
    public let id: UUID
    
    private enum CodingKeys: String, CodingKey {
        case profile, accessToken, refreshToken, lastRefresh, id
    }
    
    public init(profile: PlayerProfile, accessToken: String, refreshToken: String) {
        self.profile = profile
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.lastRefresh = .now
        self.id = .init()
    }
    
    public func refresh() async throws {
        let service: MicrosoftAuthService = .init()
        let response = try await service.refresh(token: refreshToken)
        self.profile = response.profile
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        lastRefresh = .now
    }
    
    public func shouldRefresh() -> Bool {
        return Date.now.timeIntervalSince(lastRefresh) >= 86400
    }
    
    /// 重新获取带有角色属性的完整档案（用于更换皮肤 / 披风后刷新）。
    public func reloadProfile() async throws {
        let service: MinecraftProfileService = .init(accessToken: accessToken)
        self.profile = try await service.fetchSessionProfile(for: profile.id)
    }
}
