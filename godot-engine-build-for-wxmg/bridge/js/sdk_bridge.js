/**
 * WeChat Mini Game API wrappers for Godot JavaScriptBridge integration.
 *
 * Each wrapper accepts its Godot callback as a parameter (instead of reading
 * from window._wx*Cb), avoiding the window identity mismatch between
 * `get_interface("window")` and the JS global `window`.
 *
 * Usage from GDScript:
 *
 *   var cb = JavaScriptBridge.create_callback(Callable(self, "_on_login_cb"))
 *   JavaScriptBridge.get_interface("GameGlobal").__wxLogin(cb)
 */

// ---------------------------------------------------------------------------
// Login — wx.login()
// Callback receives: code (String) or "" on failure
// ---------------------------------------------------------------------------

GameGlobal.__wxLogin = function (cb) {
	wx.login({
		success: function (res) {
			if (cb) cb(typeof res.code === "string" ? res.code : "");
		},
		fail: function () {
			if (cb) cb("");
		},
	});
};

// ---------------------------------------------------------------------------
// Rewarded video / interstitial ad
// Parameters: interstitial (bool), adUnitId (string, optional), cb (function)
// Callback receives: "ok" | "cancel" | "fail"
// ---------------------------------------------------------------------------

GameGlobal.__wxShowAd = function (interstitial, adUnitId, cb) {
	var unitId = adUnitId || window.__wxAdUnitId || "";

	if (!unitId) {
		if (cb) cb("fail");
		return;
	}

	var ad;
	if (interstitial) {
		ad = wx.createInterstitialAd({ adUnitId: unitId });
	} else {
		ad = wx.createRewardedVideoAd({ adUnitId: unitId });
	}

	ad.onError(function () {
		if (cb) cb("fail");
	});

	ad.onClose(function (res) {
		if (res && res.isEnded) {
			if (cb) cb("ok");
		} else {
			if (cb) cb("cancel");
		}
	});

	ad.show().catch(function () {
		ad.load().then(function () {
			return ad.show();
		}).catch(function () {
			if (cb) cb("fail");
		});
	});
};

// ---------------------------------------------------------------------------
// App foreground events — wx.onShow()
// Callback receives: JSON {shareTicket: String, query: Object}
// ---------------------------------------------------------------------------

GameGlobal.__wxOnShow = function (cb) {
	wx.onShow(function (res) {
		if (cb) {
			var payload = JSON.stringify({
				shareTicket: res.shareTicket || "",
				query: res.query || {},
			});
			cb(payload);
		}
	});
};

// ---------------------------------------------------------------------------
// Share config — stores {title, imageUrl, query} for multi-scene share
// Used by both passive (onShareAppMessage) and active (shareAppMessage) share.
// Stored on GameGlobal to avoid the window identity mismatch between
// get_interface("window") and the JS global window.
// Callback: none (fire-and-forget)
// ---------------------------------------------------------------------------

GameGlobal.__wxShareConfigData = { title: "", imageUrl: "", query: "" };

GameGlobal.__wxSetShareConfig = function (title, imageUrl, query) {
	GameGlobal.__wxShareConfigData = {
		title: title || "",
		imageUrl: imageUrl || "",
		query: query || "",
	};
};

// Register wx.onShareAppMessage once. Returns stored config.
wx.onShareAppMessage(function () {
	var cfg = GameGlobal.__wxShareConfigData || {};
	return {
		title: cfg.title || "",
		imageUrl: cfg.imageUrl || "",
		query: cfg.query || "",
	};
});

// ---------------------------------------------------------------------------
// Active share — wx.shareAppMessage()
// Callback receives: "ok" | "cancel" | "fail"
// ---------------------------------------------------------------------------

GameGlobal.__wxShareAppMessage = function (cb) {
	var cfg = GameGlobal.__wxShareConfigData || {};
	wx.shareAppMessage({
		title: cfg.title || "",
		imageUrl: cfg.imageUrl || "",
		query: cfg.query || "",
		success: function () { if (cb) cb("ok"); },
		fail: function () { if (cb) cb("fail"); },
		complete: function () { }
	});
};

