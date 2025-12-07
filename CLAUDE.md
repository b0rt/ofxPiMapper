# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

### Building Examples
```bash
# Build and run the basic example
cd example_basic
make
./bin/example_basic

# Run in fullscreen mode
./bin/example_basic -f

# Build other examples (camera, fbo-sources, gamepad, remote-client, remote-server, etc.)
cd example_<name>
make && ./bin/example_<name>
```

### Linux Development Notes
On non-Raspberry Pi Linux systems:
- Remove `ofxOMXPlayer` from `example/addons.make` (RPi-only dependency)
- Remove `ofxRPiCameraVideoGrabber` from `example_camera/addons.make` (RPi-only)

### Video Encoding for ofxPiMapper
Videos must be encoded properly for playback. Use HandBrake:
```
Preset: Fast 720p30
Format: MKV File
Framerate: Same as source
Profile: Baseline
Audio Codec: FLAC 16-bit
Audio Samplerate: 22.05 KHz
```

Or use ffmpeg:
```bash
ffmpeg -i input-video.mp4 -s 1280x720 -aspect 16:9 \
  -c:v libx264 -profile:v baseline \
  -c:a pcm_s16le -ar 22000 -ac 2 \
  output-video.mov
```

## Architecture Overview

ofxPiMapper is an OpenFrameworks addon for projection mapping optimized for Raspberry Pi. It uses a state machine architecture with command pattern for undo/redo support.

### Key Technologies
- OpenFrameworks 0.9+
- C++ with namespace `ofx::piMapper`
- GLES2 rendering (with GLES1 fallback)
- XML-based persistence (ofxXmlSettings)
- Event-driven architecture

### High-Level Component Relationships

```
ofxPiMapper (public facade)
  ↓
Application (orchestrator)
  ├── ApplicationBaseMode (state machine: 4 modes)
  ├── SurfaceManager (manages SurfaceStack presets)
  ├── MediaServer (auto-discovers assets)
  ├── CmdManager (undo/redo stack)
  └── Gui (event broadcasting system)
```

### Core Components

**Application** (`src/Application/Application.h/cpp`)
- Central orchestrator that manages mode switching, event routing, and command execution
- Auto-saves every 60 seconds outside Presentation Mode
- Manages keyboard shortcuts including 3-character sequences ("new", "rbt", "sdn", "ext")

**Application Modes** (`src/Application/Modes/`)
Four modes implement `ApplicationBaseMode`:
1. **PresentationMode** (Key 1) - Final output rendering, forced on startup for video sync
2. **ProjectionMappingMode** (Key 3) - Surface geometry editing with interactive joints
3. **TextureMappingMode** (Key 2) - UV coordinate adjustment
4. **SourceSelectionMode** (Key 4) - Media source assignment

**Command System** (`src/Commands/`)
- 45+ commands inherit from `BaseCmd` or `BaseUndoCmd`
- `CmdManager` maintains undo stack (Key 'z' to undo)
- All user actions (move vertex, add surface, scale, etc.) are encapsulated as commands
- Examples: `MvSurfaceVertCmd`, `AddSurfaceCmd`, `SetNextSourceCmd`, `TogglePerspectiveCmd`

**Surface System** (`src/Surfaces/`)
- `BaseSurface` abstract base with 5 concrete types: QuadSurface, TriangleSurface, GridWarpSurface, CircleSurface, HexagonSurface
- `SurfaceManager` handles selection state and surface collection
- `SurfaceStack` groups surfaces into presets (switchable at runtime)
- `SurfaceFactory` singleton for type-safe creation

**Source System** (`src/Sources/`)
- `BaseSource` hierarchy: ImageSource, VideoSource, FboSource
- `MediaServer` auto-discovers from: `sources/images/`, `sources/videos/`, USB drives, `/boot/ofxpimapper/`
- `DirectoryWatcher` monitors filesystem for new assets
- VideoSource supports multi-Raspberry Pi synchronization via ofxVideoSync

**GUI System** (`src/Gui/`)
- Singleton `Gui` class broadcasts three event types: `GuiJointEvent`, `GuiSurfaceEvent`, `GuiBackgroundEvent`
- Texture-based GUI for GLES2 (replaced ofxGui due to performance issues)
- Interactive elements: `CircleJoint` (vertex handles), `EdgeBlendJoint` (GLES2 blend controls)
- Main widgets in `src/UserInterface/`: ProjectionEditor, TextureEditor, SourcesEditor, ScaleWidget, LayerPanel

**Persistence** (`src/Application/SettingsLoader.h/cpp`)
- XML serialization to `bin/data/ofxpimapper.xml`
- Saves: surface types, vertices, texture coords, source assignments, preset names
- Manual save: Key 's'

