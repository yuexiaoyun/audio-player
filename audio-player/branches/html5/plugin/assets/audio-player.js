var AudioPlayer = function () {
	var instances = [];
	var groups = {};
	var activePlayers = {};
	var playerURL = "";
	var defaultOptions = {};
	var currentVolume = -1;
	var requiredFlashVersion = "9";
	
	function getPlayer(playerID) {
		if (document.all && !window[playerID]) {
			for (var i = 0; i < document.forms.length; i++) {
				if (document.forms[i][playerID]) {
					return document.forms[i][playerID];
					break;
				}
			}
		}
		return document.all ? window[playerID] : document[playerID];
	}
	
	function addListener(playerID, type, func) {
		getPlayer(playerID).addListener(type, func);
	}
	
	function decode64(instr) {
		instr = instr.replace(/[^A-Za-z0-9\+\/\=]/g, "");
		var keystr = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
		var outstr = '', i = 0, l = instr.length, chr1, chr2, chr3, enc1, enc2, enc3, enc4;
		while (i < l) {
			enc1 = keystr.indexOf(instr.charAt(i++));
			enc2 = keystr.indexOf(instr.charAt(i++));
			enc3 = keystr.indexOf(instr.charAt(i++));
			enc4 = keystr.indexOf(instr.charAt(i++));
			chr1 = (enc1 << 2) | (enc2 >> 4);
			chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
			chr3 = ((enc3 & 3) << 6) | enc4;
			outstr+=String.fromCharCode(chr1);
			if (enc3 != 64) outstr+=String.fromCharCode(chr2);
			if (enc4 != 64) outstr+=String.fromCharCode(chr3);
		}
		return outstr.replace(/\x00+$/, '');
	}
	
	function checkWebAudio() {
		var a = document.createElement("audio");
		return a && a.canPlayType && (a.canPlayType('audio/mpeg') != "");
	}
	
	function getCallback(o, options) {
		return function (e) {
			return embedCallback.apply(o, [e, options]);
		}
	}
	
	function embedCallback (result, options) {
		if (!result.success && checkWebAudio()) {
			var toReplace = document.getElementById(result.id);
			toReplace.parentNode.replaceChild(buildAudioTag(options), toReplace);
		}
	}
	
	function buildAudioTag(options) {
		var a = document.createElement("audio");
		a.setAttribute("src", encodeURI(options.soundFile));
		a.setAttribute("controls", "controls");
		if (options.autostart == "yes") {
			a.setAttribute("autoplay", "autoplay")
		}
		if (options.loop == "yes") {
			a.setAttribute("loop", "loop")
		}
		a.style.width = options.width + "px";
		if (options.bgcolor) {
			a.style.backgroundColor = "#" + options.bgcolor;
		}
		if (options.initialvolume) {
			a.volume = options.initialvolume / 100;
		}
		
		return  a;
	}
	
	return {
		setup: function (url, options) {
			playerURL = url;
			defaultOptions = options;
			if (swfobject.hasFlashPlayerVersion(requiredFlashVersion)) {
				swfobject.switchOffAutoHideShow();
				swfobject.createCSS("p.audioplayer_container span", "visibility:hidden;height:24px;overflow:hidden;padding:0;border:none;");
			}
		},

		getPlayer: function (playerID) {
			return getPlayer(playerID);
		},
		
		addListener: function (playerID, type, func) {
			addListener(playerID, type, func);
		},
		
		embed: function (elementID, options) {
			var instanceOptions = {};
			var key;
			
			var flashParams = {};
			var flashVars = {};
			var flashAttributes = {};
	
			// Merge default options and instance options
			for (key in defaultOptions) {
				instanceOptions[key] = defaultOptions[key];
			}
			for (key in options) {
				instanceOptions[key] = options[key];
			}
			
			if (instanceOptions.transparentpagebg == "yes") {
				flashParams.bgcolor = "#FFFFFF";
				flashParams.wmode = "transparent";
			} else {
				if (instanceOptions.pagebg) {
					flashParams.bgcolor = "#" + instanceOptions.pagebg;
				}
				flashParams.wmode = "opaque";
			}
			
			flashParams.menu = "false";
			
			for (key in instanceOptions) {
				if (key == "pagebg" || key == "width" || key == "transparentpagebg") {
					continue;
				}
				flashVars[key] = instanceOptions[key];
			}
			
			flashAttributes.name = elementID;
			flashAttributes.style = "outline: none";
			
			flashVars.playerID = elementID;
			
			swfobject.embedSWF(playerURL, elementID, instanceOptions.width.toString(), "24", requiredFlashVersion, false, flashVars, flashParams, flashAttributes, getCallback(this, instanceOptions));
			
			instances.push(elementID);
			
			if (options.group) {
				groups[elementID] = options.group;
			}
		},
		
		syncVolumes: function (playerID, volume) {	
			if (groups[playerID]) return;
			currentVolume = volume;
			for (var i = 0; i < instances.length; i++) {
				if (!groups[instances[i]] && instances[i] != playerID) {
					getPlayer(instances[i]).setVolume(currentVolume);
				}
			}
		},
		
		activate: function (playerID, info) {
			for (var activePlayerID in activePlayers) {
				if (activePlayerID == playerID) {
					continue;
				}
				if (groups[playerID] != groups[activePlayerID]) {
					this.close(activePlayerID);
					continue;
				}
				if (!(groups[playerID] || groups[activePlayerID])) {
					this.close(activePlayerID);
				}
			}
			activePlayers[playerID] = 1;
		},
		
		load: function (playerID, soundFile, titles, artists) {
			getPlayer(playerID).load(soundFile, titles, artists);
		},
		
		close: function (playerID) {
			getPlayer(playerID).close();
			if (playerID in activePlayers) {
				delete activePlayers[playerID];
			}
		},
		
		open: function (playerID, index) {
			if (index == undefined) {
				index = 1;
			}
			getPlayer(playerID).open(index == undefined ? 0 : index-1);
		},
		
		getVolume: function (playerID) {
			return currentVolume;
		}
		
	}
	
}();
