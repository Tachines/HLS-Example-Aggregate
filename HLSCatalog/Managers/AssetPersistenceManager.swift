/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetPersistenceManager` is the main class in this sample that demonstrates how to
  manage downloading HLS streams.  It includes APIs for starting and canceling downloads,
  deleting existing assets off the users device, and monitoring the download progress.
 */

import Foundation
import AVFoundation
import GCDWebServer

class AssetPersistenceManager: NSObject {
    // MARK: Properties

    /// Singleton for AssetPersistenceManager.
    static let sharedManager = AssetPersistenceManager()

    /// Internal Bool used to track if the AssetPersistenceManager finished restoring its state.
    private var didRestorePersistenceManager = false

    /// The AVAssetDownloadURLSession to use for managing AVAssetDownloadTasks.
    fileprivate var assetDownloadURLSession: AVAssetDownloadURLSession!

    /// Internal map of AVAggregateAssetDownloadTask to its corresponding Asset.
    fileprivate var activeDownloadsMap = [AVAggregateAssetDownloadTask: Asset]()

    /// Internal map of AVAggregateAssetDownloadTask to download URL.
    fileprivate var willDownloadToUrlMap = [AVAggregateAssetDownloadTask: URL]()
    
    fileprivate let baseDownloadURL: URL
    
    fileprivate var currentFairplayManager: FairplayManager?

    // MARK: Intialization
    
    let webServer: GCDWebServer

    override private init() {
        
        baseDownloadURL = URL(fileURLWithPath: NSHomeDirectory())
        
        //create local webserver
        webServer = GCDWebServer()
        webServer.addGETHandler(forBasePath: "/", directoryPath:  NSHomeDirectory(), indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
        webServer.start(withPort: 8080, bonjourName: "Stan Web Server")

        super.init()

        // Create the configuration for the AVAssetDownloadURLSession.
        let backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "AAPL-Identifier")

        // Create the AVAssetDownloadURLSession using the configuration.
        assetDownloadURLSession =
            AVAssetDownloadURLSession(configuration: backgroundConfiguration,
                                      assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }
    
    /// Restores the Application state by getting all the AVAssetDownloadTasks and restoring their Asset structs.
    func restorePersistenceManager() {
        guard !didRestorePersistenceManager else { return }
        
        didRestorePersistenceManager = true
        
        // Grab all the tasks associated with the assetDownloadURLSession
        assetDownloadURLSession.getAllTasks { tasksArray in
            // For each task, restore the state in the app by recreating Asset structs and reusing existing AVURLAsset objects.
            for task in tasksArray {
                guard let _ = task as? AVAggregateAssetDownloadTask, let _ = task.taskDescription else { break }
            }
            
            NotificationCenter.default.post(name: .AssetPersistenceManagerDidRestoreState, object: nil)
        }
    }

    /// Triggers the initial AVAssetDownloadTask for a given Asset.
    func downloadStream(for asset: Asset) {

        // Get the default media selections for the asset's media selection groups.
        let preferredMediaSelection = asset.urlAsset.preferredMediaSelection

        /*
         Creates and initializes an AVAggregateAssetDownloadTask to download multiple AVMediaSelections
         on an AVURLAsset.
         
         For the initial download, we ask the URLSession for an AVAssetDownloadTask with a minimum bitrate
         corresponding with one of the lower bitrate variants in the asset.
         */
        guard let task =
            assetDownloadURLSession.aggregateAssetDownloadTask(with: asset.urlAsset,
                                                               mediaSelections: [preferredMediaSelection],
                                                               assetTitle: asset.name,
                                                               assetArtworkData: nil,
                                                               options:
                [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265_000]) else { return }

        // To better track the AVAssetDownloadTask we set the taskDescription to something unique for our sample.
        task.taskDescription = asset.name

        self.currentFairplayManager = FairplayManager.manager(assetId: asset.programId, contentId: asset.contentId)
        asset.urlAsset.resourceLoader.setDelegate(currentFairplayManager, queue: DispatchQueue.main)
        activeDownloadsMap[task] = asset

        task.resume()

        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name
        userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
        userInfo[Asset.Keys.downloadSelectionDisplayName] = displayNamesForSelectedMediaOptions(preferredMediaSelection)

        NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo:  userInfo)
    }

    /// Returns an Asset given a specific name if that Asset is associated with an active download.
    func assetForStream(withName name: String) -> Asset? {
        var asset: Asset?

        for (_, assetValue) in activeDownloadsMap where name == assetValue.name {
            asset = assetValue
            break
        }

        return asset
    }
    
    /// Returns an Asset pointing to a file on disk if it exists.
    func localAssetForStream(withName name: String, contentId: String, programId: String) -> Asset? {
        let userDefaults = UserDefaults.standard
        guard let localFileLocation = userDefaults.value(forKey: name) as? String else { return nil }
        
        var asset: Asset?
        
        if let url = NSURL(string:"http://localhost:8080/")?.appendingPathComponent(localFileLocation) {
            asset = Asset(name: name, contentId: contentId, programId: programId, urlAsset: AVURLAsset(url: url))
        }
        
        return asset
    }

    /// Returns the current download state for a given Asset.
    func downloadState(for asset: Asset) -> Asset.DownloadState {
        let userDefaults = UserDefaults.standard
        
        
        // Check if there are any active downloads in flight.
        for (_, assetValue) in activeDownloadsMap {
            if asset.name == assetValue.name {
                return .downloading
            }
        }
        
        // Check if there is a file URL stored for this asset.
        if let localFileLocation = userDefaults.value(forKey: asset.name) as? String{
            // Check if the file exists on disk
            let localFilePath = baseDownloadURL.appendingPathComponent(localFileLocation).path
            
            if localFilePath == baseDownloadURL.path {
                return .notDownloaded
            }
            
            if FileManager.default.fileExists(atPath: localFilePath) {
                return .downloaded
            }
        }
        
        return .notDownloaded
    }

    /// Deletes an Asset on disk if possible.
    func deleteAsset(_ asset: Asset) {
        let userDefaults = UserDefaults.standard
        
        do {
            if let localFileLocation = userDefaults.value(forKey: asset.name) as? String {
                let localFileLocation = baseDownloadURL.appendingPathComponent(localFileLocation).deletingLastPathComponent()
                try FileManager.default.removeItem(at: localFileLocation)
                
                userDefaults.removeObject(forKey: asset.name)
                
                var userInfo = [String: Any]()
                userInfo[Asset.Keys.name] = asset.name
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                
                NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo:  userInfo)
                NotificationCenter.default.post(name: .AssetPersistenceManagerDidRestoreState, object: nil)
            }
        } catch {
            print("An error occured deleting the file: \(error)")
        }
    }

    /// Cancels an AVAssetDownloadTask given an Asset.
    func cancelDownload(for asset: Asset) {
        var task: AVAggregateAssetDownloadTask?

        for (taskKey, assetVal) in activeDownloadsMap where asset == assetVal {
            task = taskKey
            break
        }

        task?.cancel()
    }
}

/// Return the display names for the media selection options that are currently selected in the specified group
func displayNamesForSelectedMediaOptions(_ mediaSelection: AVMediaSelection) -> String {

    var displayNames = ""

    guard let asset = mediaSelection.asset else {
        return displayNames
    }

    // Iterate over every media characteristic in the asset in which a media selection option is available.
    for mediaCharacteristic in asset.availableMediaCharacteristicsWithMediaSelectionOptions {
        /*
         Obtain the AVMediaSelectionGroup object that contains one or more options with the
         specified media characteristic, then get the media selection option that's currently
         selected in the specified group.
         */
        guard let mediaSelectionGroup =
            asset.mediaSelectionGroup(forMediaCharacteristic: mediaCharacteristic),
            let option = mediaSelection.selectedMediaOption(in: mediaSelectionGroup) else { continue }

        // Obtain the display string for the media selection option.
        if displayNames.isEmpty {
            displayNames += " " + option.displayName
        } else {
            displayNames += ", " + option.displayName
        }
    }

    return displayNames
}

/**
 Extend `AssetPersistenceManager` to conform to the `AVAssetDownloadDelegate` protocol.
 */
extension AssetPersistenceManager: AVAssetDownloadDelegate {

    /// Tells the delegate that the task finished transferring data.
//    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
//        let userDefaults = UserDefaults.standard
//
//        /*
//         This is the ideal place to begin downloading additional media selections
//         once the asset itself has finished downloading.
//         */
//        guard let task = task as? AVAggregateAssetDownloadTask,
//            let asset = activeDownloadsMap.removeValue(forKey: task) else { return }
//
//        guard let downloadURL = willDownloadToUrlMap.removeValue(forKey: task) else { return }
//
//        // Prepare the basic userInfo dictionary that will be posted as part of our notification.
//        var userInfo = [String: Any]()
//        userInfo[Asset.Keys.name] = asset.name
//
//        if let error = error as NSError? {
//            switch (error.domain, error.code) {
//            case (NSURLErrorDomain, NSURLErrorCancelled):
//                /*
//                 This task was canceled, you should perform cleanup using the
//                 URL saved from AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didFinishDownloadingTo:).
//                 */
//                guard let localFileLocation = localAssetForStream(withName: asset.name, contentId: asset.contentId, programId: asset.programId)?.urlAsset.url else { return }
//
//                do {
//                    try FileManager.default.removeItem(at: localFileLocation)
//
//                    userDefaults.removeObject(forKey: asset.name)
//                } catch {
//                    print("An error occured trying to delete the contents on disk for \(asset.name): \(error)")
//                }
//
//                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
//
//            case (NSURLErrorDomain, NSURLErrorUnknown):
//                fatalError("Downloading HLS streams is not supported in the simulator.")
//
//            default:
//                fatalError("An unexpected error occured \(error.domain)")
//            }
//        } else {
//            do {
//                let bookmark = try downloadURL.bookmarkData()
//
//                userDefaults.set(bookmark, forKey: asset.name)
//            } catch {
//                print("Failed to create bookmarkData for download URL.")
//            }
//
//            userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloaded.rawValue
//            userInfo[Asset.Keys.downloadSelectionDisplayName] = ""
//        }
//
//        NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
//    }

    /// Method called when the an aggregate download task determines the location this asset will be downloaded to.
    func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                    willDownloadTo location: URL) {

        /*
         This delegate callback should only be used to save the location URL
         somewhere in your application. Any additional work should be done in
         `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`.
         */

        willDownloadToUrlMap[aggregateAssetDownloadTask] = location
    }

    /// Method called when a child AVAssetDownloadTask completes.
    func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                    didCompleteFor mediaSelection: AVMediaSelection) {
        /*
         This delegate callback provides an AVMediaSelection object which is now fully available for
         offline use. You can perform any additional processing with the object here.
         */

        guard let asset = activeDownloadsMap[aggregateAssetDownloadTask] else { return }

        // Prepare the basic userInfo dictionary that will be posted as part of our notification.
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name

        aggregateAssetDownloadTask.taskDescription = asset.name

        aggregateAssetDownloadTask.resume()

        userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
        userInfo[Asset.Keys.downloadSelectionDisplayName] = displayNamesForSelectedMediaOptions(mediaSelection)

        NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
    }

    /// Method to adopt to subscribe to progress updates of an AVAggregateAssetDownloadTask.
    func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange, for mediaSelection: AVMediaSelection) {

        // This delegate callback should be used to provide download progress for your AVAssetDownloadTask.
        guard let asset = activeDownloadsMap[aggregateAssetDownloadTask] else { return }

        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete +=
                CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        }

        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name
        userInfo[Asset.Keys.percentDownloaded] = percentComplete
        print("Progress: \(percentComplete)")
        NotificationCenter.default.post(name: .AssetDownloadProgress, object: nil, userInfo:  userInfo)
    }
}

extension Notification.Name {
    /// Notification for when download progress has changed.
    static let AssetDownloadProgress = Notification.Name(rawValue: "AssetDownloadProgressNotification")
    
    /// Notification for when the download state of an Asset has changed.
    static let AssetDownloadStateChanged = Notification.Name(rawValue: "AssetDownloadStateChangedNotification")
    
    /// Notification for when AssetPersistenceManager has completely restored its state.
    static let AssetPersistenceManagerDidRestoreState = Notification.Name(rawValue: "AssetPersistenceManagerDidRestoreStateNotification")
}
