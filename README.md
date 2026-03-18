# MemBar

A lightweight macOS menu bar app that shows **live RAM usage** — color-coded by memory pressure, updated every 2 seconds, no Dock icon.

```
6.4 GB    ← green / yellow / red depending on pressure
```

Click the indicator to open a detail popover:

```
┌─────────────────────────────────┐
│  MEMORY  PRESSURE               │
│  6.42 GB          / 16 GB total │
│  ████████████░░░░░░░░░░░░░░░░   │
│  Wired: 2.1 GB          41%     │
│ ─────────────────────────────── │
│  Wi-Fi              192.168.1.5 │
│  [ Quit MemBar ]                │
└─────────────────────────────────┘
```

---

## Requirements

| | |
|---|---|
| **macOS** | 13 Ventura or later |
| **Xcode CLT** | `xcode-select --install` |
| **Swift** | Bundled with CLT (≥ 5.9) |

---

## Quick start

```bash
git clone https://github.com/your-username/MemBar
cd MemBar
chmod +x build.sh
./build.sh          # compile → run immediately
```

## Install as a login item (auto-start on login)

```bash
git clone https://github.com/your-username/MemBar
cd MemBar
chmod +x build.sh
./build.sh install
```

This compiles a release binary to `~/.local/bin/MemBar` and registers a `launchd` plist so it starts automatically at login.

## Uninstall

```bash
./build.sh remove
```

---

## Memory explained

| Field | What it means |
|-------|---------------|
| **Used** | Active + wired + compressed pages — RAM currently in use |
| **Wired** | Memory locked by the kernel and drivers; cannot be swapped or compressed |
| **Pressure %** | Used ÷ total — how hard the system is working to satisfy memory demand |

## Color coding

| Color | Pressure |
|-------|----------|
| 🟢 Green  | < 60% |
| 🟡 Yellow | 60 – 80% |
| 🔴 Red    | > 80% |

---

## Project layout

```
MemBar/
├── Package.swift           ← Swift Package Manager manifest
├── build.sh                ← build / install / remove script
└── Sources/
    └── MemBar/
        └── main.swift      ← entire app (~260 lines)
```
