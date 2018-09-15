//
//  CloudRPC.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-07.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

struct CloudScannerRPC : ScannerRPC {
    var privetToken: String?
    
    let cloudConnection: CloudConnection
    let cloudEventBroker: CloudEventBroker
    
    init(cloudEventBroker: CloudEventBroker, cloudConnection: CloudConnection) {
        self.cloudConnection = cloudConnection
        self.cloudEventBroker = cloudEventBroker
    }
    
    mutating func setPrivetToken(_ privetToken: String) {
        self.privetToken = privetToken
    }
    
    func scannerRequestWithURLResponse(url: URL, method: String, requestBody: Data?, commandId: String, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?) -> ()) throws {
        log.info("Submitting cloud URL request \(url)")
        if let requestBody = requestBody, let bodyStr = String(data: requestBody, encoding: .utf8) {
            log.verbose("Body \(bodyStr)")
        }
        
        var request = try LocalScannerRPC.createURLRequest(url: url, method: method, privetToken: privetToken ?? "")
        
        if (requestBody != nil) {
            request.httpBody = requestBody
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        request.setValue(cloudConnection.accessToken, forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if error != nil {
                completion(.Failure(error), nil)
                return
            }
            
            guard let response = response as? HTTPURLResponse else {
                completion(.Failure(SessionError.unexpectedError(detail: "Unexpected: Response was not HTTPURLResponse")), nil)
                return
            }
            
            if response.statusCode >= 400 {
                completion(.Failure(SessionError.unexpectedError(detail: "HTTP status \(response.statusCode)")), nil)
            }
            
            // Response will arrive through MQTT
            self.cloudEventBroker.waitForResponse(commandId: commandId, completion: { (headers, data) in
                log.verbose("Received response")
                if let bodyData = String(data: data, encoding: .utf8) {
                    log.info("Body: \(bodyData)")
                }
                completion(.Success(data), nil)
            })
        }
        task.resume()
    }
    
    func scannerRequest(url: URL, method: String, requestBody: Data?, commandId: String, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?) -> ()) throws {
        try scannerRequestWithURLResponse(url: url, method: method, requestBody: requestBody, commandId: commandId) { (response, _) in
            completion(response, nil)
        }
    }
}

