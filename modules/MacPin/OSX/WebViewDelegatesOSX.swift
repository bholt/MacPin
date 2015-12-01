/// MacPin WebViewDelegates
///
/// Handle modal & interactive webview prompts and errors using OSX widgets

import WebKit

extension WebViewControllerOSX {

	func webView(webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: () -> Void) {
		let alert = NSAlert()
		alert.messageText = webView.title!
		alert.addButtonWithTitle("Dismiss")
		alert.informativeText = message
		alert.icon = webview.favicon.icon
		alert.alertStyle = .InformationalAlertStyle // .Warning .Critical
		displayAlert(alert) { (response:NSModalResponse) -> Void in completionHandler() }
	}

	func webView(webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: (Bool) -> Void) {
		let alert = NSAlert()
		alert.messageText = webView.title!
		alert.addButtonWithTitle("OK")
		alert.addButtonWithTitle("Cancel")
		alert.informativeText = message
		alert.icon = NSApplication.sharedApplication().applicationIconImage
		displayAlert(alert) { (response:NSModalResponse) -> Void in completionHandler(response == NSAlertFirstButtonReturn ? true : false) }
	}

	func webView(webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: (String?) -> Void) {
		let alert = NSAlert()
		alert.messageText = webView.title!
		alert.addButtonWithTitle("Submit")
		alert.informativeText = prompt
		alert.icon = NSApplication.sharedApplication().applicationIconImage
		let input = NSTextField(frame: NSMakeRect(0, 0, 200, 24))
		input.stringValue = defaultText ?? ""
		input.editable = true
 		alert.accessoryView = input
		displayAlert(alert) { (response:NSModalResponse) -> Void in completionHandler(input.stringValue) }
	}

	func _webView(webView: WKWebView, printFrame: WKFrameInfo) { 
		warn("JS: `window.print();`")
		let printer = NSPrintOperation(view: webView, printInfo: NSPrintInfo.sharedPrintInfo())
		// seems to work very early on in the first loaded page, then just becomes blank pages
		// PDF = This view requires setWantsLayer:YES when blendingMode == NSVisualEffectBlendingModeWithinWindow

		//var wkview = (webView.subviews.first as WKView)
		// https://github.com/WebKit/webkit/blob/d3e9af22a535887f7d4d82e37817ba5cfc03e957/Source/WebKit2/UIProcess/API/mac/WKView.mm#L3848
		//var view = WKPrintingView(printFrame, view: wkview)
		// https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/mac/WKPrintingView.mm
		//var printer = wkview.printOperationWithPrintInfo(NSPrintInfo.sharedPrintInfo(), forFrame: printFrame) //crash on retain

		printer.showsPrintPanel = true
		printer.runOperation()
	}

}

extension WebViewControllerOSX {

	func webView(webView: WKWebView, didReceiveAuthenticationChallenge challenge: NSURLAuthenticationChallenge,
		completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
    
    let am = challenge.protectionSpace.authenticationMethod
		if am == NSURLAuthenticationMethodServerTrust {
			completionHandler(.PerformDefaultHandling, nil)
			return
		}
		warn("(\(challenge.protectionSpace.authenticationMethod)) [\(webView.URL ?? String())]")	

		let alert = NSAlert()
		alert.messageText = webView.title!
		alert.addButtonWithTitle("Submit")
		alert.addButtonWithTitle("Cancel")
		alert.informativeText = "auth challenge"
		alert.icon = NSApplication.sharedApplication().applicationIconImage

		let prompts = NSView(frame: NSMakeRect(0, 0, 200, 64))

		let userbox = NSTextField(frame: NSMakeRect(0, 40, 200, 24))
		userbox.stringValue = "Enter user"
 		if let cred = challenge.proposedCredential {
			if let user = cred.user { userbox.stringValue = user }
		}
		userbox.editable = true

		let passbox = NSTextField(frame: NSMakeRect(0, 0, 200, 24))
		passbox.stringValue = "Enter password"
 		if let cred = challenge.proposedCredential {
			if cred.hasPassword { passbox.stringValue = cred.password! }
		}
		passbox.editable = true

		prompts.subviews = [userbox, passbox]

 		alert.accessoryView = prompts

		//alert.beginSheetModalForWindow(webView.window!, completionHandler:{(response:NSModalResponse) -> Void in
		displayAlert(alert) { (response:NSModalResponse) -> Void in
			if response == NSAlertFirstButtonReturn {
				completionHandler(.UseCredential, NSURLCredential(
					user: userbox.stringValue,
					password: passbox.stringValue,
					persistence: .Permanent
				))
			} else {
				// need to cancel request, else user can get locked into a modal prompt loop
				completionHandler(.PerformDefaultHandling, nil)
				webView.stopLoading()
			}
 		}
	}
}
