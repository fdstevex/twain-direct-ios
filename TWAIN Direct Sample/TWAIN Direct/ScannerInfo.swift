//
//  ScannerInfo.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-21.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import Foundation

struct ScannerInfo : Codable {
    enum ConnectionType: String {
        case local = "local"
        case cloud = "cloud"
    }

    // Construct ScannerInfo for a cloud scanner
    static func cloudScannerInfo(url: URL, name: String, note: String?, APIURL: URL, scannerID: String, accessToken: String, refreshToken: String?) -> ScannerInfo {
        return ScannerInfo(url: url, connectionType: ConnectionType.cloud.rawValue, name: name, note: note, fqdn: url.host!, cloudAPIURL: APIURL, cloudScannerID: scannerID, cloudAccessToken: accessToken, cloudRefreshToken: refreshToken)
    }
    
    // Construct ScannerInfo for a local scanner
    static func localScannerInfo(url: URL, name: String, note: String?, fqdn: String) -> ScannerInfo {
        return ScannerInfo(url: url, connectionType: ConnectionType.local.rawValue, name: name, note: note, fqdn: fqdn, cloudAPIURL: nil, cloudScannerID: nil, cloudAccessToken: nil, cloudRefreshToken: nil)
    }
    
    let url: URL

    // Value from ConnectionType enum
    let connectionType: String
    
    let name: String
    let note: String?
    let fqdn: String

    // API to the base cloud API endpoint
    let cloudAPIURL: URL?
    let cloudScannerID: String?
    let cloudAccessToken: String?
    let cloudRefreshToken: String?
}
