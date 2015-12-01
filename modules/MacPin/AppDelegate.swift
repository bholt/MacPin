
#if os(OSX)
import AppKit
#elseif os(iOS)
import UIKit
#endif

import ObjectiveC
import WebKit
import WebKitPrivates
import Darwin

// common AppDelegate code sharable between OSX and iOS (not much)
class AppDelegate: NSObject {

	static func WebProcessConfiguration() -> _WKProcessPoolConfiguration {
		let config = _WKProcessPoolConfiguration()
		//config.injectedBundleURL = NSbundle.mainBundle().URLForAuxillaryExecutable("contentfilter.wkbundle")
		return config
	}
	//let webProcessPool = WKProcessPool() // all wkwebviews should share this
	let webProcessPool = WKProcessPool()._initWithConfiguration(AppDelegate.WebProcessConfiguration()) // all wkwebviews should share this
	//let browserController =

	override init() {
		// browserController.webProcessPool = WKProcessPool
		super.init()
	}
}

extension AppDelegate: _WKDownloadDelegate {
	func _downloadDidStart(download: _WKDownload!) { warn(download.request.description) }
	func _download(download: _WKDownload!, didRecieveResponse response: NSURLResponse!) { warn(response.description) }
	func _download(download: _WKDownload!, didRecieveData length: UInt64) { warn(length.description) }
	func _download(download: _WKDownload!, decideDestinationWithSuggestedFilename filename: String!, allowOverwrite: UnsafeMutablePointer<ObjCBool>) -> String! {
		warn(download.request.description)
		download.cancel()
		return ""
	}
	func _downloadDidFinish(download: _WKDownload!) { warn(download.request.description) }
	func _download(download: _WKDownload!, didFailWithError error: NSError!) { warn(error.description) }
	func _downloadDidCancel(download: _WKDownload!) { warn(download.request.description) }
}
