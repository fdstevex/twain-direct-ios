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
// through MQTT
protocol ScannerRPC {
    // Call once we have a privetToken (for the first request, we won't know the token yet)
    mutating func setPrivetToken(_ privetToken: String)
    
    // If requestBody is specified, it is assumed it's type is application/json
    func scannerRequest(url: URL, method: String, requestBody: Data?, completion: @escaping (AsyncResponse<Data>)->()) throws

    func scannerRequestWithURLResponse(url: URL, method: String, requestBody: Data?, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?)->()) throws
}
