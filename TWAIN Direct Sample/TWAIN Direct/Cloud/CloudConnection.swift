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
    
    func getScannerList(completionHandler: @escaping (AsyncResponse<String>)->()) {
        getEventBrokerInfo() { response in
            self.getScannerListJSON() { response in
                guard case .Success(let data) = response else {
                    // Pass along the error if there is one
                    if case .Failure(let error) = response {
                        completionHandler(.Failure(error))
                    } else {
                        completionHandler(.Failure(nil))
                    }
                    return
                }

                let str = String(data: data, encoding: .utf8)
                log.info(str)
            }
        }
    }
    
    func getData(endpoint: String, completionHandler: @escaping (AsyncResponse<Data>)->()) {
        let url = apiURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.addValue(accessToken, forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                completionHandler(AsyncResponse.Failure(error))
                return
            }
            guard response.statusCode == 200 else {
                log.error("Response from \(endpoint) endpoint: \(response)")
                completionHandler(AsyncResponse.Failure(nil))
                return
            }
            
            guard let data = data else {
                log.error("No data")
                completionHandler(AsyncResponse.Failure(nil))
                return
            }
            
            completionHandler(AsyncResponse.Success(data))
        }
        task.resume()
    }
    
    func getEventBrokerInfo(_ completionHandler: @escaping (AsyncResponse<CloudEventBrokerInfo>)->()) {
        getData(endpoint: "user") { response in
            guard case .Success(let data) = response else {
                // Pass along the error if there is one
                if case .Failure(let error) = response {
                    completionHandler(.Failure(error))
                } else {
                    completionHandler(.Failure(nil))
                }
                return
            }
            
            // Decode the JSON into a temporary structure so we can extract the eventBroker property
            struct ResponseRoot: Codable {
                let eventBroker: CloudEventBrokerInfo
            }
            do {
                let responseRoot = try JSONDecoder().decode(ResponseRoot.self, from: data)
                completionHandler(AsyncResponse.Success(responseRoot.eventBroker))
            } catch {
                completionHandler(AsyncResponse.Failure(error))
            }
        }
    }
    
    func getScannerListJSON(_ completionHandler: @escaping (AsyncResponse<Data>)->()) {
        getData(endpoint: "scanners") { response in
            guard case .Success(let data) = response else {
                // Pass along the error if there is one
                if case .Failure(let error) = response {
                    completionHandler(.Failure(error))
                } else {
                    completionHandler(.Failure(nil))
                }
                return
            }
            
            completionHandler(AsyncResponse.Success(data))
        }
    }
}
