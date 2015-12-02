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

	var stockTrelloBlue = "rgb(0, 121, 191)";
	if (window.macpinIsTransparent) {
    var grp = /rgba?\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(,\s*\d+[\.\d+]*)*\)/g.exec(document.body.style.backgroundColor);
    css.innerHTML = "body { background-color: rgba(" + grp.slice(1,4).join(", ") + ", 0.2) !important; }";
      // css.innerHTML = "body { background-color: rgba(125, 126, 244, 0.07) !important; } ";
      // css.innerHTML = "body { opacity: 0.07 !important; }"; 
  } else if ( (document.body.style.backgroundColor == stockTrelloBlue) && overrideStockTrelloBlue && macpinIsTransparent) {
		css.innerHTML = 'body { background-color: rgba('+overrideStockTrelloBlue+') !important; } ';
		// could get rgb=getComputedStyle(document.body).backgroundColor.match(/[\d\.]+/g) and convert from original rgb() to rgba()
		// http://stackoverflow.com/q/6672374/3878712 http://davidwalsh.name/detect-invert-color
	} else if ( (document.body.style.backgroundColor == stockTrelloBlue) && overrideStockTrelloBlue) {
		css.innerHTML = 'body { background-color: rgba('+overrideStockTrelloBlue+') !important; } ';
	} else {
		css.innerHTML = '{}';
	}

	if (darkMode) css.innerHTML += "\
		body { -webkit-filter:invert(100%); }\
		input,img,.window-cover,.list-card-cover,.attachment-thumbnail-preview,.js-open-board,.board-background-select { -webkit-filter:invert(100%); }\
		span { color: black; }";
	
	if (darkMode && document.body.style.backgroundColor == "") document.body.style.backgroundColor = "black";

	document.head.appendChild(css);
};

var bgWatch = new MutationObserver(function(muts) { customizeBG(); });
bgWatch.observe(document.body, { attributes: true, attributeFilter: ["style"], childList: false, characterData: false, subtree: false });
