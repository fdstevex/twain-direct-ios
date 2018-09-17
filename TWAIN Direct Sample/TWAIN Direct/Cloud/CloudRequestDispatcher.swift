//
//  CloudRequestDispatcher.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-16.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

/**
 TWAIN Cloud uses OAuth2 for authentication.
 
 An OAuth2 accessToken can expire any time, and can be refreshed
 using the refreshToken. Any request can return a 401, and this needs to
 kick off the token refresh.
 
 During the token refresh, other request being dispatched must wait, because
 we know they will fail with the invalid accessToken. Also, because the
 refreshToken can only be used once, other requests that were already 'in flight'
 that return a 401 must wait for the token refresh to complete, and then be
 retried with the new request.
 
 This class manages that process.
 */

class CloudRequestDispatcher {
    // This class has to be thread-safe; serialize access to local properties
    private let queue = OperationQueue()
    
    private var waitingRequests = [(URLRequest, (Data?, URLResponse?, Error?) -> ())]()
    private var cloudConnection: CloudConnection
    
    init(cloudConnection: CloudConnection) {
        self.cloudConnection = cloudConnection
        queue.maxConcurrentOperationCount = 1
    }
    
    // Dispatch an URLRequest, including handling 401 errors and token refresh
    func dispatch(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        queue.addOperation {
            if !self.waitingRequests.isEmpty {
                // Refresh in progress .. add to the queue
                self.waitingRequests.append((request, completion))
                return
            }
        }
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            let httpResponse = response as! HTTPURLResponse
            guard httpResponse.statusCode != 401 else {
                log.verbose("Request failed with 401, attempting token refresh")
                self.attemptTokenRefresh(request, completion:completion)
                return;
            }
            
            completion(data, response, error)
        }
        task.resume()
    }
    
    // Add this request to the list of requests waiting for a token refresh.
    // If this is the first one, then submit the refresh request.
    private func attemptTokenRefresh(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        // Create the queue and start the refresh, or just add to the queue if it exists
        queue.addOperation {
            self.waitingRequests.append((request, completion))
            if self.waitingRequests.count == 1 {
                // This is the first request added, so submit the refresh request
                self.submitTokenRefreshRequest()
            }
        }
    }

    // Fail all outstanding requests, for example if the token refresh failed.
    private func failAll(_ error: Error) {
        queue.addOperation {
            let requests = self.waitingRequests
            self.waitingRequests.removeAll()
            OperationQueue.main.addOperation {
                requests.forEach { (request, completion) in
                    completion(nil, nil, error)
                }
            }
        }
    }
    
    // Send the token refresh request to the server.
    private func submitTokenRefreshRequest() {
        guard let refreshToken = self.cloudConnection.refreshToken else {
            // Refresh token should have been set long before we get here
            log.error("No refresh token")
            failAll(SessionError.invalidState)
            return
        }

        let url = self.cloudConnection.apiURL.appendingPathComponent("authentication/refresh/\(refreshToken)")
        let refreshRequest = URLRequest(url: url)
        let task = URLSession.shared.dataTask(with: refreshRequest) { (data, response, error) in
            let httpResponse = response as! HTTPURLResponse
            guard httpResponse.statusCode == 200 else {
                log.verbose("Token refresh failed with statusCode \(httpResponse.statusCode)")
                self.failAll(SessionError.accessTokenRefreshFailed)
                return
            }
            
            struct RefreshResponse : Decodable {
                let authorizationToken: String
                let refreshToken: String
            }
            
            guard let data = data else {
                // This would be unexxpected - a 200 response to a token refresh, but no body
                log.verbose("Token refresh failed with no body")
                self.failAll(SessionError.accessTokenRefreshFailed)
                return
            }
            
            self.queue.addOperation {
                do {
                    log.verbose("Token refresh succeeded, redispatching requests")
                    let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from:data)
                    self.cloudConnection.accessToken = refreshResponse.authorizationToken
                    self.cloudConnection.refreshToken = refreshResponse.refreshToken
                    self.cloudConnection.makeSelected()
                    
                    let requests = self.waitingRequests
                    self.waitingRequests.removeAll()
                    requests.forEach({ (request, completion) in
                        // Update the token header in the request
                        var updatedRequest = request
                        updatedRequest.setValue(refreshResponse.authorizationToken, forHTTPHeaderField: "Authorization")
                        self.dispatch(updatedRequest, completion: completion)
                    })
                } catch {
                    // This would be unexxpected - a 200 response to a token refresh, but no body
                    log.error("OAuth2 token JSON deserialization failed")
                    self.failAll(error)
                }
            }
        }
        task.resume()
    }
}

