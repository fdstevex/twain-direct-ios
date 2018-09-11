//
//  ScannerRPC.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-07.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

// Protocol for making a call to a scanner.
// There are two implementations of this protocol - one for local
// scanners, which return the response in the HTTP request, and one
// for cloud scanners, which return the response asynchronously
// through MQTT.
//
// HTTPURLResponse is passed back so the MIME response from a local
// scanner can be parsed out of it. Cloud scanners deliver blocks through
// a different mechanism and MIME body isn't delivered through MQTT, so
// HTTPURLResponse is nil from the cloud implementation
protocol ScannerRPC {
    // Call once we have a privetToken (for the first request, we won't know the token yet)
    mutating func setPrivetToken(_ privetToken: String)
    
    // If requestBody is specified, it is assumed it's type is application/json
    func scannerRequest(url: URL, method: String, requestBody: Data?, commandId: String, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?)->()) throws

    func scannerRequestWithURLResponse(url: URL, method: String, requestBody: Data?, commandId: String, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?)->()) throws
}
