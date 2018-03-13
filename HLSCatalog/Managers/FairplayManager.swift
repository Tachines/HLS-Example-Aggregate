//
//  FairplayManager.swift
//  HLSCatalog
//
//  Created by Bo Dan on 13/3/18.
//  Copyright © 2018 Apple Inc. All rights reserved.
//

import Foundation
import AVFoundation

extension String {
    func stringByAddingPercentEncodingForRFC3986() -> String? {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics)
    }
}

protocol FairplayLicenseBackend {
    func licenseRequest(certificate: Data, loadingRequest: AVAssetResourceLoadingRequest, contentId: String) throws -> URLRequest
    func handleLicenseResponse(contentId: String, res: Data?, loadingRequest: AVAssetResourceLoadingRequest)
    func loadCachedLicense(contentId: String, currentTime: Int64) -> Data?
}

@available(iOS 10.0, *)
class OfflineFairplayLicenseBackend : FairplayLicenseBackend {
    let licenseUrl: URL
    let assetId: String
    
    init(licenseUrl: String, assetId: String) {
        self.licenseUrl = URL(string: licenseUrl)!
        self.assetId = assetId
    }
    
    func parseCKC(licenseResponse: Data?) -> Data? {
        return Data(base64Encoded: licenseResponse!, options: NSData.Base64DecodingOptions.init(rawValue: 0))
    }
    
    func clearLicense() {
        let storage = UserDefaults.standard
        storage.removeObject(forKey: "fps_license_\(assetId)")
    }
    
    func persistLicense(data: Data) {
        print("[OfflineFairplayLicenseBackend] persist license fps_license_\(assetId)")
        let storage = UserDefaults.standard
        storage.set(data, forKey: "fps_license_\(assetId)")
    }
    
    func loadCachedLicense(contentId _: String, currentTime: Int64) -> Data? {
        let storage = UserDefaults.standard
        return storage.data(forKey: "fps_license_\(assetId)")
    }
    
