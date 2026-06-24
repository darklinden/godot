class_name SdkBridge
extends Node

## Eval-free JS bridge to WeChat Mini Game APIs.
##
## Uses direct JavaScriptObject method calls (get_interface + create_callback)
## instead of JavaScriptBridge.eval(), which is disabled in WeChat Mini Game.
##
## Each async wrapper creates a named callback, calls GameGlobal.__wx*(), awaits
## a done flag, and returns the unwrapped result. Sync wrappers call and return
## directly. Persistent listeners store their callback ref to prevent GC.
##
## All JS method calls use Object.call() to avoid unsafe_method_access warnings
## — the methods exist on the JS object at runtime but are invisible to GDScript's
## static type system.

var _game_global: JavaScriptObject = null

# Cached SceneTree ref — survives node removal from tree (await-friendly)
var _tree: SceneTree = null

# Persistent listener callback refs (must stay alive to avoid GC)
var _on_show_js_cb: JavaScriptObject = null
var _on_memory_warning_js_cb: JavaScriptObject = null
var _on_network_status_js_cb: JavaScriptObject = null

# User-supplied callbacks for persistent listeners
var _on_show_user_cb: Callable
var _on_memory_warning_user_cb: Callable
var _on_network_status_user_cb: Callable

# Re-entry guard
var _login_in_flight: bool = false

# Login state
var _login_result: Variant = null
var _login_done: bool = false

# Ad state
var _ad_result: Variant = null
var _ad_done: bool = false

# Share state
var _share_result: Variant = null
var _share_done: bool = false

# Network state
var _network_type_result: Variant = null
var _network_type_done: bool = false

# Add to desktop state
var _add_to_desktop_result: Variant = null
var _add_to_desktop_done: bool = false

# Clipboard state
var _clipboard_result: Variant = null
var _clipboard_done: bool = false

# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------


func _ready() -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	_tree = get_tree()
	_game_global = JavaScriptBridge.get_interface("GameGlobal")
	if _game_global == null:
		printerr("[SdkBridge] GameGlobal interface not found")


# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------


static func is_wechat_available() -> bool:
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	return JavaScriptBridge.get_interface("GameGlobal") != null


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


## JavaScriptBridge.create_callback wraps JS args in an Array.
static func _unwrap(value: Variant) -> Variant:
	if value is Array:
		var arr: Array = value
		if arr.size() > 0:
			return arr[0]
	return value


# ---------------------------------------------------------------------------
# Login — wx.login() → code
# ---------------------------------------------------------------------------


func _on_login_cb(v: Variant) -> void:
	_login_result = _unwrap(v)
	_login_done = true


func login_async() -> String:
	if _login_in_flight:
		printerr("[SdkBridge] wx.login() already in flight — rejecting duplicate call")
		return ""
	_login_in_flight = true
	print("[SdkBridge] calling wx.login()...")

	_login_result = null
	_login_done = false

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_on_login_cb"))
	if cb == null:
		_login_in_flight = false
		printerr("[SdkBridge] create_callback failed for __wxLogin")
		return ""

	_game_global.call("__wxLogin", cb)

	while not _login_done:
		if not _tree:
			_login_in_flight = false
			return ""
		await _tree.process_frame

	_login_in_flight = false

	if _login_result is String:
		var str_result: String = _login_result
		if str_result.is_empty():
			printerr("[SdkBridge] wx.login() returned empty code")
		else:
			print(
				"[SdkBridge] wx.login() OK code_len=%d code=%s" % [str_result.length(), str_result]
			)
		return str_result
	printerr("[SdkBridge] wx.login() unexpected result type: ", typeof(_login_result))
	return ""


# ---------------------------------------------------------------------------
# Ad — rewarded video / interstitial → "ok" | "cancel" | "fail"
# ---------------------------------------------------------------------------


func _on_ad_cb(v: Variant) -> void:
	_ad_result = _unwrap(v)
	_ad_done = true


func show_ad_async(interstitial: bool, ad_unit_id: String = "") -> String:
	if _game_global == null:
		return "fail"

	_ad_result = null
	_ad_done = false

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_on_ad_cb"))
	if cb == null:
		printerr("[SdkBridge] create_callback failed for __wxShowAd")
		return "fail"

	_game_global.call("__wxShowAd", interstitial, ad_unit_id, cb)

	while not _ad_done:
		if not _tree:
			return "fail"
		await _tree.process_frame

	if _ad_result is String:
		return _ad_result
	return "fail"


# ---------------------------------------------------------------------------
# onShow — app foreground events (persistent listener)
# ---------------------------------------------------------------------------


