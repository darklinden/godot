# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Build System

Godot uses **SCons** (Python-based) for building. The build entry point is `SConstruct`.

```bash
# Default editor build (debug features, dev_build=no)
scons

# Developer build (verbose, warnings=extra, werror=yes, tests=yes)
scons dev_mode=yes

# Production build
scons production=yes target=template_release

# Parallel build with explicit job count
scons -j8

# Build only specific modules (disable all, enable only what you need)
scons modules_enabled_by_default=no module_gdscript_enabled=yes
```

Key build variables:
- `target` — `editor` (default), `template_release`, `template_debug`
- `dev_build` — enables DEV_ENABLED code (editor-only debug tooling)
- `dev_mode` — alias for `verbose=yes warnings=extra werror=yes tests=yes strict_checks=yes`
- `tests` — build unit tests into the binary
- `production` — sets defaults for release builds (LTO, no debug)
- `platform` — auto-detected; override for cross-compilation

## Testing

The test framework is **doctest**. Tests live in `tests/` (mirroring the source structure under `tests/core/`, `tests/scene/`, `tests/servers/`).

```bash
# Build with tests enabled
scons tests=yes
# or: scons dev_mode=yes

# Run all tests
./bin/godot --test

# Run a specific test suite
./bin/godot --test "suite=TestNode"

# Run a specific test case
./bin/godot --test "test-case=TestNode.*create*"
```

Test macros (defined in `tests/test_macros.h`):
- `TEST_CASE(name)` — standard test case
- `TEST_COND(cond, ...)` — check condition is true
- `TEST_FAIL(cond, ...)` — unconditionally fail
- `TEST_FAIL_COND(cond, ...)` — fail if condition is true (required check)
- `TEST_CASE_PENDING(name)` — skip a test
- `TEST_CASE_MAY_FAIL(name)` — expected-flaky test

## Linting and Code Quality

Pre-commit hooks are managed via **prek** (`.pre-commit-config.yaml`). Run individual checks directly:

```bash
# Python linting
ruff check .
ruff format --check .

# Type checking
mypy .

# C++ formatting
clang-format -i <files>

# Spell checking
codespell

# Build system validation
python tests/python_build/validate_builders.py

# Class reference XML validation
python misc/scripts/validate_xml.py

# Copyright headers check
python misc/scripts/copyright_headers.py

# Header guard check
python misc/scripts/header_guards.py

# File formatting (newlines, trailing whitespace, BOM)
python misc/scripts/file_format.py

# Documentation RST generation (dry-run)
python doc/tools/make_rst.py doc/classes modules platform --dry-run --color
```

CI runs: `.github/workflows/static_checks.yml` (prek), platform-specific builds in `runner.yml`.

## Architecture

Godot is organized into layered subsystems:

### Core (`core/`)
Foundation layer with no scene/editor dependencies. Key subsystems:
- **Variant** (`core/variant/`) — Dynamic typed union covering all Godot types (int, float, String, Vector2/3, Color, Array, Dictionary, Object pointers, etc.). The core interop type between C++ and scripting.
- **Object** (`core/object/`) — Base class for most engine types. Provides reflection via ClassDB, signal/slot connections, property bindings, and method dispatch to scripts.
- **ClassDB** (`core/object/class_db.h`) — Central class registry. The `GDCLASS` macro registers a C++ class; `BIND_METHOD`/`BIND_ENUM_CONSTANT` macros expose methods/enums to scripting.
- **Resource** (`core/io/resource.h`) — `RefCounted` subclass for data containers. Resources are reference-counted, serializable, and can be loaded/saved to disk.
- **Math** (`core/math/`) — Vector2/3/4, Transform2D/3D, AABB, Basis, Quaternion, Color, Plane, etc.
- **OS** (`core/os/`) — Platform abstraction: threading, memory, file I/O, time.
- **Templates** (`core/templates/`) — Container types: HashMap, HashSet, Vector, LocalVector, List, RID_Owner, SafeRefCount, etc.