    func licenseRequest(certificate: Data, loadingRequest: AVAssetResourceLoadingRequest, contentId: String) throws -> URLRequest {
        let storage = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        storage.set(now, forKey: "loading_request_\(assetId)")
        print("[OfflineFairplayLicenseBackend] license requested for contentId = \(contentId)")
        let spc = try loadingRequest.streamingContentKeyRequestData(forApp: certificate, contentIdentifier: contentId.data(using: String.Encoding.utf8)!, options:[AVAssetResourceLoadingRequestStreamingContentKeyRequestRequiresPersistentKey: true])
        
        let customData = ["userId": "applefpstest", "sessionId": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkZXZpY2VDYXAiOlsib2ZmbGluZSJdLCJkZXZpY2VJZCI6IjkxQ0I2ODUxLTNFM0UtNDcyNC1CMTUxLUY1QzFBOUIwN0FGQiIsImV4cGlyZXMiOjE1NTA4OTQxMDgsImlhdCI6MTUxOTM1ODEwOCwicHJvZmlsZUlkIjoiOTI1ZGNmMjExNjE5NDVjNzkyNDU3MGEwNTM5Yzc1NjAiLCJyb2xlIjoib2ZmbGluZSIsInVpZCI6IjkyNWRjZjIxMTYxOTQ1Yzc5MjQ1NzBhMDUzOWM3NTYwIiwidXNlckNhcCI6WyJvZmZsaW5lIl0sInV1aWQiOiI5MjVkY2YyMTE2MTk0NWM3OTI0NTcwYTA1MzljNzU2MCJ9.oGaGrw0fDrAJgM_EMUazUMCbvRcUyRmwQHMTwOfz2jA", "merchant": "stan"]
        let encoded = try! JSONSerialization.data(withJSONObject: customData).base64EncodedString()
        print("[OfflineFairplayLicenseBackend] encoded = \(encoded)")
        let request = NSMutableURLRequest(url: self.licenseUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(encoded, forHTTPHeaderField: "dt-custom-data")
        request.httpBody = ("offline=true&spc=" + spc.base64EncodedString().stringByAddingPercentEncodingForRFC3986()!).data(using: .utf8)
        return request as URLRequest
    }
    
    func handleLicenseResponse(contentId: String, res: Data?, loadingRequest: AVAssetResourceLoadingRequest) {
        if loadingRequest.isCancelled {
            return
        }
        print("[OfflineFairplayLicenseBackend] license response for assetId = \(assetId)")
        guard let ckc = self.parseCKC(licenseResponse: res) else {
            print("error parsing CKC from licenseResponse \(String(describing: res))")
            return
        }
        print("[OfflineFairplayLicenseBackend] ckc \(ckc)")
        
        // The following line triggers a crash
        do {
            let persistentContentKeyContext = try loadingRequest.persistentContentKey(fromKeyVendorResponse: ckc, options: nil)
            print("[OfflineFairplayLicenseBackend] persisting license key for \(assetId) bro")
            self.persistLicense(data: persistentContentKeyContext)
            if let contentInformationRequest = loadingRequest.contentInformationRequest {
                contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType
            }
            if let dataRequest = loadingRequest.dataRequest {
                dataRequest.respond(with: persistentContentKeyContext)
            }
        } catch let error as NSError {
            print("error generating persistent key context from CKC: \(error)")
        }
        
       
        loadingRequest.finishLoading()
    }
}

@available(iOS 10.0, *)
class FairplayManager: NSObject {
    static func manager(assetId: String, contentId: String) -> FairplayManager {
        return FairplayManager(certificateUrl: "https://lic.drmtoday.com/license-server-fairplay/cert/stan/", assetId: assetId, contentId: contentId, backend: OfflineFairplayLicenseBackend(licenseUrl: "https://lic.drmtoday.com/license-server-fairplay/", assetId: assetId))
    }
    
    var certificateUrl: URL?
    var currentAssetId: String = ""
    var contentId: String = ""
    
    var backend: FairplayLicenseBackend?
    
    var savedLoadingRequest: AVAssetResourceLoadingRequest?
    
    override init() {
        super.init()
    }
    
    init(certificateUrl: String, assetId: String, contentId: String, backend: FairplayLicenseBackend){
        self.certificateUrl = URL(string: certificateUrl)!
        self.currentAssetId = assetId
        self.contentId = contentId
        self.backend = backend
        
        super.init()
    }
    
    let cacheVersion = "1"
    
    func persistCertificate(_ data: Data) {
        let storage = UserDefaults.standard
        storage.set(data, forKey: "fps_certificate_\(self.certificateUrl?.absoluteString)_\(self.cacheVersion)")
    }
    
    func loadCachedCertificate() -> Data? {
        let storage = UserDefaults.standard
        return storage.data(forKey: "fps_certificate_\(self.certificateUrl?.absoluteString)_\(self.cacheVersion)")
    }
    
    func loadLicense(certificate: Data, contentId: String, loadingRequest: AVAssetResourceLoadingRequest) {
        do {
            guard let backend = self.backend else { return }
            let currentTime = Int64(Date().timeIntervalSince1970)
            if let ckc = backend.loadCachedLicense(contentId: contentId, currentTime:currentTime) {
                if let contentInformationRequest = loadingRequest.contentInformationRequest {
                    contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType
                }
                if let dataRequest = loadingRequest.dataRequest {
                    dataRequest.respond(with: ckc)
                }
                loadingRequest.finishLoading()
                return
            }
            let request = try backend.licenseRequest(certificate: certificate, loadingRequest: loadingRequest, contentId: contentId)
            let task = URLSession.shared.dataTask(with: request as URLRequest) {data, response, error in
                guard error == nil else {
                    print("Error fetching CKC from \(request.url!): \(error)")
                    loadingRequest.finishLoading(with: error)
                    return
                }
                
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                    
                    print("Unexpected status code from license response: \(httpStatus.statusCode)")
                    loadingRequest.finishLoading(with: NSError(domain: "FairplayManager", code: httpStatus.statusCode, userInfo: nil))
                    return
                }
                backend.handleLicenseResponse(contentId: contentId, res: data, loadingRequest: loadingRequest)
            }
            task.resume()
        } catch {
            print("error generating license request: \(error)")
            loadingRequest.finishLoading(with: error)
            return
        }
    }
}

@available(iOS 10.0, *)
extension FairplayManager: AVAssetResourceLoaderDelegate {
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        print("[FairplayManager] shouldWaitForLoadingOfRequestedResource: \(loadingRequest.request.url)")
        if loadingRequest.request.url?.scheme != "skd" {
            print("malformed loading request: \(loadingRequest.request.url?.absoluteString)")
            return false
        }
        
        if let certificate = self.loadCachedCertificate() {
            self.loadLicense(certificate: certificate, contentId: self.contentId, loadingRequest: loadingRequest)
            return true
        }
        guard let certificateUrl = self.certificateUrl else {
            print("Cannot fetch certificate without a URL")
            return false
        }
        let task = URLSession.shared.dataTask(with: certificateUrl) {(certificate, response, error) in
            guard error == nil else {
                print("Error while fetching certificate from \(self.certificateUrl): \(error)")
                return
            }
            self.persistCertificate(certificate!)
            self.loadLicense(certificate: certificate!, contentId: self.contentId, loadingRequest: loadingRequest)
        }
        task.resume()
        self.savedLoadingRequest = loadingRequest
        return true
    }
}