func _on_show_cb(payload: Variant) -> void:
	if payload is String:
		var text: String = payload
		if not text.is_empty():
			var json: JSON = JSON.new()
			if json.parse(text) == OK:
				var data: Variant = json.get_data()
				if data is Dictionary and not _on_show_user_cb.is_null():
					_on_show_user_cb.call(data)


func setup_on_show(on_show_callback: Callable) -> void:
	if _game_global == null:
		return

	_on_show_user_cb = on_show_callback
	if _on_show_js_cb == null:
		_on_show_js_cb = JavaScriptBridge.create_callback(Callable(self, "_on_show_cb"))
		if _on_show_js_cb:
			_game_global.call("__wxOnShow", _on_show_js_cb)


# ---------------------------------------------------------------------------
# Share
# ---------------------------------------------------------------------------


## Set multi-scene share config. Passed directly as parameters to avoid
## the window identity mismatch between get_interface("window") and JS global.
func set_share_config(title: String, image_url: String = "", query: String = "") -> void:
	if _game_global == null:
		return
	_game_global.call("__wxSetShareConfig", title, image_url, query)


func _on_share_cb(v: Variant) -> void:
	_share_result = _unwrap(v)
	_share_done = true


func share_app_message_async() -> String:
	if _game_global == null:
		return "fail"

	_share_result = null
	_share_done = false

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_on_share_cb"))
	if cb == null:
		printerr("[SdkBridge] create_callback failed for __wxShareAppMessage")
		return "fail"

	_game_global.call("__wxShareAppMessage", cb)

	while not _share_done:
		if not _tree:
			return "fail"
		await _tree.process_frame

	if _share_result is String:
		return _share_result
	return "fail"


func update_share_menu(with_share_ticket: bool, is_private_message: bool = true) -> void:
	if _game_global == null:
		return
	_game_global.call("__wxUpdateShareMenu", with_share_ticket, is_private_message)


# ---------------------------------------------------------------------------
# Vibration
# ---------------------------------------------------------------------------


func vibrate_short(type: String = "medium") -> void:
	if _game_global == null:
		return
	_game_global.call("__wxVibrateShort", type)


func vibrate_long() -> void:
	if _game_global == null:
		return
	_game_global.call("__wxVibrateLong")


# ---------------------------------------------------------------------------
# Memory
# ---------------------------------------------------------------------------


func _on_memory_warning_cb(level: Variant) -> void:
	if not _on_memory_warning_user_cb.is_null():
		_on_memory_warning_user_cb.call(level)


func setup_memory_warning(callback: Callable) -> void:
	if _game_global == null:
		return

	_on_memory_warning_user_cb = callback
	if _on_memory_warning_js_cb == null:
		_on_memory_warning_js_cb = JavaScriptBridge.create_callback(
			Callable(self, "_on_memory_warning_cb")
		)
		if _on_memory_warning_js_cb:
			_game_global.call("__wxOnMemoryWarning", _on_memory_warning_js_cb)


func trigger_gc() -> void:
	if _game_global == null:
		return
	_game_global.call("__wxTriggerGC")


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------


class NetworkStatus:
	var is_network_connected: bool
	var network_type: String

	func _init(p_is_connected: bool, p_network_type: String) -> void:
		is_network_connected = p_is_connected
		network_type = p_network_type


func _on_network_type_cb(v: Variant) -> void:
	_network_type_result = _unwrap(v)
	_network_type_done = true


func get_network_type_async() -> NetworkStatus:
	if _game_global == null:
		return NetworkStatus.new(false, "unknown")

	_network_type_result = null
	_network_type_done = false

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(
		Callable(self, "_on_network_type_cb")
	)
	if cb == null:
		printerr("[SdkBridge] create_callback failed for __wxGetNetworkType")
		return NetworkStatus.new(false, "unknown")

	_game_global.call("__wxGetNetworkType", cb)

	while not _network_type_done:
		if not _tree:
			return NetworkStatus.new(false, "unknown")
		await _tree.process_frame

	return _parse_network_status(_network_type_result)


func _on_network_status_cb(json_str: Variant) -> void:
	if not _on_network_status_user_cb.is_null():
		_on_network_status_user_cb.call(_parse_network_status(json_str))


func setup_network_status_change(callback: Callable) -> void:
	if _game_global == null:
		return

	_on_network_status_user_cb = callback
	if _on_network_status_js_cb == null:
		_on_network_status_js_cb = JavaScriptBridge.create_callback(
			Callable(self, "_on_network_status_cb")
		)
		if _on_network_status_js_cb:
			_game_global.call("__wxOnNetworkStatusChange", _on_network_status_js_cb)


