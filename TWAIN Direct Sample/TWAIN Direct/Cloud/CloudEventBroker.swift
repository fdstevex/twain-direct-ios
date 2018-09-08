//
//  CloudEventBroker.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-06.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation
import MQTTClient

struct CloudEventBrokerListener {
    let commandID: String
    let callback: (String)->()
}

/**
 * Subscribe to the scanner's MQTT response topic and broker messages.
 * Commands register the command ID with CloudEventBroker, and responses are
 * dispatched as they arrive.
 */
class CloudEventBroker {
    let accessToken: String
    let eventBrokerInfo: CloudEventBrokerInfo
    let session: MQTTSession
    let listeners = [String:CloudEventBrokerListener]()
    
    init(accessToken: String, eventBrokerInfo: CloudEventBrokerInfo) {
        self.accessToken = accessToken
        self.eventBrokerInfo = eventBrokerInfo
        
        struct CloudEventBrokerInfo: Codable {
            let type: String;
            let url: URL;
            let topic: String;
        }

        let transport = MQTTCFSocketTransport()
        transport.host = eventBrokerInfo.url.host
        transport.port = UInt32(eventBrokerInfo.url.port ?? 8883)
        
        session = MQTTSession()
        session.transport = transport
    }
    
    func connect(completion: @escaping ()->()) {
        let connectHandler:(Error?)->() = { error in
            log.info("MQTT Connected")
            completion()
        }
        
        session.connect(connectHandler: connectHandler)
    }
}
