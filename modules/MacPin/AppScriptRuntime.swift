/// MacPin AppScript Runtime
///
/// Creates a singleton-instance of JavaScriptCore for intepreting bundled javascripts to control a MacPin app

// make a Globals struct with a member for each thing to expose under `$`: browser, app, WebView, etc..

#if os(OSX)
import AppKit
import OSAKit
#elseif os(iOS)
import UIKit
#endif

import Foundation
import JavaScriptCore // https://github.com/WebKit/webkit/tree/master/Source/JavaScriptCore/API
// https://developer.apple.com/library/mac/documentation/General/Reference/APIDiffsMacOSX10_10SeedDiff/modules/JavaScriptCore.html

#if arch(x86_64) || arch(i386)
import Prompt // https://github.com/neilpa/swift-libedit
#endif

import UserNotificationPrivates
import SSKeychain // https://github.com/soffes/sskeychain

extension JSValue {
	func tryFunc (method: String, argv: [AnyObject]) -> Bool {
		if self.isObject && self.hasProperty(method) {
			warn("this.\(method) <- \(argv)")
			var ret = self.invokeMethod(method, withArguments: argv)
			if let bool = ret.toObject() as? Bool { return bool }
		}
		return false
		//FIXME: handle a passed-in closure so we can handle any ret-type instead of only bools ...
	}

	func tryFunc (method: String, _ args: AnyObject...) -> Bool { //variadic overload
		return self.tryFunc(method, argv: args)
	}
}

@objc protocol AppScriptExports : JSExport { // '$.app'
	//func warn(msg: String)
	var appPath: String { get }
	var resourcePath: String { get }
	var arguments: [AnyObject] { get }
	var environment: [NSObject:AnyObject] { get }
	var name: String { get }
	var bundleID: String { get }
	var hostname: String { get }
	var architecture: String { get }
	var arches: [AnyObject]? { get }
	var platform: String { get }
	var platformVersion: String { get }
	func registerURLScheme(scheme: String)
	func changeAppIcon(iconpath: String)
	func postNotification(title: String?, _ subtitle: String?, _ msg: String?, _ id: String?)
	func postHTML5Notification(object: [String:AnyObject])
	func openURL(urlstr: String, _ app: String?)
	func sleep(secs: Double)
	func doesAppExist(appstr: String) -> Bool
	func pathExists(path: String) -> Bool
	func loadAppScript(urlstr: String) -> JSValue?
	func callJXALibrary(library: String, _ call: String, _ args: [AnyObject])
}

class AppScriptRuntime: NSObject, AppScriptExports  {
	static let shared = AppScriptRuntime() // create & export the singleton

	var context = JSContext(virtualMachine: JSVirtualMachine())
	var jsdelegate: JSValue

	var arguments: [AnyObject] { return NSProcessInfo.processInfo().arguments }
	var environment: [NSObject:AnyObject] { return NSProcessInfo.processInfo().environment }
	var appPath: String { return NSBundle.mainBundle().bundlePath ?? String() }
	var resourcePath: String { return NSBundle.mainBundle().resourcePath ?? String() }
	var hostname: String { return NSProcessInfo.processInfo().hostName }
	var bundleID: String { return NSBundle.mainBundle().bundleIdentifier ?? String() }

#if os(OSX)
	var name: String { return NSRunningApplication.currentApplication().localizedName ?? String() }
	let platform = "OSX"
#elseif os(iOS)
	var name: String { return NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleDisplayName") as? String ?? String() }
	let platform = "iOS"
#endif

	// http://nshipster.com/swift-system-version-checking/
	var platformVersion: String { return NSProcessInfo.processInfo().operatingSystemVersionString }

	var arches: [AnyObject]? { return NSBundle.mainBundle().executableArchitectures }
#if arch(i386)
	let architecture = "i386"
#elseif arch(x86_64)
	let architecture = "x86_64"
#elseif arch(arm)
	let architecture = "arm"
#elseif arch(arm64)
	let architecture = "arm64"
#endif

    override init() {
		context.name = "AppScriptRuntime"
		context.evaluateScript("$ = {};") //default global for our exports
		jsdelegate = context.evaluateScript("{};")! //default property-less delegate obj
		context.objectForKeyedSubscript("$").setObject("", forKeyedSubscript: "launchedWithURL")
		//context.objectForKeyedSubscript("$").setObject(GlobalUserScripts, forKeyedSubscript: "globalUserScripts")
		context.objectForKeyedSubscript("$").setObject(MPWebView.self, forKeyedSubscript: "WebView") // `new $.WebView({})` WebView -> [object MacPin.WebView]
		context.objectForKeyedSubscript("$").setObject(SSKeychain.self, forKeyedSubscript: "keychain")

		// set console.log to NSBlock that will call warn()
		let logger: @objc_block String -> Void = { msg in warn(msg) }
		let dumper: @objc_block AnyObject -> Void = { obj in dump(obj) }
		context.evaluateScript("console = {};") // console global
		context.objectForKeyedSubscript("console").setObject(unsafeBitCast(logger, AnyObject.self), forKeyedSubscript: "log")
		context.objectForKeyedSubscript("console").setObject(unsafeBitCast(logger, AnyObject.self), forKeyedSubscript: "dump")

		super.init()
	}

	override var description: String { return "<\(reflect(self).summary)> [\(appPath)] `\(context.name)`" }

	func sleep(secs: Double) {
		let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(Double(NSEC_PER_SEC) * secs))
		dispatch_after(delayTime, dispatch_get_main_queue()){}
		//NSThread.sleepForTimeInterval(secs)
	}

/*
	func delay(delay:Double, closure:()->()) {
		dispatch_after(
			dispatch_time(
				DISPATCH_TIME_NOW,
				Int64(delay * Double(NSEC_PER_SEC))
			),
 		dispatch_get_main_queue(), closure)
	}
*/

