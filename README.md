# HLS Catalog: Using AVFoundation to play and persist HTTP Live Streams

This sample demonstrates how to use the AVFoundation framework to play HTTP Live Streams hosted on remote servers as well as how to persist the HLS streams on disk for offline playback.

## Using the Sample

Build and run the sample on an actual device running iOS 11.0 or later using Xcode.  The APIs demonstrated in this sample do not work on the iOS Simulator.

This sample provides a list of HLS Streams that you can playback by tapping on the UITableViewCell corresponding to the stream.  If you wish to manage the download of an HLS stream such as initiating an `AVAggregateAssetDownloadTask`, canceling an already running `AVAggregateAssetDownloadTask` or deleteting an already downloaded HLS stream from disk, you can accomplish this by tapping on the accessory button on the `UITableViewCell` corresponding to the stream you wish to manage.

When the sample creates and initializes an `AVAggregateAssetDownloadTask` for the download of an HLS stream, only the default selections for each of the media selection groups will be used (these are indicated in the HLS playlist `EXT-X-MEDIA` tags by a DEFAULT attribute of YES).

### Adding Streams to the Sample

If you wish to add your own HLS streams to test with using this sample, you can do this by adding an entry into the Streams.plist that is part of the Xcode Project.  There are two important keys you need to provide values for:

__name__: What the display name of the HLS stream should be in the sample.

__playlist_url__: The URL of the HLS stream's master playlist.

### Application Transport Security

If any of the streams you add are not hosted securely, you will need to add an Application Transport Security (ATS) exception in the Info.plist.  More information on ATS and the relevant plist keys can be found in the following article:

Information Property List Key Reference - NSAppTransportSecurity: <https://developer.apple.com/library/ios/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW33>

## Important Notes

* Saving HLS streams for offline playback is only supported for VOD streams.  If you try to save a live HLS stream, the system will throw an exception.

* This sample does not support saving FairPlay Streaming (FPS) content.  For a version of the sample that demonstrates how to download FPS content, see the sample code available in the FairPlay Streaming Server SDK at <https://developer.apple.com/streaming/fps/>.

## Main Files

__AssetPersistenveManager.swift__: 

- `AssetPersistenceManager` is the main class in this sample that demonstrates how to manage downloading HLS streams.  It includes APIs for starting and canceling downloads, deleting existing assets off the users device, and monitoring the download progress.

__AssetPlaybackManager.swift__:

- `AssetPlaybackManager` is the class that manages the playback of Assets in this sample using Key-value observing on various AVFoundation classes.

__AssetListManager.swift__:

- The `AssetListManager` class is responsible for providing a list of assets to present in the `AssetListTableViewController`.

__StreamListManager.swift__:

- The `StreamListManager` class manages loading reading the contents of the `Streams.plist` file in the application bundle.
 
## Requirements

### Build

Xcode 9.0 or later; iOS 11.0 SDK or later

### Runtime

iOS 11.0 or later.

Copyright (C) 2017 Apple Inc. All rights reserved.
