# 编译 Godot Engine（微信小游戏适配版）

本文档从 `skills/` 目录提取，描述如何从官方 Godot 源码编译支持微信小游戏的引擎 WASM。

## 前置要求

-   **目标版本**：Godot `origin/4.6` 分支
-   **编译环境**：Emscripten (emsdk)，Node.js

## 步骤概览

```
1. 确认目标仓库版本
2. Apply patches + sources
3. scons 编译
4. JS 后处理 (godot_process.js)
5. WASM 压缩 (.wasm.br)
6. 安装 runtime shell (godot-sdk.js, godot-loader.js)
7. 验证
```

---

## 1. 确认目标仓库

```bash
cd /path/to/godot
```

## 2. Apply Patches

在 Godot 源码上应用微信小游戏适配 patch。改动涉及 9 个文件 + 7 个新增文件，详见 [patch-breakdown.md](patch-breakdown.md)。

### 核心改动一览

| 微信小游戏限制 | 对应改动 |
|---|---|
| 不能执行/扫描 `eval` | `eval` → `exec` 重命名；`JavaScriptBridge::eval()` 空实现 |
| 不支持 WASM_BIGINT (BigInt) | 禁用 `WASM_BIGINT` |
| 不支持 WASM SIMD | SIMD 条件门控；`wasm_simd` 默认关闭 |
| 不支持 fetch / Response | `fsUtils.localFetch` 替代；`library_godot_fetch.js` |
| 不支持 IndexedDB | `library_godot_fs.js` (WXMEMFS) |
| 不支持 Web Audio API | `library_godot_audio.js` |
| 不支持标准 canvas DOM API | WebGL 检测跳过；`library_godot_display.js` |
| 无 DOM 键盘事件 | `library_godot_input.js` |
| 无 Blob / FileReader | `library_blob.js` |
| 无 `crypto.subtle` | `library_godot_crypto.js` |
| 子包体积限制 | `.wasm.br` Brotli 加载 |
| 退出机制不同 | `wx.exitMiniProgram()` |
| 需识别运行环境 | `OS.has_feature("wechat"/"minigame"/"wxgame")` |
| JS 库加载顺序 | `AddJSPre` 优先注入 polyfill |
| `"eval"` 字符串在 WASM 数据段中被扫描拦截 | C++ 拆分 `JAVASCRIPT_EVAL_ENABLED`——只 guard `eval()`，`get_interface`/`create_callback` 在 Web 构建中无条件可用 |

### C++ `JAVASCRIPT_EVAL_ENABLED` 拆分

这是让 eval-free bridge 能够工作的**前置 C++ 改动**。涉及 2 个文件：

**`platform/web/api/api.cpp`**：
- `eval` 绑定加 `#ifdef JAVASCRIPT_EVAL_ENABLED` 守卫
- 拆分 stub 块：`eval()` stub 用 `JAVASCRIPT_EVAL_ENABLED`，`get_interface`/`create_callback`/`create_object` 等只用 `!WEB_ENABLED`（Web 构建中无条件编译）

**`platform/web/javascript_bridge_singleton.cpp`**：
- `eval()` 实现加 `#ifdef JAVASCRIPT_EVAL_ENABLED` 守卫，WeChat 构建中返回 `Variant()`
- `get_interface`/`create_callback`/`is_js_buffer` 等不 guard，Web 构建中始终有效

效果：`javascript_eval=no` 只剥离 `eval`，`get_interface` + `create_callback` 正常工作。

## 3. SCons 编译

```bash
cd /path/to/godot
scons platform=web target=template_release threads=no wasm_simd=no
```

**重要**：

-   **不要**加 `dlink_enabled=yes`——微信小游戏不支持 Emscripten 动态链接
-   `threads=no`：微信不支持 SharedArrayBuffer
-   `wasm_simd=no`：旧版 iOS WebKit 在微信里可能崩溃

产物路径：`bin/.web_zip/godot.js` + `bin/.web_zip/godot.wasm`

## 4. JS 后处理

```bash
node skills/scripts/godot_process.js
```

这个脚本对 Emscripten 生成的 `godot.js` 做两件事：

**文本替换：**

| 规则                                            | 说明                                  |
| ----------------------------------------------- | ------------------------------------- |
| `performance.now` → `nowPolyfill`               | 微信没有 `performance.now`            |
| `FS.mount(IDBFS,...)` → `FS.mount(WXMEMFS,...)` | 用 WXMEMFS 替代浏览器 IndexedDB       |
| `WebAssembly.RuntimeError` 处理                 | 条件检查，微信可能没有这个构造函数    |
| getValue/setValue i64                           | 无 `WASM_BIGINT` 时的回退实现         |
| `stat.ino` guard                                | 微信文件系统可能没有 inode            |
| invoke import 映射                              | 自动补全缺失的 Emscripten invoke 映射 |

**ES2020 语法转译：**