### Design Patterns in Use

- **State Machine**: ApplicationBaseMode hierarchy for mode switching
- **Command Pattern**: Undo/redo support via CmdManager
- **Observer**: ofEvent system for loose coupling between components
- **Singleton**: Gui, SurfaceFactory, SettingsLoader
- **Factory**: SurfaceFactory for type-safe surface creation
- **Composite**: SurfaceStack collections

### Data Flow Example: Moving a Vertex

```
User drags vertex
  → ProjectionMappingMode::onMouseDragged()
  → CircleJoint hit test
  → GuiJointEvent broadcast
  → MvSurfaceVertCmd created and executed
  → CmdManager::exec() adds to undo stack
  → BaseSurface::setVertex()
  → vertexChangedEvent broadcast
  → GUI updates visual representation
```

### Rendering Pipeline

**GLES2 Path** (modern, with shader support):
- Perspective correction via homography shader
- Edge blending shader (QuadSurface only)
- Vertex array objects (VAO) for efficiency

**GLES1 Path** (legacy compatibility):
- Fixed-function homography matrix
- Software edge blending

**Video Synchronization**:
- ofxVideoSync enables multi-RPi LAN synchronization
- Presentation Mode locked to 30 FPS for smooth sync
- Platform-specific: ofxOMXPlayer (RPi hardware decoder) or ofxVideoSync (desktop)

### Important Files

- `src/ofxPiMapper.h/cpp` - Public API facade
- `src/Application/Application.h/cpp` - Core orchestrator
- `src/Surfaces/BaseSurface.h` - Surface interface
- `src/Commands/CmdManager.h/cpp` - Undo/redo manager
- `src/Gui/Gui.h/cpp` - Event broadcasting
- `addon_config.mk` - Addon metadata and dependencies

### Dependencies

Core (from `addon_config.mk`):
- ofxXmlSettings (included with OpenFrameworks)
- ofxVideoSync (custom fork for multi-device video sync)
- ofxOsc (for remote control features)

Platform-specific:
- ofxOMXPlayer (Raspberry Pi hardware video decoder)
- ofxRPiCameraVideoGrabber (Raspberry Pi camera support)

### Custom Development

**Creating Custom FBO Sources**:
```cpp
class MyCustomSource : public ofx::piMapper::FboSource {
    void draw() override {
        // Render custom content to FBO
    }
};
// Register with mapper
mapper.registerFboSource(myCustomSource);
```

**Creating Custom Commands**:
```cpp
class MyCommand : public ofx::piMapper::BaseUndoCmd {
    void exec() override { /* perform action */ }
    void undo() override { /* reverse action */ }
};
```

**Listening to Surface Events**:
```cpp
ofAddListener(surface->vertexChangedEvent, this, &MyClass::onVertexChanged);
```

## Important Keyboard Shortcuts

Mode switching: 1 (Presentation), 2 (Texture), 3 (Projection), 4 (Source)
Surface creation: t (triangle), q (quad), g (grid), c (circle)
Surface editing: d (duplicate), + (scale up), - (scale down), p (toggle perspective)
Grid editing: ] (add columns), [ (remove columns), } (add rows), { (remove rows)
Navigation: . (next surface), , (previous surface), > (next vertex), < (previous vertex)
Layer ordering: 0 (move up), 9 (move down), l (toggle layer panel)
Actions: s (save), z (undo), BACKSPACE (delete), SPACE (pause video), TAB (next source)
Special: new (clear), ext (exit), rbt (reboot RPi), sdn (shutdown RPi)

## Fork-Specific Features

This fork includes features not in upstream ofxPiMapper:
- GLES2 renderer with shader support
- Edge blending via shaders (QuadSurface only)
- Video playback synchronization across multiple Raspberry Pis (requires custom ofxOMXPlayer branch)
- Texture-based GUI replacing ofxGui (faster rendering)
- Presentation Mode forced on startup to enable video sync

## Directory Structure

```
src/
  ├── Application/        # Core orchestrator, 4 modes, SettingsLoader
  ├── Commands/           # 45+ command classes for undo/redo
  ├── Surfaces/           # BaseSurface + 5 concrete types + manager/factory
  ├── Sources/            # BaseSource + 3 types (Image, Video, FBO)
  ├── MediaServer/        # Asset discovery and DirectoryWatcher
  ├── Gui/                # Event broadcasting system
  ├── UserInterface/      # Interactive joints and widgets
  ├── Info/               # Info display overlay
  ├── Types/              # Custom Vec2/Vec3 (version-agnostic)
  ├── Utils/              # Homography calculations
  └── ofxPiMapper.h/cpp   # Public API facade
```
