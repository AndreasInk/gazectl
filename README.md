<div align="center">
<pre> ██████╗  █████╗ ███████╗███████╗ ██████╗████████╗██╗
██╔════╝ ██╔══██╗╚══███╔╝██╔════╝██╔════╝╚══██╔══╝██║
██║  ███╗███████║  ███╔╝ █████╗  ██║        ██║   ██║
██║   ██║██╔══██║ ███╔╝  ██╔══╝  ██║        ██║   ██║
     ╚██████╔╝██║  ██║███████╗███████╗╚██████╗   ██║   ███████╗
      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝   ╚═╝   ╚══════╝
</pre>

**Head tracking display switcher for macOS**

<br />

<img src="assets/demo.png" width="500" />

</div>

---

`gazectl` can track your head with either your webcam or supported AirPods motion sensors to detect which monitor you're looking at and automatically switch focus to it. It uses Apple's Vision and Core Motion frameworks plus native macOS APIs to switch monitor focus, with no third-party window manager required.

> macOS only. Requires macOS 14+.

## Permissions

gazectl needs these macOS permissions depending on the source you use:

- **Accessibility** — for moving the cursor and clicking to switch monitor focus
- **Camera** — required for `--source camera`
- **Motion & Fitness** — required for `--source airpods`

Grant the needed permissions in **System Settings → Privacy & Security**. macOS prompts the first time a source is used.

## Install

```bash
npx gazectl@latest
```

Or install globally:

```bash
npm i -g gazectl
```

## Usage

```bash
# First run — calibrates automatically
gazectl

# Use AirPods motion instead of the camera
gazectl --source airpods

# Force recalibration
gazectl --calibrate

# With verbose logging
gazectl --verbose
```

On first run, gazectl asks you to look at each monitor and press Enter. It samples your head pose for 2 seconds per monitor, then saves calibration to `~/.local/share/gazectl/calibration.json`.

AirPods mode uses a session-relative baseline. After the initial per-monitor calibration, later launches ask for one short anchor baseline on the saved anchor monitor before live tracking begins. See [docs/airpods-motion.md](docs/airpods-motion.md) for the model.

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--calibrate` | off | Force recalibration |
| `--calibration-file` | `~/.local/share/gazectl/calibration.json` | Custom calibration path |
| `--source` | `camera` | Tracking source: `camera` or `airpods` |
| `--camera` | 0 | Camera index, only valid with `--source camera` |
| `--verbose` | off | Print live pose continuously |
| `--debug` | off | Print transition decision points |

## How it works

1. **Calibrate** — record a per-monitor pose map for the selected source
2. **Track** — Apple Vision or AirPods motion reports your live head pose in real time
3. **Switch** — gazectl matches the live pose against the calibrated monitor poses and clicks into the best match

## Build from source

```bash
swift build -c release
cp .build/release/gazectl /usr/local/bin/gazectl
```

# Star History

<p align="center">
  <a target="_blank" href="https://star-history.com/#jnsahaj/gazectl&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jnsahaj/gazectl&type=Date&theme=dark">
      <img alt="GitHub Star History for jnsahaj/gazectl" src="https://api.star-history.com/svg?repos=jnsahaj/gazectl&type=Date">
    </picture>
  </a>
</p>