文本替换后自动调用 esbuild 将 JS 转译为 ES2018，消除微信不支持的语法：

-   `?.`（可选链）
-   `??`（空值合并）

无需额外命令。

## 5. WASM 压缩

```bash
sh skills/scripts/compress_wasm.sh
```

产物：`bin/.web_zip/godot.wasm.br`（Brotli 压缩）

## 6. 安装 Runtime Shell

将最小运行时文件复制到小游戏引擎子包目录：

```bash
python3 skills/scripts/install_min_runtime.py demo/wxgame/engine/
```

复制两个文件：

-   `godot-sdk.js`（8KB，ES5 兼容版）
-   `godot-loader.js`

### Runtime Shell 提供的接口

`godot-sdk.js` 是旧版 `godot-minigame-sdk` 的最小替代。引擎（`godot.js`）在运行时依赖它注入的三个对象，必须在引擎之前加载：

| 导出 | 用途 | 引擎引用位置 |
|------|------|-------------|
| `GODOTSDK.startGame(exe, pack)` | 启动引擎 | `game.js` 入口 |
| `GODOTSDK.audio.WEBAudio.audioContext` | 音频上下文（`wx.createWebAudioContext()`，含 onHide/onShow 生命周期） | `godot.js` 音频模块 |
| `fsUtils.localFetch(path)` | `wx.getFileSystemManager().readFile()` 封装 | `godot.js` preloader |
| `fsUtils.loadSubpackage(name, ...)` | 子包加载 | `GODOTSDK.load_pack()` |
| `GameGlobal.nowPolyfill` | 时间戳替代 `performance.now` | `godot.js` 计时 |
| `__globalAdapter` 键盘方法 | 输入桥接 | `godot.js` 输入模块 |
| `WXWebAssembly → WebAssembly` | 命名空间覆盖（`gameGlobal.CCWebAssembly`） | `godot.js` WASM 实例化 |

### 加载顺序（在 `godot.js` 之前）

1. `godot-sdk.js`
2. `godot-loader.js`
3. `godot.js`（编译产物）

## 7. 验证

参考 `skills/references/validation-checklist.md`，核心检查点：

```bash
# 静态锚点检查
rg -n "WXMEMFS|fsUtils.localFetch|wx.exitMiniProgram|wasm\.br" bin/.web_zip/godot.js platform/web/js/engine

# 文件存在性
ls bin/.web_zip/godot.js bin/.web_zip/godot.wasm.br
```

运行时验证（在微信开发者工具中）：

-   `user://` 读写持久化（WXMEMFS）
-   大文件 HTTP 下载字节正确
-   音频播放/停止/重放稳定
-   高 DPI 显示 + 键盘输入
-   退出走 `wx.exitMiniProgram()`

## 8. GDScript ↔ WeChat API Bridge

`JavaScriptBridge.eval()` 在微信小游戏中不可用（WASM 包中的字符串 `"eval"` 会被微信扫描拒绝）。取而代之的是 **eval-free bridge**，分两层：

| 层 | 文件 | 位置 |
|---|---|---|
| JS 侧 | `bridge/js/sdk_bridge.js` | 微信小游戏 `wxgame/js/` |
| GDScript 侧 | `bridge/gdscript/sdk_bridge.gd` | Godot 项目 `scripts/service/` |

### 工作原理

```
GDScript (sdk_bridge.gd)
  → JavaScriptBridge.get_interface("GameGlobal")
  → JavaScriptBridge.create_callback(Callable(self, "_on_login_cb"))
  → _game_global.call("__wxLogin", cb)           # 直接调用 JavaScriptObject 方法
  → GameGlobal.__wxLogin(cb)                      # JS 侧：sdk_bridge.js
  → wx.login({ success: cb })                     # 微信原生 API
```

**不加 `JavaScriptBridge.eval()`。** 所有调用走 `get_interface` + `create_callback` + `Object.call()`，完全避开 eval 关键字。

### JS 侧设计：callback 作为参数传递

`sdk_bridge.js` 的所有 `__wx*` 函数**接受 callback 作为参数**，而不是从 `window._wx*Cb` 读取：

```js
// ❌ 旧方式 — get_interface("window") ≠ JS 全局 window，扫码失败
GameGlobal.__wxLogin = function () {
    var cb = window._wxLoginCb;
    wx.login({ success: cb });
};

// ✅ 新方式 — callback 直接作为参数传入
GameGlobal.__wxLogin = function (cb) {
    wx.login({
        success: function (res) { if (cb) cb(res.code); },
        fail: function () { if (cb) cb(""); },
    });
};
```

原因：`JavaScriptBridge.get_interface("window")` 返回的 JavaScriptObject 和 JS IIFE 内部的 `windowObject` **不是同一个对象**，挂载到 `window._wx*Cb` 的属性无法被 JS 侧读到。传参完全规避了这个问题。

### JS 侧部署

