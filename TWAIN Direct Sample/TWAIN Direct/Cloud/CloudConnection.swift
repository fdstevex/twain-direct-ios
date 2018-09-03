//
//  CloudConnection.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-03.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

extension Notification.Name {
    static let cloudConnectionDidRefreshToken = Notification.Name("cloudConnectionDidRefreshToken")
}

/**
 * Manage a connection to a TWAIN Cloud service.
 * This includes the REST API and the MQTT events listener.
 */
class CloudConnection {
    
    // Root API URL
    let apiURL: URL
    
    // OAuth2 Access Token
    var accessToken: String

    // OAuth2 Refresh Token
    var refreshToken: String?

    // Flag that indicates a token refresh is in flight
    var refreshingToken = false

    init(apiURL: URL, accessToken: String, refreshToken: String?) {
        self.apiURL = apiURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}
