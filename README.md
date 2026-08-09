# Soundfridge

> **Early-stage project:** Soundfridge is under active development and is not yet ready for general use.

Soundfridge is a macOS audio utility for output devices that macOS cannot control with its normal system volume controls, especially fixed-volume HDMI and DisplayPort audio devices.

The goal is deliberately simple:

**Make a fixed-volume output behave like a normal macOS audio device, with volume and mute controlled from the keyboard, Control Center, and the standard Sound interface.**

Soundfridge is derived from [SoundBridge](https://github.com/chenjy16/SoundBridge) by chenjy16. SoundBridge provided the virtual Core Audio driver, host audio engine, shared-memory transport, device-management code, and much of the foundation that made this project possible.

Soundfridge is now taking a different product and architectural direction. It should be considered its own project rather than a rebranding of SoundBridge.

---

## Project status

Soundfridge is currently in **early development**.

The backend is functional enough to prove the core concept, but installation, configuration, packaging, UI, and long-term service management are still being redesigned.

At this stage, the project is intended primarily for development and testing.

### Working today

- Core Audio HAL virtual proxy devices
- Audio forwarding from a virtual device to physical hardware
- Standard macOS volume and mute controls on the proxy device
- Detection of physical output devices
- Detection of whether Core Audio already provides writable volume control
- Filtering of devices that do not need Soundfridge
- Persistent device decisions (`pending`, `managed`, `ignored`)
- Hot-plug handling
- A persistent Host process that can remain idle when no managed device is connected
- Runtime transitions between idle and active states
- Sleep/wake recovery
- Immediate configuration reconciliation without restarting the Host

### Still in development

- A minimal configuration application
- First-run device selection
- Driver/Host installation and lifecycle management
- Reliable launch-at-login/background-service installation
- Packaging, signing, notarization, updates, and uninstall
- User-facing documentation and release process

---

## Why Soundfridge?

Some HDMI and DisplayPort audio outputs appear normally in macOS but expose no writable system volume control. When one of these devices is selected, the macOS volume slider may be disabled and the keyboard volume keys may do nothing.

Soundfridge places a virtual Core Audio output device in front of that physical device.

Applications send audio to the virtual device. Soundfridge then forwards that audio to the real hardware while applying software volume control.

From the user's perspective, the desired result is simply:

```text
Keyboard volume keys
        │
Control Center volume
        │
System Settings → Sound
        │
        ▼
Soundfridge virtual device
        │
        ▼
Fixed-volume physical output
```

The virtual device exists so macOS can treat the output like a normal volume-controllable audio device.

---

## Design philosophy

Soundfridge is intentionally moving away from the original SoundBridge user experience.

### Use macOS controls, not another volume UI

The primary interface for volume should be the interface macOS already provides:

- keyboard volume keys
- Control Center
- System Settings
- normal Core Audio APIs used by applications

Soundfridge does **not** aim to provide a second permanent volume slider in a menu bar application.

If the virtual device is doing its job, the user should rarely need to think about Soundfridge at all.

### A background service is intentional

SoundBridge explicitly emphasized having no invisible background daemon. Soundfridge makes a different tradeoff.

For Soundfridge, a persistent background Host is desirable because audio-device management is infrastructure, not an interactive application task.

The Host needs to remain available so it can:

- notice devices being connected or disconnected
- create and remove proxy mappings
- transition between idle and active operation
- recover after sleep and wake
- react immediately to configuration changes
- provide audio forwarding whenever a managed device is selected

The long-term goal is therefore:

```text
Soundfridge.app
    Configuration / setup only
    Not a permanent menu bar volume controller
            │
            │ configuration
            ▼
Soundfridge Host
    Persistent background service
            │
            ▼
Soundfridge HAL Driver
    Virtual Core Audio devices
            │
            ▼
Physical audio hardware
```

The configuration app should be something the user opens when configuration is needed, not something that must remain visible for volume control to work.

### Keep the product small

Soundfridge is not intended to become a general-purpose audio mixer.

Current priorities are:

1. detect outputs that actually need software volume control
2. let the user choose which of those outputs Soundfridge should manage
3. make those devices work naturally with macOS volume controls
4. stay reliable across reconnects, sleep/wake, and login
5. keep configuration and maintenance simple

Features that do not support that core goal should earn their complexity.

---

## Device management

Soundfridge distinguishes between devices that macOS can already control and devices that may need a proxy.

For each physical output, the Host examines Core Audio capabilities.

If the device already exposes writable output volume control, Soundfridge leaves it alone.

If it does not, the device may become a Soundfridge candidate.

Known candidate devices are currently recorded with one of three decisions:

```text
pending   User has not chosen yet
managed   Soundfridge should provide a proxy
ignored   Soundfridge should leave it alone
```

The upcoming configuration UI will provide the user-facing controls for these decisions.

The intended first-run interaction is roughly:

```text
New fixed-volume output detected

DELL U4025QW

[ Manage ]    [ Ignore ]
```

Once a decision changes, the running Host can reconcile the new configuration without restarting.

---

## Architecture

Soundfridge currently inherits the core multi-process architecture of SoundBridge, but responsibilities are being simplified.

```text
┌──────────────────────┐
│ Soundfridge App      │
│ Swift / SwiftUI      │
│                      │
│ Setup & preferences  │
└──────────┬───────────┘
           │
           │ configuration
           ▼
┌──────────────────────┐
│ Soundfridge Host     │
│ Swift                │
│                      │
│ Device discovery     │
│ Lifecycle management │
│ Audio rendering      │
└──────────┬───────────┘
           │
           │ shared memory / control state
           ▼
┌──────────────────────┐
│ HAL Virtual Driver   │
│ C++ / libASPL        │
│                      │
│ Core Audio proxies   │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Physical Device      │
│ HDMI / DP / USB      │
└──────────────────────┘
```

### Host lifecycle

The Host has an explicit lifecycle:

```text
STARTING
   │
   ├── device available ──► ACTIVE
   │
   └── no device ─────────► IDLE

IDLE ◄────────────────────► ACTIVE

IDLE / ACTIVE ────────────► STOPPING
```

`IDLE` is a normal operating state. The Host remains alive but does not keep an unnecessary AudioEngine running.

When a managed device appears, the Host can initialize the required audio resources and become active. When the last managed device disappears, those resources are torn down and the Host returns to idle.

---

## Relationship to SoundBridge

Soundfridge exists because of the substantial work done in the original [SoundBridge](https://github.com/chenjy16/SoundBridge) project.

In particular, SoundBridge provided important foundations including:

- the Core Audio HAL virtual-driver architecture
- the Swift Host engine
- shared-memory communication between driver and Host
- physical-device discovery and routing
- installation and packaging work
- the original macOS application
- DSP infrastructure
- a working demonstration that this approach is viable on modern macOS

Soundfridge began as a fork while investigating fixes and improvements to SoundBridge.

Some generally useful fixes developed during that work are being contributed back upstream where appropriate.

The projects now differ mainly in product direction.

SoundBridge was designed around a visible menu bar application with its own volume controls and additional audio features such as EQ.

Soundfridge instead aims for a small background system whose primary user interface for volume is **macOS itself**.

The original author's work remains an important part of Soundfridge's technical lineage and is gratefully acknowledged.

---

## Repository layout

The repository still largely reflects the inherited SoundBridge structure and will change as the project evolves.

```text
soundfridge/
├── apps/mac/
│   └── SoundBridgeApp/          # Existing macOS app; being redesigned
├── packages/
│   ├── driver/                  # Core Audio HAL virtual driver
│   ├── host/                    # Background Host engine
│   └── dsp/                     # Inherited DSP subsystem
├── tools/
├── Makefile
└── README.md
```

Names and directory structure still contain `SoundBridge` in several places. Renaming is not currently a priority; functionality and architecture are being stabilized first.

The inherited DSP subsystem also remains in the repository for now. Soundfridge's core goal does not require a user-facing EQ, so its long-term role has not yet been decided.

---

## Building from source

Soundfridge currently uses the inherited SoundBridge build system.

### Requirements

- macOS
- Xcode Command Line Tools
- CMake
- Git
- the `libASPL` Git submodule

Clone and initialize submodules:

```bash
git clone <soundfridge-repository-url>
cd soundfridge
git submodule update --init --recursive
```

Install/check build dependencies:

```bash
make install-deps
```

Build all components:

```bash
make build
```

For Host-only development, a release build is often faster and avoids rebuilding unrelated components:

```bash
swift build --package-path packages/host --configuration release
```

Run the Host directly:

```bash
packages/host/start_host.sh
```

### Tests

Run the DSP test suite with:

```bash
make test
```

The build and development workflow is still inherited from SoundBridge and is expected to change as Soundfridge's application and installation model are redesigned.

---

## Development priorities

Near-term development is focused on closing the configuration loop between the background Host and a minimal macOS application.

The next major milestone is:

```text
Host discovers new candidate device
        │
        ▼
device recorded as pending
        │
        ▼
configuration app is notified
        │
        ▼
user chooses Manage or Ignore
        │
        ▼
configuration is saved
        │
        ▼
Host reconciles immediately
```

After that, attention can move toward installation, persistent service management, packaging, and release engineering.

---

## Contributing

Soundfridge is still young, and architecture may change quickly.

Small, focused changes are preferred over large feature additions. The project currently values:

- simple designs
- native macOS behavior
- clear failure modes
- readable code
- minimal dependencies
- changes that can be tested independently

Bug fixes that are broadly applicable to the original SoundBridge project should also be considered for contribution upstream.

---

## License

Soundfridge is derived from SoundBridge, which is distributed under the MIT License.

See the repository's license file for the applicable license text and attribution requirements.

---

## Acknowledgements

Soundfridge is based on **SoundBridge**, originally created by **chenjy16**.

The original project established the Core Audio architecture and much of the implementation that Soundfridge continues to build upon.

Thank you to the SoundBridge author and the open-source projects it depends on, including `libASPL`.
