//
//  CloudConnection.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-03.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

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

    // MQTT connection and message dispatcher
    lazy var dispatcher = CloudRequestDispatcher(cloudConnection: self)
    
    init(apiURL: URL, accessToken: String, refreshToken: String?) {
        self.apiURL = apiURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    // Get the list of scanners available
    func getScannerList(completionHandler: @escaping (AsyncResponse<[ScannerInfo]>)->()) {
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
            
            // Extract the info we need to populate an array of ScannerInfo
            guard let array = try? JSONSerialization.jsonObject(with: data, options: []) else {
                completionHandler(.Failure(SessionError.invalidJSON))
                return;
            }
            
            var scanners = [ScannerInfo]()
            
            if let array = array as? [NSDictionary] {
                for scannerDict in array {
                    guard let name = scannerDict["name"] as? String,
                        let note = scannerDict["description"] as? String,
                        let id = scannerDict["id"] as? String else {
                            log.warning("Unusable entry in scanners array: \(scannerDict)")
                            continue
                    }
                    
                    let scannerURL = self.apiURL.appendingPathComponent("scanners/" + id)
                    let scannerInfo = ScannerInfo.cloudScannerInfo(url: scannerURL, name: name, note: note, APIURL: self.apiURL, scannerID: id, accessToken: self.accessToken, refreshToken: self.refreshToken)
                    scanners.append(scannerInfo)
                }
            }
            
            completionHandler(AsyncResponse.Success(scanners))
        }
    }

    // Helper function that makes a call to cloud API endpoint and returns the response data.
    private func getData(endpoint: String, completionHandler: @escaping (AsyncResponse<Data>)->()) {
        let url = apiURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.setValue(accessToken, forHTTPHeaderField: "Authorization")
        
        dispatcher.dispatch(request) { data, response, error in
            guard let response = response as? HTTPURLResponse else {
                completionHandler(AsyncResponse.Failure(error))
                return
            }
            guard response.statusCode == 200 else {
                log.error("Response from \(endpoint) endpoint: \(response)")
                completionHandler(AsyncResponse.Failure(SessionError.httpError(statusCode:response.statusCode)))
                return
            }
            
            guard let data = data else {
                log.error("No data")
                completionHandler(AsyncResponse.Failure(nil))
                return
            }
            
            completionHandler(AsyncResponse.Success(data))
        }
    }
    
    // Get the CloudEventBrokerInfo from the cloud service, which includes the
    // MQTT endpoint and topic to subscribe to.  Used by CloudSession when starting a session.
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
    
    // Get the list of scanners.  Helper for getScannerList;
    private func getScannerListJSON(_ completionHandler: @escaping (AsyncResponse<Data>)->()) {
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

// Settings related items
extension CloudConnection {
    enum SettingsKeys: String {
        case apiURL = "cloudScannerAPIURL"
        case accessToken = "cloudAccessToken"
        case refreshToken = "cloudRefreshToken"
    }
    
    // Save the current URL and tokens to UserDefaults
    func makeSelected() {
        let defaults = UserDefaults.standard
        defaults.set(apiURL, forKey: SettingsKeys.apiURL.rawValue)
        defaults.set(accessToken, forKey: SettingsKeys.accessToken.rawValue)
        defaults.set(refreshToken, forKey: SettingsKeys.refreshToken.rawValue)
    }
    
    // Restore the saved CloudConnection from UserDefaults
    static func restoreSelected() -> CloudConnection? {
        guard let scannerAPIURL = UserDefaults.standard.url(forKey: SettingsKeys.apiURL.rawValue) else {
            return nil
        }
        
        guard let accessToken = UserDefaults.standard.string(forKey: SettingsKeys.accessToken.rawValue) else {
            return nil
        }
        
        guard let refreshToken = UserDefaults.standard.string(forKey: SettingsKeys.refreshToken.rawValue) else {
            return nil
        }
        
        return CloudConnection(apiURL: scannerAPIURL, accessToken: accessToken, refreshToken: refreshToken)
    }
}
