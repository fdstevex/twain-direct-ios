//
//  CloudSession.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-06.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

/**
 * A TWAIN Cloud client uses the CloudSession object to establish a connection to a
 * cloud scanner, and then uses the associated Session to scan images.
 *
 * To use:
 *  - Instantiate the CloudSession
 *  - call createSession
 *
 * This will request the scanner info and event broker info from the cloud,
 * and then prepare a Session. This process is async and the session will be
 * passed to the callback when it is ready.
 *
 * Once connected, the Session provides the same API as a local scanner.
 */

class CloudSession {
    let APIRoot: URL
    let scannerID: String
    var cloudEventBroker: CloudEventBroker?
    let cloudConnection: CloudConnection
    
    init(APIRoot: URL, scannerID: String, cloudConnection: CloudConnection) {
        self.APIRoot = APIRoot
        self.scannerID = scannerID
        self.cloudConnection = cloudConnection
    }
    
    // Create the cloud session by establishing the MQTT session, and then using that to
    // create a regular TWAIN Direct Session
    func createSession(completion: @escaping (AsyncResponse<Session>)->()) {
        cloudConnection.getEventBrokerInfo { response in
            switch (response) {
            case AsyncResponse.Failure(let error):
                completion(.Failure(error))
                return
            case AsyncResponse.Success(let eventBrokerInfo):
                let cloudEventBroker = CloudEventBroker(accessToken:self.cloudConnection.accessToken, eventBrokerInfo:eventBrokerInfo)
                self.cloudEventBroker = cloudEventBroker
                self.cloudEventBroker?.connect {
                    let url = self.cloudConnection.apiURL.appendingPathComponent("scanners/" + self.scannerID)
                    let session = Session(url: url, cloudEventBroker: cloudEventBroker, cloudConnection: self.cloudConnection)
                    completion(AsyncResponse.Success(session))
                }
                break;
            }
        }
    }
}