	func loadSiteApp() {
		let app = (NSBundle.mainBundle().objectForInfoDictionaryKey("MacPin-AppScriptName") as? String) ?? "app"

		//context.objectForKeyedSubscript("$").setObject(self, forKeyedSubscript: "osx") //FIXME: deprecate
		context.objectForKeyedSubscript("$").setObject(self, forKeyedSubscript: "app") //better nomenclature

		if let app_js = NSBundle.mainBundle().URLForResource(app, withExtension: "js") {

			// make thrown exceptions popup an nserror displaying the file name and error type
			// FIXME: doesn't print actual text of throwing code
			// Safari Web Inspector <-> JSContext seems to get an actual source-map
			context.exceptionHandler = { context, exception in
				let error = NSError(domain: "MacPin", code: 4, userInfo: [
					NSURLErrorKey: context.name,
					NSLocalizedDescriptionKey: "\(context.name) `\(exception)`"
				])
				displayError(error) // would be nicer to pop up an inspector pane or tab to interactively debug this
				context.exception = exception //default in JSContext.mm
				return // gets returned to evaluateScript()?
			}

			if let jsval = loadAppScript(app_js.description) {
				if jsval.isObject {
					warn("\(app_js) loaded as AppScriptRuntime.shared.jsdelegate")
					jsdelegate = jsval
				}
			}
		}
	}

	func loadAppScript(urlstr: String) -> JSValue? {
		if let scriptURL = NSURL(string: urlstr), script = try? NSString(contentsOfURL: scriptURL, encoding: NSUTF8StringEncoding) {
			// FIXME: script code could be loaded from anywhere, exploitable?
			warn("\(scriptURL): read")

			// JSBase.h
			//func JSCheckScriptSyntax(ctx: JSContextRef, script: JSStringRef, sourceURL: JSStringRef, startingLineNumber: Int32, exception: UnsafeMutablePointer<JSValueRef>) -> Bool
			//func JSEvaluateScript(ctx: JSContextRef, script: JSStringRef, thisObject: JSObjectRef, sourceURL: JSStringRef, startingLineNumber: Int32, exception: UnsafeMutablePointer<JSValueRef>) -> JSValueRef
			// could make this == $ ...
			// https://github.com/facebook/react-native/blob/master/React/Executors/RCTContextExecutor.m#L304
			// https://github.com/facebook/react-native/blob/0fbe0913042e314345f6a033a3681372c741466b/React/Executors/RCTContextExecutor.m#L175

			var exception = JSValue()

			if JSCheckScriptSyntax(
				/*ctx:*/ context.JSGlobalContextRef,
				/*script:*/ JSStringCreateWithCFString(script as CFString),
				/*sourceURL:*/ JSStringCreateWithCFString(scriptURL.absoluteString as CFString),
				/*startingLineNumber:*/ Int32(1),
				/*exception:*/ UnsafeMutablePointer(exception.JSValueRef)
			) {
				warn("\(scriptURL): syntax checked ok")
				context.name = "\(context.name) <\(urlstr)>"
				// FIXME: assumes last script loaded is the source file of *all* thrown errors, which is not always true

			 	return context.evaluateScript(script as String, withSourceURL: scriptURL) // returns JSValue!
			} else {
				// hmm, using self.context for the syntax check seems to evaluate the contents anyways
				// need to make a throwaway dupe of it
				warn("bad syntax: \(scriptURL)")
				if exception.isObject { warn("got errObj") }
				if exception.isString { warn(exception.toString()) }
				/*
				var errMessageJSC = JSValueToStringCopy(context.JSGlobalContextRef, exception.JSValueRef, UnsafeMutablePointer(nil))
				var errMessageCF = JSStringCopyCFString(kCFAllocatorDefault, errMessageJSC) //as String
				JSStringRelease(errMessageJSC)
				var errMessage = errMessageCF as String
				warn(errMessage)
				*/
			} // or pop open the script source-code in a new tab and highlight the offender
		}
		return nil
	}

