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
    
    mutating func setPrivetToken(_ privetToken: String) {
        self.privetToken = privetToken
    }
    
    func scannerRequest(url: URL, method: String, requestBody: Data?, completion: @escaping (AsyncResponse<Data>) -> ()) throws {
        log.info("TBD")
    }
    
    func scannerRequestWithURLResponse(url: URL, method: String, requestBody: Data?, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?) -> ()) throws {
        log.info("TBD")
    }
}