`sdk_bridge.js` 在 `GameGlobal` 上注册所有 `__wx*` 封装函数。必须放在微信小游戏项目中，并在 `godot.js` **之前**加载：

```
加载顺序:
  1. engine/godot-sdk.js     # polyfills
  2. engine/godot-loader.js  # 加载器
  3. js/sdk_bridge.js        # ← WeChat API bridge（注册 GameGlobal.__wx*）
  4. engine/godot.js         # 引擎
```

### GDScript 侧用法

**1. 设成 autoload**

`project.godot`:
```
[autoload]
SdkBridgeInstance="*res://scripts/service/sdk_bridge.gd"
```

**2. 通过 WeChatService 调用**

```gdscript
# WeChatService 是 RefCounted，按需创建
class_name WeChatService
extends RefCounted

var _bridge: SdkBridge

func _init() -> void:
    _bridge = SdkBridgeInstance   # autoload 单例

func login_async() -> String:
    return await _bridge.login_async()
```

**3. 业务侧调用**

```gdscript
var wechat := WeChatService.new()
var code: String = await wechat.login_async()
```

### 提供的 API

| 方法 | 类型 | 说明 |
|------|------|------|
| `login_async()` | async → String | wx.login()，返回 code |
| `show_ad_async(interstitial, ad_unit_id)` | async → String | 激励视频/插屏广告，"ok"/"cancel"/"fail" |
| `get_launch_options_sync()` | sync → LaunchOptions | 启动参数 |
| `share_app_message_async()` | async → String | 主动分享 |
| `set_share_config(title, image_url, query)` | fire-and-forget | 设置分享卡片内容 |
| `update_share_menu(...)` | fire-and-forget | 更新分享菜单 |
| `setup_on_show(callback)` | persistent listener | 监听回到前台 |
| `setup_memory_warning(callback)` | persistent listener | 内存告警 |
| `setup_network_status_change(callback)` | persistent listener | 网络状态变化 |
| `get_network_type_async()` | async → NetworkStatus | 获取当前网络类型 |
| `add_to_desktop_async()` | async → String | 添加到桌面 |
| `get_clipboard_data_async()` | async → String | 读取剪贴板 |
| `set_clipboard_data_async(text)` | async → String | 写入剪贴板 |
| `vibrate_short(type)` | fire-and-forget | 短振动 |
| `vibrate_long()` | fire-and-forget | 长振动 |
| `trigger_gc()` | fire-and-forget | 触发 GC |

### 设计要点

- **Callback 传参**：JS 侧 `__wx*` 函数接受 callback 作为参数，不存 `window._wx*Cb`（规避 `get_interface("window")` ≠ JS 全局 `window` 的身份不一致问题）
- **Array unwrap**：JS callback 的参数在 C++ 层被包装成 `["val"]`，GDScript 回调用 `_unwrap()` 解包
- **Await 模式**：`while not _done: await _tree.process_frame`，不阻塞主线程
- **_tree 缓存**：`_ready()` 时 `_tree = get_tree()`，防止节点中途被移除后 `get_tree()` 返回 null
- **禁止 lambda**：`create_callback` 的 target 必须是命名成员方法（call by name），lambda 在 Godot 4.6 中作为 `Callable` 传入会导致 JS 侧回调失败。一次性操作用 `Callable(self, "_on_login_cb")`，持久化监听器用命名方法转发 + 成员变量存储用户回调

---

## 产物清单

构建完成后，将以下文件放入微信小游戏项目：

| 文件 | 来源 | 位置 |
|------|------|------|
| `godot.wasm.br` | `bin/.web_zip/godot.wasm.br` | `engine/` |
| `godot.js` | `bin/.web_zip/godot.js`（已 patch） | `engine/` |
| `godot-sdk.js` | `skills/assets/min-runtime/godot-sdk.js` | `engine/` |
| `godot-loader.js` | `skills/assets/min-runtime/godot-loader.js` | `engine/` |
| `game.js` | 宿主项目入口（调用 `GODOTSDK.startGame`） | 根目录 |
| `sdk_bridge.js` | `bridge/js/sdk_bridge.js` | `js/` |

GDScript 侧文件放在 Godot 项目中即可，随 `.pck` 导出：

| 文件 | 来源 | Godot 项目路径 |
|------|------|---------------|
| `sdk_bridge.gd` | `bridge/gdscript/sdk_bridge.gd` | `scripts/service/sdk_bridge.gd` |
| `wechat_service.gd` | 业务层封装（自行编写） | `scripts/service/wechat_service.gd` |

## WeChat JS 兼容性

微信小游戏 JS 引擎 **不支持** ES2020 语法：

-   `?.`（可选链）
-   `??`（空值合并）

`godot_process.js` 已集成 esbuild 自动转译（`--target=es2018`），无需手动处理。

`skills/assets/min-runtime/godot-sdk.js` 已经是 ES5 兼容版，无需处理。
