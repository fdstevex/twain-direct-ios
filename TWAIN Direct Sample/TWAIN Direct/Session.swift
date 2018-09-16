//
//  Session.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-22.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import Foundation

/**
 This class manages a session with a TWAIN Direct scanner.
 */

enum SessionError : Error {
    case createSessionFailed(code: String?)
    case releaseImageBlocksFailed(code: String?)
    case closeSessionFailed(code: String?)
    case missingSessionID
    case invalidJSON
    case blockDownloadFailed
    case startCapturingFailed(response: StartCapturingResponse)
    case stopCapturingFailed(response: StopCapturingResponse)
    case delegateNotSet
    case invalidState
    case unexpectedError(detail: String)
    case invalidResponse(detail: String)
    case rpcFailure(statusCode: Int)
    case accessTokenRefreshFailed
    case httpError(statusCode: Int)
}

// These aren't actually localizable (not returned through NSLocalizedString) because these are states the app
// should deal with, not report directly to the user.
extension SessionError: LocalizedError {
    public var errorDescription: String? {
        get {
            switch (self) {
            case .createSessionFailed(let code):
                if let code = code {
                    return "createSession failed (\(code))"
                } else {
                    return "createSession failed"
                }
            case .releaseImageBlocksFailed(let code):
                if let code = code {
                    return "releaseImageBlocks failed (\(code))"
                } else {
                    return "releaseImageBlocks failed"
                }
            case .closeSessionFailed(let code):
                if let code = code {
                    return "closeSession failed (\(code))"
                } else {
                    return "closeSession failed"
                }
            case .missingSessionID:
                return "missingSessionID (Session not created or already closed)"
            case .invalidJSON:
                return "invalid JSON"
            case .startCapturingFailed(let response):
                if let code = response.results.code {
                    return "startCapturing failed (\(code))"
                } else {
                    return "startCapturing failed"
                }
            case .stopCapturingFailed(let response):
                if let code = response.results.code {
                    return "stopCapturing failed (\(code))"
                } else {
                    return "stopCapturing failed"
                }
            case .delegateNotSet:
                return "delegate not set"
            case .blockDownloadFailed:
                return "block download failed"
            case .invalidState:
                return "invalid state"
            case .unexpectedError(let detail):
                return "unexpected error \(detail)"
            case .invalidResponse(let detail):
                return "invalid response \(detail)"
            case .rpcFailure(let statusCode):
                return "RPC failure, http statusCode \(statusCode)"
            case .accessTokenRefreshFailed:
                return "OAuth2 access token refresh failed"
            case .httpError(let statusCode):
                return "HTTP error, statusCode \(statusCode)"
            }
        }
    }
}

protocol SessionDelegate: class {
    func session(_ session: Session, didReceive file: URL, metadata: Data)
    func session(_ session: Session, didChangeState newState:Session.State)
    func session(_ session: Session, didChangeStatus newStatus:Session.StatusDetected?, success: Bool)
    func sessionDidFinishCapturing(_ session: Session)
    func session(_ session: Session, didEncounterError error:Error)
}

enum AsyncResult {
    case Success
    case Failure(Error?)
}

enum AsyncResponse<T> {
    case Success(T)
    case Failure(Error?)
}

class Session : NSObject {
    public enum State: String, Codable {
        case noSession
        case ready
        case capturing
        case closed
        case draining
    }
    
    public enum StatusDetected: String, Codable {
        case nominal
        case coverOpen
        case foldedCorner
        case imageError
        case misfeed
        case multifed
        case paperJam
        case noMedia
        case staple
    }
    
    let url: URL
    var apiURL: URL?
    var sessionID: String?
    var sessionRevision = 0
    var sessionStatus: SessionStatus?
    var sessionState: State?
    
    var paused = false
    var stopping = false
    
    var shouldWaitForEvents = false
    var waitForEventsRetryCount = 0
    let numWaitForEventsRetriesAllowed = 3
    var captureStarted = false
    
    var blockDownloader: BlockDownloader?

    let lock = NSRecursiveLock()
    
