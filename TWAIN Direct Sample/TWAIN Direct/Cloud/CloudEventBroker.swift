//
//  CloudEventBroker.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-06.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation
import MQTTClient

/**
 * Subscribe to the scanner's MQTT response topic and broker messages.
 * Commands register the command ID with CloudEventBroker, and responses are
 * dispatched as they arrive.
 */
class CloudEventBroker {
    let accessToken: String
    let eventBrokerInfo: CloudEventBrokerInfo
    var session: MQTTSession!
    let queue = OperationQueue()
    var listeners = [String:([String:String], Data)->()]()
    
    init(accessToken: String, eventBrokerInfo: CloudEventBrokerInfo) {
        self.accessToken = accessToken
        self.eventBrokerInfo = eventBrokerInfo
        
        queue.maxConcurrentOperationCount = 1
        
        queue.addOperation {
            self.session = MQTTSession()
            let transport = MQTTWebsocketTransport()
            transport.url = eventBrokerInfo.url
            self.session.transport = transport
        }
    }
    
    func connect(completion: @escaping ()->()) {
        let connectHandler:(Error?)->() = { error in
            log.verbose("MQTT Connected, subscribing")
            self.session.subscribe(toTopic: self.eventBrokerInfo.topic, at: .atLeastOnce) {
                error, _ in
                if let error = error {
                    log.error("Unexpected error in MQTT subscribe completion: \(error)")
                    return
                }

                // Connect has completed now that we've subscribed
                log.verbose("MQTT subscribed, ready")
                OperationQueue.main.addOperation {
                    completion()
                }
            }
        }


        queue.addOperation {
            self.session.messageHandler = self.handleMessage
            self.session.connect(connectHandler: connectHandler)
        }
    }
    
    func handleMessage(data: Data?, topic: String?) {
        guard let data = data else {
            return
        }

        // Decode the message from the data
        struct Message : Codable {
            let requestId: String?
            let statusCode: UInt32
            let statusDescription: String?
            let body: String
            let headers: [String:String]
        }
        
        do {
            let message = try JSONDecoder().decode(Message.self, from: data)
            
            // The message body is an object encoded as a JSON string - we need to decode
            // that so we can extract the commandId
            struct MessageBody : Codable {
                let commandId: String?
            }
            
            let messageData = message.body.data(using: .utf8)!
            let messageBody = try JSONDecoder().decode(MessageBody.self, from: messageData)
            
            // Locate a listener
            // infoex is the only command sent without a commandId
            if let listener = listeners[messageBody.commandId ?? "infoex"] {
                listener(message.headers, messageData)
            }
        } catch {
            // TODO: pass on a protocol error
            log.error("Exception decoding message body: \(error)")
        }
    }
    
    func waitForResponse(commandId: String, completion: @escaping ([String:String], Data)->()) {
        queue.addOperation {
            self.listeners[commandId] = completion
        }
    }
}
