//
//  LocalRPC.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-07.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import Foundation

class LocalScannerRPC : NSObject, ScannerRPC {
    var privetToken: String?

    func setPrivetToken(_ privetToken: String) {
        self.privetToken = privetToken
    }

    func scannerRequestWithURLResponse(url: URL, method: String, requestBody: Data?, commandId: String, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?) -> ()) throws {
        var request = try LocalScannerRPC.createURLRequest(url: url, method: method, privetToken: privetToken ?? "")
        
        if (requestBody != nil) {
            request.httpBody = requestBody
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        
        let task = urlSession.dataTask(with: request) { (data, response, error) in
            if error != nil {
                completion(.Failure(error), nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.Failure(SessionError.unexpectedError(detail: "Missing HTTPURLResponse")), nil)
                return
            }
            
            guard let data = data else {
                completion(.Failure(SessionError.invalidResponse(detail: "Missing data")), nil)
                return
            }

            if httpResponse.statusCode >= 400 {
                if let responseBodyString = String(data: data, encoding: .utf8) {
                    log.info(responseBodyString)
                }
                completion(.Failure(SessionError.rpcFailure(statusCode: httpResponse.statusCode)), nil)
            }
            
            guard let httpURLResponse = response as? HTTPURLResponse else {
                completion(.Failure(SessionError.invalidResponse(detail: "No HTTPURLResponse")), nil)
                return
            }
            
            completion(.Success(data), httpURLResponse)
        }
        task.resume()
    }

    func scannerRequest(url: URL, method: String, requestBody: Data?, commandId: String, completion: @escaping (AsyncResponse<Data>, HTTPURLResponse?) -> ()) throws {
        try scannerRequestWithURLResponse(url: url, method: method, requestBody: requestBody, commandId: commandId) { (response, urlResponse) in
            completion(response, urlResponse)
        }
    }
    
    static func createURLRequest(url: URL, method: String, privetToken: String) throws -> URLRequest {
        var request = URLRequest(url:url)
        request.setValue(privetToken, forHTTPHeaderField: "X-Privet-Token")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.httpMethod = method
        return request
    }
    
    // URL Session that allows connection to untrusted SSL
    var _urlSession: URLSession? = nil
    var urlSession: URLSession {
        if let session = self._urlSession {
            return session
        }
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self._urlSession = session
        return session
    }
}

extension LocalScannerRPC : URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let trust = challenge.protectionSpace.serverTrust!
        let credential = URLCredential(trust: trust)
        completionHandler(.useCredential, credential)
    }
}