func _parse_network_status(raw: Variant) -> NetworkStatus:
	if raw is String:
		var str_raw: String = raw
		if not str_raw.is_empty():
			var json: JSON = JSON.new()
			if json.parse(str_raw) == OK:
				var data: Variant = json.get_data()
				if data is Dictionary:
					var dict: Dictionary = data
					var is_connected_val: Variant = dict.get("isConnected", false)
					var net_type_val: Variant = dict.get("networkType", "unknown")
					var is_connected_bool: bool = false
					var net_type: String = "unknown"
					if is_connected_val is bool:
						is_connected_bool = is_connected_val
					if net_type_val is String:
						net_type = net_type_val
					return NetworkStatus.new(is_connected_bool, net_type)
	return NetworkStatus.new(false, "unknown")


# ---------------------------------------------------------------------------
# Add to desktop
# ---------------------------------------------------------------------------


func _on_add_to_desktop_cb(v: Variant) -> void:
	_add_to_desktop_result = _unwrap(v)
	_add_to_desktop_done = true


func add_to_desktop_async() -> String:
	if _game_global == null:
		return "fail"

	_add_to_desktop_result = null
	_add_to_desktop_done = false

	var _add_cb: JavaScriptObject = JavaScriptBridge.create_callback(
		Callable(self, "_on_add_to_desktop_cb")
	)
	if _add_cb == null:
		printerr("[SdkBridge] create_callback failed for __wxAddToDesktop")
		return "fail"

	_game_global.call("__wxAddToDesktop", _add_cb)

	while not _add_to_desktop_done:
		if not _tree:
			return "fail"
		await _tree.process_frame

	if _add_to_desktop_result is String:
		return _add_to_desktop_result
	return "fail"


# ---------------------------------------------------------------------------
# Launch options — sync return
# ---------------------------------------------------------------------------


class LaunchOptions:
	var scene: int
	var query: Dictionary
	var share_ticket: String

	func _init(p_scene: int, p_query: Dictionary, p_share_ticket: String) -> void:
		scene = p_scene
		query = p_query
		share_ticket = p_share_ticket


func get_launch_options_sync() -> LaunchOptions:
	if _game_global == null:
		return LaunchOptions.new(0, {}, "")

	var raw: Variant = _game_global.call("__wxGetLaunchOptionsSync")
	if raw is String:
		var str_raw: String = raw
		if not str_raw.is_empty():
			var json: JSON = JSON.new()
			if json.parse(str_raw) == OK:
				var data: Variant = json.get_data()
				if data is Dictionary:
					var dict: Dictionary = data
					var scene_val: Variant = dict.get("scene", 0)
					var query_val: Variant = dict.get("query", {})
					var ticket_val: Variant = dict.get("shareTicket", "")
					var scene: int = 0
					var query_dict: Dictionary = {}
					var ticket: String = ""
					if scene_val is int:
						scene = scene_val
					if query_val is Dictionary:
						query_dict = query_val
					if ticket_val is String:
						ticket = ticket_val
					return LaunchOptions.new(scene, query_dict, ticket)
	return LaunchOptions.new(0, {}, "")


# ---------------------------------------------------------------------------
# Clipboard
# ---------------------------------------------------------------------------


func _on_clipboard_cb(v: Variant) -> void:
	_clipboard_result = _unwrap(v)
	_clipboard_done = true


func set_clipboard_data_async(text: String) -> String:
	if _game_global == null:
		return "fail"

	_clipboard_result = null
	_clipboard_done = false

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_on_clipboard_cb"))
	if cb == null:
		printerr("[SdkBridge] create_callback failed for __wxSetClipboardData")
		return "fail"

	_game_global.call("__wxSetClipboardData", text, cb)

	while not _clipboard_done:
		if not _tree:
			return "fail"
		await _tree.process_frame

	if _clipboard_result is String:
		return _clipboard_result
	return "fail"


func get_clipboard_data_async() -> String:
	if _game_global == null:
		return ""

	_clipboard_result = null
	_clipboard_done = false

	var cb: JavaScriptObject = JavaScriptBridge.create_callback(Callable(self, "_on_clipboard_cb"))
	if cb == null:
		printerr("[SdkBridge] create_callback failed for __wxGetClipboardData")
		return ""

	_game_global.call("__wxGetClipboardData", cb)

	while not _clipboard_done:
		if not _tree:
			return ""
		await _tree.process_frame

	if _clipboard_result is String:
		return _clipboard_result
	return ""