// ---------------------------------------------------------------------------
// Share menu — wx.updateShareMenu()
// Callback: none (fire-and-forget)
// ---------------------------------------------------------------------------

GameGlobal.__wxUpdateShareMenu = function (withShareTicket, isPrivateMessage) {
	wx.updateShareMenu({
		withShareTicket: withShareTicket === true || withShareTicket === "true",
		isPrivateMessage: isPrivateMessage === true || isPrivateMessage === "true",
	});
};

// ---------------------------------------------------------------------------
// Vibration — wx.vibrateShort() / wx.vibrateLong()
// Callback: none (fire-and-forget)
// ---------------------------------------------------------------------------

GameGlobal.__wxVibrateShort = function (type) {
	wx.vibrateShort({ type: type || "medium" });
};

GameGlobal.__wxVibrateLong = function () {
	wx.vibrateLong();
};

// ---------------------------------------------------------------------------
// Memory warning — wx.onMemoryWarning()
// Callback receives: level (int) — 5=low, 10=medium, 15=high
// ---------------------------------------------------------------------------

GameGlobal.__wxOnMemoryWarning = function (cb) {
	wx.onMemoryWarning(function (res) {
		if (cb) cb(res.level);
	});
};

// ---------------------------------------------------------------------------
// GC trigger — wx.triggerGC()
// Callback: none (fire-and-forget)
// ---------------------------------------------------------------------------

GameGlobal.__wxTriggerGC = function () {
	wx.triggerGC();
};

// ---------------------------------------------------------------------------
// Network type — wx.getNetworkType()
// Callback receives: JSON {isConnected: bool, networkType: String}
// ---------------------------------------------------------------------------

GameGlobal.__wxGetNetworkType = function (cb) {
	wx.getNetworkType({
		success: function (res) {
			if (cb) cb(JSON.stringify({
				isConnected: res.networkType !== "none",
				networkType: res.networkType,
			}));
		},
		fail: function () {
			if (cb) cb(JSON.stringify({ isConnected: false, networkType: "unknown" }));
		},
	});
};

// ---------------------------------------------------------------------------
// Network status change — wx.onNetworkStatusChange()
// Callback receives: JSON {isConnected: bool, networkType: String}
// ---------------------------------------------------------------------------

GameGlobal.__wxOnNetworkStatusChange = function (cb) {
	wx.onNetworkStatusChange(function (res) {
		if (cb) cb(JSON.stringify({
			isConnected: res.isConnected,
			networkType: res.networkType || "",
		}));
	});
};

// ---------------------------------------------------------------------------
// Add to desktop — wx.addToDesktop()
// Callback receives: "ok" | "cancel" | "fail"
// ---------------------------------------------------------------------------

GameGlobal.__wxAddToDesktop = function (cb) {
	wx.addToDesktop({
		success: function () { if (cb) cb("ok"); },
		fail: function () { if (cb) cb("fail"); },
		complete: function () { }
	});
};

// ---------------------------------------------------------------------------
// Launch options — wx.getLaunchOptionsSync()
// Returns: JSON {scene: int, query: Object, shareTicket: String} (sync, no callback)
// ---------------------------------------------------------------------------

GameGlobal.__wxGetLaunchOptionsSync = function () {
	var opts = wx.getLaunchOptionsSync();
	var scene = opts.scene || 0;
	var query = opts.query || {};
	var referrerInfo = opts.referrerInfo || {};
	var shareTicket = opts.shareTicket || "";
	var hostExtraData = opts.hostExtraData || "";
	var chatType = opts.chatType || 0;
	var retObj = {
		scene: scene,
		shareTicket: shareTicket,
		hostExtraData: hostExtraData,
		chatType: chatType,
	};
	for (var key in query) {
		if (query.hasOwnProperty(key)) {
			var val = query[key];
			if (typeof val !== "object") {
				retObj['query_' + key] = val;
			}
		}
	}
	for (var key in referrerInfo) {
		if (referrerInfo.hasOwnProperty(key)) {
			var val = referrerInfo[key];
			if (typeof val !== "object") {
				retObj['referrerInfo_' + key] = val;
			}
		}
	}
	console.log("wx.getLaunchOptionsSync:", JSON.stringify(retObj));
	return JSON.stringify(retObj);
};