	func doesAppExist(appstr: String) -> Bool {
#if os(OSX)
		if LSCopyApplicationURLsForBundleIdentifier(appstr as CFString, nil) != nil { return true }
#elseif os(iOS)
		if let appurl = NSURL(string: "\(appstr)://") { // installed bundleids are usually (automatically?) usable as URL schemes in iOS
			if UIApplication.sharedApplication().canOpenURL(appurl) { return true }
		}
#endif
		return false
	}

	func pathExists(path: String) -> Bool {	return NSFileManager.defaultManager().fileExistsAtPath((path as NSString).stringByExpandingTildeInPath) }

	func openURL(urlstr: String, _ appid: String? = nil) {
		if let url = NSURL(string: urlstr) {
#if os(OSX)
			NSWorkspace.sharedWorkspace().openURLs([url], withAppBundleIdentifier: appid, options: .Default, additionalEventParamDescriptor: nil, launchIdentifiers: nil)
			//options: .Default .NewInstance .AndHideOthers
			// FIXME: need to force focus on appid too, already launched apps may not pop-up#elseif os (iOS)
#elseif os(iOS)
			// iOS doesn't allow directly launching apps, must use custom-scheme URLs and X-Callback-URL
			//  unless jailbroken http://stackoverflow.com/a/6821516/3878712
			if let urlp = NSURLComponents(URL: url, resolvingAgainstBaseURL: true) {
				if let appid = appid { urlp.scheme = appid } // assume bundle ID is a working scheme
				UIApplication.sharedApplication().openURL(urlp.URL!)
			}
#endif
		}
	}

	// func newTrayTab
	//  support opening a page as a NSStatusItem icon by the clock
	// https://github.com/phranck/CCNStatusItem

	func changeAppIcon(iconpath: String) {
#if os(OSX)
		/*
		switch (iconpath) {
			case let icon_url = NSBundle.mainBundle().URLForResource(iconpath, withExtension: "png"): fallthrough // path was to a local resource
			case let icon_url = NSURL(string: iconpath): // path was a url, local or remote
				NSApplication.sharedApplication().applicationIconImage = NSImage(contentsOfUrl: icon_url)
			default:
				warn("invalid icon: \(iconpath)")
		}
		*/

		if let icon_url = NSBundle.mainBundle().URLForResource(iconpath, withExtension: "png") ?? NSURL(string: iconpath) {
			// path was a url, local or remote
			NSApplication.sharedApplication().applicationIconImage = NSImage(contentsOfURL: icon_url)
		} else {
			warn("invalid icon: \(iconpath)")
		}
#endif
	}

	func registerURLScheme(scheme: String) {
		// there *could* be an API for this in WebKit, like Chrome & FF: https://bugs.webkit.org/show_bug.cgi?id=92749
		// https://developer.mozilla.org/en-US/docs/Web-based_protocol_handlers
#if os(OSX)
		LSSetDefaultHandlerForURLScheme(scheme, NSBundle.mainBundle().bundleIdentifier)
		warn("registered URL handler in OSX: \(scheme)")
		//NSApp.registerServicesMenuSendTypes(sendTypes:[.kUTTypeFileURL], returnTypes:nil)
		// http://stackoverflow.com/questions/20461351/how-do-i-enable-services-which-operate-on-selected-files-and-folders
#else
		// use Info.plist: CFBundleURLName = bundleid & CFBundleURLSchemes = [blah1, blah2]
		// on jailed iOS devices, there is no way to do this at runtime :-(
#endif
	}

