//
//  RequestManager.swift
//  CriticalMaps
//
//  Created by Leonard Thomas on 12/17/18.
//

import Foundation
import os.log

public class RequestManager {
    private struct SendLocationPostBody: Codable {
        var device: String
        var location: Location
    }

    private struct SendMessagePostBody: Codable {
        var device: String
        var messages: [SendChatMessage]
    }

    private let endpoint: URL

    private var hasActiveRequest = false

    private var dataStore: DataStore
    private var locationProvider: LocationProvider
    private var networkLayer: NetworkLayer
    private var idProvider: IDProvider

    private var log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "RequestManager")

    init(dataStore: DataStore, locationProvider: LocationProvider, networkLayer: NetworkLayer, interval: TimeInterval = 12.0, idProvider: IDProvider, url: URL) {
        endpoint = url
        self.idProvider = idProvider
        self.dataStore = dataStore
        self.locationProvider = locationProvider
        self.networkLayer = networkLayer
        configureTimer(with: interval)
    }

    private func configureTimer(with interval: TimeInterval) {
        Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(timerDidUpdate(timer:)), userInfo: nil, repeats: true)
    }

    @objc private func timerDidUpdate(timer _: Timer) {
        Logger.log(.info, log: log, "Timer did update")
        updateData()
    }

    private func defaultCompletion(for response: ApiResponse?) {
        DispatchQueue.main.async {
            defer {
                self.hasActiveRequest = false
            }
            if let response = response {
                self.dataStore.update(with: response)

                Logger.log(.info, log: self.log, "Successfully finished API update")
            } else {
                Logger.log(.error, log: self.log, "API update failed")
            }
        }
    }

    private func updateData() {
        guard hasActiveRequest == false else {
            Logger.log(.info, log: log, "Don't attempt to request new data because because a request is still active")
            return
        }
        hasActiveRequest = true
        // We only use a post request if we have a location to post
        if let currentLocation = locationProvider.currentLocation {
            let body = SendLocationPostBody(device: idProvider.id, location: currentLocation)
            guard let bodyData = try? JSONEncoder().encode(body) else {
                hasActiveRequest = false
                defaultCompletion(for: nil)
                return
            }
            networkLayer.post(with: endpoint, decodable: ApiResponse.self, bodyData: bodyData, completion: defaultCompletion)
        } else {
            getData()
        }
    }

    public func getData() {
        networkLayer.get(with: endpoint, decodable: ApiResponse.self, completion: defaultCompletion)
    }

    public func send(messages: [SendChatMessage], completion: (([String: ChatMessage]?) -> Void)? = nil) {
        let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask {
            completion?(nil)
            self.networkLayer.cancelActiveRequestsIfNeeded()
        }
        let body = SendMessagePostBody(device: idProvider.id, messages: messages)

        guard let bodyData = try? JSONEncoder().encode(body) else {
            completion?(nil)
            return
        }
        networkLayer.post(with: endpoint, decodable: ApiResponse.self, bodyData: bodyData) { response in
            self.defaultCompletion(for: response)
            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                completion?(response?.chatMessages)
            }
        }
    }
}
