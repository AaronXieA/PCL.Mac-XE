//
//  FileUtils.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2025/11/22.
//

import Foundation
import CryptoKit

public enum FileUtils {
    /// 通用文件哈希获取。
    /// - Parameters:
    ///   - url: 文件的 URL。
    ///   - hashFunction: 零参构造的哈希函数类型 (如 `SHA256.self`)。
    /// - Returns: 哈希结果的 hex 字符串。
    public static func hash<H: HashFunction>(of url: URL, using hashFunction: H.Type) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let handle: FileHandle = try .init(forReadingFrom: url)
        defer { try? handle.close() }
        
        var hasher: H = .init()
        while try autoreleasepool(invoking: {
            if let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                hasher.update(data: data)
                return true
            } else {
                return false
            }
        }) { }
        let digest: H.Digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// SHA-1
    public static func sha1(of url: URL) throws -> String {
        try hash(of: url, using: Insecure.SHA1.self)
    }
    
    /// SHA-256
    public static func sha256(of url: URL) throws -> String {
        try hash(of: url, using: SHA256.self)
    }
    
    /// SHA-512
    public static func sha512(of url: URL) throws -> String {
        try hash(of: url, using: SHA512.self)
    }
    
    /// 获取 CurseForge 指纹（MurmurHash2 32 位，种子为 1，计算前忽略空白字符）。
    public static func curseForgeFingerprint(of url: URL) throws -> UInt32 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data: Data = try Data(contentsOf: url)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count)
        for byte in data where byte != 0x09 && byte != 0x0A && byte != 0x0D && byte != 0x20 {
            bytes.append(byte)
        }
        return murmur2(bytes, seed: 1)
    }
    
    private static func murmur2(_ bytes: [UInt8], seed: UInt32) -> UInt32 {
        let m: UInt32 = 0x5bd1e995
        let r: UInt32 = 24
        var h: UInt32 = seed ^ UInt32(bytes.count)
        var i: Int = 0
        
        while bytes.count - i >= 4 {
            var k: UInt32 = UInt32(bytes[i])
                | (UInt32(bytes[i + 1]) << 8)
                | (UInt32(bytes[i + 2]) << 16)
                | (UInt32(bytes[i + 3]) << 24)
            k = k &* m
            k ^= k >> r
            k = k &* m
            h = h &* m
            h ^= k
            i += 4
        }
        
        switch bytes.count - i {
        case 3:
            h ^= UInt32(bytes[i + 2]) << 16
            fallthrough
        case 2:
            h ^= UInt32(bytes[i + 1]) << 8
            fallthrough
        case 1:
            h ^= UInt32(bytes[i])
            h = h &* m
        default:
            break
        }
        
        h ^= h >> 13
        h = h &* m
        h ^= h >> 15
        return h
    }
    
    public static func checkFile(at url: URL, with checksums: [String: String]) throws -> Bool {
        for (algorithm, value) in checksums {
            let hash: String? = switch algorithm {
            case "sha1": try sha1(of: url)
            case "sha256": try sha256(of: url)
            case "sha512": try sha512(of: url)
            default: nil
            }
            guard let hash else { continue }
            guard hash == value else { return false }
        }
        return true
    }
    
    public static func check(_ item: DownloadItem) throws -> Bool {
        guard let checksums = item.checksums else { return true }
        return try checkFile(at: item.destination, with: checksums)
    }
    
    public static func isExecutable(at url: URL) -> Bool {
        return Architecture.architecture(of: url) != .unknown
    }
}
