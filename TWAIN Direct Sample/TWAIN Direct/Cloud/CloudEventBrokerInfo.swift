//
//  CloudEventBrokerInfo.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-04.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

/**
 * EventBroker info returned from the /user endpoint. This indicates the
 * method we need to use to get async responses and events - typically the type
 * is "mqtt", the URL is a WebSocket URL and the topic is the MQTT topic to subscribe to.
 */
struct CloudEventBrokerInfo: Codable {
    let type: String;
    let url: URL;
    let topic: String;
}
