/*eslint eqeqeq:0, quotes:0, space-infix-ops:0, curly:0*/
/*globals webkit, document, window, localStorage*/

"use strict";

var macpinIsTransparent;

window.addEventListener("load", function(event) { 
	webkit.messageHandlers.MacPinPollStates.postMessage(["transparent"]);
}, false);

window.addEventListener("MacPinWebViewChanged", function(event) {
	macpinIsTransparent = event.detail.transparent;
	customizeBG();
}, false);

var customizeBG = function(el) {
	var overrideStockTrelloBlue = localStorage.overrideStockTrelloBlue;
	var darkMode = localStorage.darkMode;

	var css = document.getElementById('customizeBG');
	if (!css) {
		css = document.createElement("style");
		css.id = "customizeBG";
		css.type = 'text/css';
	}
  
	if (window.macpinIsTransparent) {
    css.innerHTML = "body { background-color: rgba(250, 250, 250, 0.05) !important; }";
  }
  
  css.innerHTML += "button.hp-button { background: transparent !important; color: #fff !important; } .comment-thread { background-color: transparent; } .comment-thread.highlight { background-color: #fff; } header, .main-header-right { background-color: #0b0b0b !important; } .code { font-family: Input !important; font-size: 14px; }";
	document.head.appendChild(css);
};

var bgWatch = new MutationObserver(function(muts) { customizeBG(); });
bgWatch.observe(document.body, { attributes: true, attributeFilter: ["style"], childList: false, characterData: false, subtree: false });