    weak var delegate: SessionDelegate?
    
    let cloudEventBroker: CloudEventBroker?
    let cloudConnection: CloudConnection?
    
    var rpc: ScannerRPC?
    
    init(url: URL) {
        self.cloudEventBroker = nil
        self.cloudConnection = nil
        self.url = url
        self.rpc = LocalScannerRPC()
    }
    
    init(url: URL, cloudEventBroker: CloudEventBroker, cloudConnection: CloudConnection) {
        self.url = url
        self.cloudEventBroker = cloudEventBroker
        self.cloudConnection = cloudConnection
        self.rpc = CloudScannerRPC(cloudEventBroker: cloudEventBroker, cloudConnection: cloudConnection)
    }

    func updateSession(_ session: SessionResponse) {
        let oldState = sessionState
        let oldStatus: SessionStatus? = session.status
        
        sessionRevision = session.revision
        sessionStatus = session.status
        sessionState = session.state

        if (session.state != oldState) {
            delegate?.session(self, didChangeState: session.state)
            
            if (session.state == .noSession) {
                self.rpc?.close()
                self.rpc = nil
            }
        }
        
        // If the session just transitioned to closed, and we're stopping, make sure we
        // release all the scanned images we don't want to transfer.
        if (oldState != State.closed && sessionState == .closed && stopping) {
            // Release all the image blocks
            releaseImageBlocks(from: 1, to: Int(Int32.max), completion: { (_) in
                // This should transition to noSession, we shouldn't need to do anything here
                log.info("final releaseImageBlocks completed")
            })
        }

        // Close the session if we're done capturing, there are no more blocks, and we're not paused
        if (captureStarted && session.doneCapturing ?? false && session.imageBlocksDrained ?? false && !self.paused && !stopping) {
            captureStarted = false
            self.closeSession(completion: { (result) in
                switch (result) {
                case .Success:
                    self.delegate?.sessionDidFinishCapturing(self)
                case .Failure(let error):
                    // Error closing .. consider the session complete
                    log.error("Error closing session: \(String(describing:error))")
                    self.delegate?.sessionDidFinishCapturing(self)
                }
            })
        }
        
        // Ensure any image blocks in the session have been enqueued
        if let imageBlocks = session.imageBlocks {
            if imageBlocks.count > 0 {
                lock.lock()
                if (self.blockDownloader == nil) {
                    self.blockDownloader = BlockDownloader(session: self)
                }
                lock.unlock()
                
                self.blockDownloader?.enqueueBlocks(imageBlocks)
            }
        }

        if (sessionStatus != oldStatus) {
            // Notify our delegate that the session changed status
            delegate?.session(self, didChangeStatus: sessionStatus?.detected, success: sessionStatus?.success ?? false)
        }
    }
    