// ---------------------------------------------------------------------------
// Device benchmark — wx.getDeviceBenchmarkInfo()
// Async callback style. Returns JSON {benchmarkLevel: int, modelLevel: int}
// (modelLevel: 0 unknown, 1 high-end, 2 mid, 3 low) or "" when unavailable
// (older base lib without wx.getDeviceBenchmarkInfo).
// ---------------------------------------------------------------------------

GameGlobal.__wxGetDeviceBenchmark = function (cb) {
	if (!cb) return;
	// Web (non-WeChat) exports don't have wx at all — fall back to unknown tier
	// so the GDScript side never waits for a timeout.
	if (typeof wx === "undefined" || typeof wx.getDeviceBenchmarkInfo !== "function") {
		console.warn("[SdkBridge] wx.getDeviceBenchmarkInfo unavailable, fallback unknown");
		if (cb) cb("");
		return;
	}
	try {
		wx.getDeviceBenchmarkInfo({
			success: function (res) {
				if (cb) {
					cb(
						JSON.stringify({
							benchmarkLevel:
								typeof res.benchmarkLevel === "number" ? res.benchmarkLevel : -1,
							modelLevel: typeof res.modelLevel === "number" ? res.modelLevel : 0,
						})
					);
				}
			},
			fail: function (err) {
				console.warn("[SdkBridge] wx.getDeviceBenchmarkInfo failed:", err && err.errMsg);
				if (cb) cb("");
			},
		});
	} catch (e) {
		console.warn("[SdkBridge] wx.getDeviceBenchmarkInfo threw:", e && e.message);
		if (cb) cb("");
	}
};

// ---------------------------------------------------------------------------
// Clipboard — wx.setClipboardData() / wx.getClipboardData()
// Both accept callback: returns "ok"/"fail" for set, text for get
// ---------------------------------------------------------------------------

GameGlobal.__wxSetClipboardData = function (text, cb) {
	wx.setClipboardData({
		data: text || "",
		success: function () { if (cb) cb("ok"); },
		fail: function () { if (cb) cb("fail"); },
	});
};

GameGlobal.__wxGetClipboardData = function (cb) {
	wx.getClipboardData({
		success: function (res) { if (cb) cb(res.data || ""); },
		fail: function () { if (cb) cb(""); },
	});
};

// ---------------------------------------------------------------------------
// Subscribe message — wx.requestSubscribeMessage()
// Callback receives: JSON string e.g. {"tmplId":"accept","tmplId2":"reject"}
// ---------------------------------------------------------------------------

GameGlobal.__wxRequestSubscribeMessage = function (tmplStr, cb) {
	if (typeof tmplStr !== "string" || tmplStr.length === 0) {
		if (cb) cb("{}");
		return;
	}
	var tmplIds = tmplStr.split(",");
	console.log("[sdk_bridge] requestSubscribeMessage tmplIds:", tmplIds);
	wx.requestSubscribeMessage({
		tmplIds: tmplIds,
		success: function (res) {
			console.log("[sdk_bridge] requestSubscribeMessage success:", JSON.stringify(res));
			if (cb) cb(JSON.stringify(res));
		},
		fail: function (err) {
			console.error("[sdk_bridge] requestSubscribeMessage failed:", JSON.stringify(err));
			if (cb) cb("{}");
		},
	});
};

// ---------------------------------------------------------------------------
// Storage — wx.setStorageSync() / wx.getStorageSync()
// Both synchronous.
// ---------------------------------------------------------------------------

GameGlobal.__wxSetStorageSync = function (key, jsonValue) {
	try {
		var parsed = JSON.parse(jsonValue);
		wx.setStorageSync(key, parsed);
	} catch (e) {
		console.error("[sdk_bridge] wx.setStorageSync failed:", e);
	}
};

GameGlobal.__wxGetStorageSync = function (key) {
	try {
		var value = wx.getStorageSync(key);
		if (value === "" || value === undefined || value === null) {
			return "{}";
		}
		if (typeof value === "object") {
			return JSON.stringify(value);
		}
		return String(value);
	} catch (e) {
		console.error("[sdk_bridge] wx.getStorageSync failed:", e);
		return "{}";
	}
};