### Scene (`scene/`)
The scene tree and node hierarchy. All scene objects inherit from `Node` (which extends `Object`):
- **Node** (`scene/main/node.h`) — Base scene graph node. Has a parent, children, and a transform. Nodes form the scene tree.
- **2D** / **3D** — 2D and 3D scene nodes (Sprite2D, CollisionShape2D, MeshInstance3D, etc.)
- **GUI** — UI controls (Button, Label, LineEdit, etc.) extending `Control`.
- **Animation** — AnimationPlayer, AnimationTree, tweens.
- **Resources** (`scene/resources/`) — Resource subclasses for scenes: meshes, materials, textures, shaders, curves, etc.
- **Main** (`scene/main/`) — SceneTree, Viewport, Window, Tween, Timer, Node.

### Servers (`servers/`)
Service backends that manage heavy internal state via opaque `RID` handles. Scene nodes are thin wrappers that call into servers:
- **RenderingServer** — Rendering backend (Vulkan via RenderingDevice, or compatibility GLES3).
- **PhysicsServer2D / PhysicsServer3D** — Physics simulation backends (GodotPhysics or third-party like Jolt).
- **NavigationServer2D / NavigationServer3D** — Navmesh-based pathfinding.
- **AudioServer** — Audio playback and mixing.
- **DisplayServer** — Window management, clipboard, cursor, screen info.
- **TextServer** — Text shaping and font rendering (FreeType or MSDF-based fallback).

### Editor (`editor/`)
The Godot editor, built only when `target=editor`. Depends on core + scene + servers. Key areas:
- **editor/plugins/** — Editor plugins for various node types and features.
- **editor/import/** — Asset import pipeline (textures, models, audio).
- **editor/inspector/** — Property inspector with editing widgets.
- **editor/export/** — Export platform support.
- **editor/gui/** — Editor-specific UI (docks, file system, script editor).

### Modules (`modules/`)
Optional/pluggable subsystems, each with its own `register_types.cpp`:
- **GDScript** (`modules/gdscript/`) — The built-in scripting language. Tokenizer → Parser → Analyzer → Compiler → Bytecode VM.
- **Mono** (`modules/mono/`) — .NET/C# scripting support.
- **Physics engines** — `modules/godot_physics_2d/`, `modules/godot_physics_3d/`, `modules/jolt_physics/`.
- **Third-party integrations** — Most third-party code in `modules/` wraps libraries from `thirdparty/`.

### Platform (`platform/`)
Per-platform implementations: `android/`, `ios/`, `linuxbsd/`, `macos/`, `windows/`, `web/`, `visionos/`. Each has a `detect.py` for SCons, OS-specific I/O, and export templates.

### Entry Point
`main/main.cpp` — Parses command-line arguments, initializes subsystems, and either starts the editor, runs a project, or executes tests.

## Key Design Patterns

### Class Registration
Every class registered with the engine must use `GDCLASS(MyClass, ParentClass)` in its header and `MyClass::_bind_methods()` to expose methods/properties/signals. ClassDB then makes these available to scripting languages.

### RID Pattern
Servers return opaque `RID` handles (Resource ID) for objects they manage. Scene nodes hold RIDs rather than direct pointers. Example: a `Sprite2D` holds a `RID canvas_item` managed by the RenderingServer.

### Variant System
`Variant` is a tagged union covering all built-in types. It is the universal exchange format between C++ and scripts. Methods exposed to scripting receive and return Variants. The `BIND_METHOD` macro system handles automatic conversion.

### SCU Builds
Single Compilation Unit builds (`scu_builders.py`) combine multiple `.cpp` files into a single translation unit per directory to reduce compilation time. Used automatically based on SCons configuration.

### Class Reference Documentation
Documentation for engine classes lives in `doc/classes/*.xml` and `modules/*/doc_classes/*.xml`. These are generated/extracted from C++ source annotations via `doc/tools/make_rst.py`. The XML schema is in `doc/class.xsd`.