	func postNotification(_ title: String? = nil, _ subtitle: String? = nil, _ msg: String?, _ id: String? = nil) {
#if os(OSX)
		let note = NSUserNotification()
		note.title = title ?? ""
		note.subtitle = subtitle ?? "" //empty strings wont be displayed
		note.informativeText = msg ?? ""
		//note.contentImage = ?bubble pic?
		if let id = id { note.identifier = id }
		//note.hasReplyButton = true
		//note.hasActionButton = true
		//note.responsePlaceholder = "say something stupid"

		note.soundName = NSUserNotificationDefaultSoundName // something exotic?
		NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(note)
		// these can be listened for by all: http://pagesofinterest.net/blog/2012/09/observing-all-nsnotifications-within-an-nsapp/
#elseif os(iOS)
		let note = UILocalNotification()
		note.alertTitle = title ?? ""
		note.alertAction = "Open"
		note.alertBody = "\(subtitle ?? String()) \(msg ?? String())"
		note.fireDate = NSDate()
		if let id = id { note.userInfo = [ "identifier" : id ] }
		UIApplication.sharedApplication().scheduleLocalNotification(note)
#endif
		//map passed-in blocks to notification responses?
		// http://thecodeninja.tumblr.com/post/90742435155/notifications-in-ios-8-part-2-using-swift-what
	}

/*
	func promptToSaveFile(filename: String? = nil, mimetype: String? = nil, callback: (String)? = nil) {
		let saveDialog = NSSavePanel();
		saveDialog.canCreateDirectories = true
		//saveDialog.allowedFileTypes = [mimetypeUTI]
		if let filename = filename { saveDialog.nameFieldStringValue = filename }
		if let window = self.window {
			saveDialog.beginSheetModalForWindow(window) { (result: Int) -> Void in
				if let url = saveDialog.URL, path = url.path where result == NSFileHandlingPanelOKButton {
					NSFileManager.defaultManager().createFileAtPath(path, contents: data, attributes: nil)
					if let callback = callback { callback(path); }
				}
			}
		}
	}
*/

	func postHTML5Notification(object: [String:AnyObject]) {
		// object's keys conforming to:
		//   https://developer.mozilla.org/en-US/docs/Web/API/notification/Notification

		// there is an API for this in WebKit: http://playground.html5rocks.com/#simple_notifications
		//  https://developer.apple.com/library/iad/documentation/AppleApplications/Conceptual/SafariJSProgTopics/Articles/SendingNotifications.html
		//  but all my my WKWebView's report 2 (access denied) and won't display auth prompts
		//  https://github.com/WebKit/webkit/search?q=webnotificationprovider  no api delegates in WK2 for notifications or geoloc yet
		//  http://stackoverflow.com/questions/14237086/how-to-handle-html5-web-notifications-with-a-cocoa-webview
#if os(OSX)
		let note = NSUserNotification()
		for (key, value) in object {
			switch value {
				case let title as String where key == "title": note.title = title
				case let subtitle as String where key == "subtitle": note.subtitle = subtitle // not-spec
				case let body as String where key == "body": note.informativeText = body
				case let tag as String where key == "tag": note.identifier = tag
				case let icon as String where key == "icon":
					if let url = NSURL(string: icon), img = NSImage(contentsOfURL: url) {
						note._identityImage = img // left-side iTunes-ish http://stackoverflow.com/a/22586980/3878712
						//note._imageURL = url //must be a file:// URL
					}
				case let image as String where key == "image": //not-spec
					if let url = NSURL(string: image), img = NSImage(contentsOfURL: url) {
						note.contentImage = img // right-side embed
					}
				default: warn("unhandled param: `\(key): \(value)`")
			}
		}
		note.soundName = NSUserNotificationDefaultSoundName // something exotic?
		NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(note)
#elseif os(iOS)
		let note = UILocalNotification()
		note.alertAction = "Open"
		note.fireDate = NSDate()
		for (key, value) in object {
			switch value {
				case let title as String where key == "title": note.alertTitle = title
				case let body as String where key == "body": note.alertBody = body
				case let tag as String where key == "tag": note.userInfo = [ "identifier" : tag ]
				//case let icon as String where key == "icon": loadIcon(icon)
				default: warn("unhandled param: `\(key): \(value)`")
			}
		}
		UIApplication.sharedApplication().scheduleLocalNotification(note)
#endif
	}


	func REPL() {
		termiosREPL({ [unowned self] (line: String) -> Void in
			// jsdelegate.tryFunc("termiosREPL", [line])
			print(self.context.evaluateScript(line))
		})
	}
	
	func evalJXA(script: String) {
#if os(OSX)
		var error: NSDictionary?
		let osa = OSAScript(source: script, language: OSALanguage(forName: "JavaScript"))
		if let output = osa.executeAndReturnError(&error) {
			warn(output.description)
		} else if (error != nil) {
			warn("error: \(error)")
		}
#endif
	}

	func callJXALibrary(library: String, _ call: String, _ args: [AnyObject]) {
		warn(args.description)
#if os(OSX)
		let script = "eval = null; function run() { return Library('\(library)').\(call).apply(this, arguments); }"
		var error: NSDictionary?
		let osa = OSAScript(source: script, language: OSALanguage(forName: "JavaScript"))
		if let output: NSAppleEventDescriptor = osa.executeHandlerWithName("run", arguments: args, error: &error) {
			// does this interpreter persist? http://lists.apple.com/archives/applescript-users/2015/Jan/msg00164.html
			warn(output.description)
		} else if (error != nil) {
			warn("error: \(error)")
		}
#endif
	}

}