    // Get a Privet token, and open a session with the scanner
    func open(completion: @escaping (AsyncResult)->()) {
        log.verbose("Session: Opening session (sending infoex request)")
        let requestURL = url.appendingPathComponent("privet/infoex")

        do {
            try rpc?.scannerRequest(url: requestURL, method: "GET", requestBody: nil, commandId: "infoex", completion: { (response, _) in
                switch response {
                case AsyncResponse.Failure(let error):
                    completion(AsyncResult.Failure(error))
                case AsyncResponse.Success(let data):
                    do {
                        let infoExResponse = try JSONDecoder().decode(InfoExResponse.self, from: data)
                        log.verbose("Session: Received infoex response")
                        self.rpc?.setPrivetToken(infoExResponse.privetToken)
                        guard var apiPath = infoExResponse.api?.first else {
                            log.info("Expected api property in infoex response")
                            completion(AsyncResult.Failure(nil))
                            return
                        }
                        if apiPath.starts(with: "/") {
                            apiPath.remove(at: apiPath.startIndex)
                        }
                        self.apiURL = self.url.appendingPathComponent(apiPath)
                        self.createSession(completion: completion)
                    } catch {
                        completion(AsyncResult.Failure(error))
                    }
                }
            })
        } catch {
            completion(AsyncResult.Failure(error))
        }
    }

    
    // Create the session. If successful, starts the event listener.
    func createSession(completion: @escaping (AsyncResult)->()) {
        guard let rpc = rpc, let apiURL = apiURL else {
            completion(.Failure(SessionError.unexpectedError(detail: "Missing rpc or apiURL")))
            return
        }
        
        log.verbose("Session: Sending createSession")

        let createSessionRequest = CreateSessionRequest()
        let httpBody = try? JSONEncoder().encode(createSessionRequest)
        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: httpBody, commandId: createSessionRequest.commandId) { (response, _) in
                switch response {
                case .Failure(let error):
                    completion(.Failure(error))
                case .Success(let data):
                    do {
                        log.verbose("Session: Received createSession response")
                        let createSessionResponse = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
                        if (!createSessionResponse.results.success) {
                            let error = SessionError.createSessionFailed(code:createSessionResponse.results.code)
                            completion(AsyncResult.Failure(error))
                            return
                        }
                        
                        self.sessionID = createSessionResponse.results.session?.sessionId
                        self.sessionRevision = 0
                        if (self.sessionID == nil) {
                            // Expected the result to have a session since success was true
                            let error = SessionError.missingSessionID
                            completion(AsyncResult.Failure(error))
                            return
                        }
                        
                        self.blockDownloader = BlockDownloader(session: self)
                        
                        self.shouldWaitForEvents = true
                        self.waitForEvents();
                        completion(AsyncResult.Success)
                    } catch {
                        completion(AsyncResult.Failure(error))
                    }
                }
            }
        } catch {
            completion(.Failure(error))
        }
    }
    
    // Start a waitForEvents call. There must be an active session.
    private func waitForEvents() {
        guard let rpc = rpc, let apiURL = apiURL else {
            // We've already checked for this
            log.error("Can't waitForEvents - missing rpc or apiURL")
            return
        }

        if (!self.shouldWaitForEvents || (self.waitForEventsRetryCount >= self.numWaitForEventsRetriesAllowed)) {
            return
        }
        
        lock.lock()
        defer {
            lock.unlock()
        }
        
        guard let sessionID = sessionID else {
            log.error("Unexpected: waitForEvents, but there's no session")
            return
        }
        
        let body = WaitForEventsRequest(sessionId: sessionID, sessionRevision: sessionRevision)
        let requestBody = try? JSONEncoder().encode(body)

        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: requestBody, commandId: body.commandId) { (response, _) in
                switch response {
                case .Failure(let error):
                    // Failure - retry up to retry count
                    log.error("Error detected in waitForEvents: \(String(describing:error))")
                    self.waitForEventsRetryCount = self.waitForEventsRetryCount + 1
                    self.waitForEvents()
                    return
                case .Success(let data):
                    self.lock.lock();
                    defer {
                        self.lock.unlock();
                    }
                    
                    do {
                        if data.isEmpty {
                            // No response data .. queue up another wait
                            self.waitForEvents()
                            return
                        }

                        // Log the event response
                        let str = String(data: data, encoding: .utf8) ?? ""
                        log.info(str)
                        
                        let response = try JSONDecoder().decode(WaitForEventsResponse.self, from: data)
                        if (!response.results.success) {
                            self.shouldWaitForEvents = false
                            log.error("waitForEvents reported failure: \(response.results)")
                            self.waitForEventsRetryCount = self.waitForEventsRetryCount + 1
                            return
                        }
                        
                        response.results.events?.forEach { event in
                            if (event.session.revision < self.sessionRevision) {
                                // We've already processed this event
                                return
                            }
                            
                            log.info("Received event: \(event)")

                            self.updateSession(event.session)
                            
                            if event.session.doneCapturing ?? false &&
                                event.session.imageBlocksDrained ?? false {
                                // We're done capturing and all image blocks drained -
                                // No need to keep polling
                                self.shouldWaitForEvents = false
                            }
                        }
                        
                        // Processed succesfully - reset the retry count
                        self.waitForEventsRetryCount = 0
                        
                        // Queue up another wait
                        self.waitForEvents()
                    } catch {
                        log.error("Error deserializing events: \(error)")
                        return
                    }
                }
            }
        } catch {
            delegate?.session(self, didEncounterError: error)
        }
    }

    func releaseImageBlocks(from fromBlock: Int, to toBlock: Int, completion: @escaping (AsyncResult)->()) {
        guard let rpc = rpc, let apiURL = apiURL else {
            completion(AsyncResult.Failure(SessionError.unexpectedError(detail: "Missing rpc or apiURL")))
            return
        }

        guard let sessionID = sessionID else {
            // This shouldn't fail, but just in case
            completion(.Failure(SessionError.missingSessionID))
            return
        }

        log.info("releaseImageBlocks releasing blocks from \(fromBlock) to \(toBlock)");

        let request = ReleaseImageBlocksRequest(sessionId: sessionID, fromBlock:fromBlock, toBlock: toBlock)
        let requestBody = try? JSONEncoder().encode(request)

        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: requestBody, commandId: request.commandId) { (response, _) in
                switch response {
                case .Failure(let error):
                    completion(.Failure(error))
                case .Success(let data):
                    do {
                        let releaseImageBlocksResponse = try JSONDecoder().decode(ReleaseImageBlocksResponse.self, from: data)
                        if (!releaseImageBlocksResponse.results.success) {
                            completion(AsyncResult.Failure(SessionError.releaseImageBlocksFailed(code:releaseImageBlocksResponse.results.code)))
                            return
                        }
                        if let session = releaseImageBlocksResponse.results.session {
                            self.updateSession(session)
                        }
                        
                        completion(.Success)
                    } catch {
                        completion(.Failure(error))
                    }
                }
            }
        } catch {
            completion(.Failure(error))
        }
    }

    func closeSession(completion: @escaping (AsyncResult)->()) {
        guard let rpc = rpc, let apiURL = apiURL else {
            completion(.Failure(SessionError.unexpectedError(detail: "Missing rpc or apiURL")))
            return
        }

        if (stopping) {
            // Already sent the closeSession
            return
        }
        
        stopping = true

        guard let sessionID = sessionID else {
            completion(.Failure(SessionError.missingSessionID))
            return
        }

        let body = CloseSessionRequest(sessionId: sessionID)
        let requestBody = try? JSONEncoder().encode(body)
        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: requestBody, commandId: body.commandId, completion: { (response, _) in
                switch response {
                case .Failure(let error):
                    completion(.Failure(error))
                case .Success(let data):
                    do {
                        let closeSessionResponse = try JSONDecoder().decode(CloseSessionResponse.self, from: data)
                        if (!closeSessionResponse.results.success) {
                            completion(AsyncResult.Failure(SessionError.closeSessionFailed(code:closeSessionResponse.results.code)))
                            return
                        }
                        
                        if let session = closeSessionResponse.results.session {
                            self.updateSession(session)
                        }
                        
                        completion(AsyncResult.Success)
                    } catch {
                        completion(AsyncResult.Failure(error))
                    }
                }
            })
        } catch {
            completion(.Failure(error))
        }
    }
    
    // sendTask takes a little more fiddling than usual because while we use Swift 4's
    // JSON Codable support for requests and responses elsewhere, in this case we need to
    // insert arbitrary JSON (the task), and there's no support for that.
    //
    // Instead, we prepare the request without the task JSON, use JSONEncoder to encode
    // that into JSON, and then decode that into a dictionary with JSONSerialization.
    // Then we can update that dictionary to include the task, and re-encode to JSON.
    
    func sendTask(_ task: [String:Any], completion: @escaping (AsyncResult)->()) {
        guard let rpc = rpc, let apiURL = apiURL else {
            completion(.Failure(SessionError.unexpectedError(detail: "Missing rpc or apiURL")))
            return
        }
        
        guard let sessionID = sessionID else {
            completion(AsyncResult.Failure(SessionError.missingSessionID))
            return
        }

        // Get JSON for the basic request
        let body = SendTaskRequest(sessionId: sessionID, task: task)
        guard let jsonEncodedBody = try? JSONEncoder().encode(body) else {
            completion(AsyncResult.Failure(SessionError.invalidJSON))
            return
        }

        // Convert to dictionary
        guard var dict = try? JSONSerialization.jsonObject(with: jsonEncodedBody, options: []) as! [String:Any] else {
            completion(AsyncResult.Failure(SessionError.invalidJSON))
            return
        }

        var paramsDict = dict["params"] as! [String:Any]
        paramsDict["task"] = task
        dict["params"] = paramsDict
        guard let mergedBody = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            completion(AsyncResult.Failure(SessionError.invalidJSON))
            return
        }
        
        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: mergedBody, commandId: body.commandId, completion: { (response, _) in
                switch response {
                case .Failure(let error):
                    completion(.Failure(error))
                case .Success(let data):
                    do {
                        let sendTaskResponse = try JSONDecoder().decode(SendTaskResponse.self, from: data)
                        if (!sendTaskResponse.results.success) {
                            completion(AsyncResult.Failure(SessionError.closeSessionFailed(code:sendTaskResponse.results.code)))
                        }
                        
                        if let session = sendTaskResponse.results.session {
                            self.updateSession(session)
                        }
                        completion(AsyncResult.Success)
                    } catch {
                        completion(AsyncResult.Failure(error))
                    }
                }
            })
        } catch {
            completion(.Failure(error))
        }
    }
    
    func startCapturing(completion: @escaping (AsyncResponse<StartCapturingResponse>)->()) {
        guard let rpc = rpc, let apiURL = apiURL else {
            completion(.Failure(SessionError.unexpectedError(detail: "Missing rpc or apiURL")))
            return
        }

        guard let sessionID = sessionID else {
            completion(.Failure(SessionError.missingSessionID))
            return
        }
        
        let request = StartCapturingRequest(sessionId: sessionID)
        let requestBody = try? JSONEncoder().encode(request)
        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: requestBody, commandId: request.commandId, completion: { (response, _) in
                switch response {
                case .Failure(let error):
                    completion(.Failure(error))
                case .Success(let data):
                    do {
                        let startCapturingResponse = try JSONDecoder().decode(StartCapturingResponse.self, from: data)
                        if (!startCapturingResponse.results.success) {
                            completion(AsyncResponse.Failure(SessionError.startCapturingFailed(response:startCapturingResponse)))
                        }
                        
                        if let session = startCapturingResponse.results.session {
                            self.updateSession(session);
                        }
                        
                        self.captureStarted = true
                        completion(.Success(startCapturingResponse))
                    } catch {
                        completion(.Failure(error))
                    }
                }
            })
        } catch {
            completion(.Failure(error))
        }
    }
    
    func stopCapturing(completion: @escaping (AsyncResponse<StopCapturingResponse>)->()) {
        guard let rpc = rpc, let apiURL = apiURL else {
            completion(.Failure(SessionError.unexpectedError(detail: "Missing rpc or apiURL")))
            return
        }

        guard let sessionID = sessionID else {
            completion(.Failure(SessionError.missingSessionID))
            return
        }

        
        let request = StopCapturingRequest(sessionId: sessionID)
        let requestBody = try? JSONEncoder().encode(request)
        do {
            try rpc.scannerRequest(url: apiURL, method: "POST", requestBody: requestBody, commandId: request.commandId, completion: { (response, _) in
                switch response {
                case .Failure(let error):
                    completion(.Failure(error))
                case .Success(let data):
                    do {
                        let stopCapturingResponse = try JSONDecoder().decode(StopCapturingResponse.self, from: data)
                        if (!stopCapturingResponse.results.success) {
                            completion(AsyncResponse.Failure(SessionError.stopCapturingFailed(response:stopCapturingResponse)))
                        }
                        
                        if let session = stopCapturingResponse.results.session {
                            self.updateSession(session);
                        }
                        completion(.Success(stopCapturingResponse))
                    } catch {
                        completion(.Failure(error))
                    }
                }
            })
        } catch {
            completion(.Failure(error))
        }
    }
}
