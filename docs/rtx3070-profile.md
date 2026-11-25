# RTX 3070 / 8 GiB launch profile

This is a conservative starting profile for the NVIDIA RTX 3070 8 GiB, Ryzen 5 2600 and 16 GiB system-RAM class. It is based on switches already documented and used by this repository; it is not a claim that the title is now playable on that hardware.

## Launch

Build the non-diagnostics diag profile:

```powershell
cargo build --profile diag -p victory
```

Then run:

```powershell
.\scripts\play-rtx3070.ps1 -GameExe "C:\path\to\game_scarlett_master.exe"
```

The script selects the Series S console profile by default. In this port, that keeps the title's own upscaler and lowers the rendering workload compared with the Series X profile. It is the recommended first comparison on an 8 GiB card. Use -SeriesX to compare image detail against the heavier Series X path.

The script uses a 512 MiB card-buffer pool instead of the 1 GiB setting in the repository's RTX 4070 test recipe. It enables the repository's documented relay / late-wait / indirect-window recipe, the parallel texture-refresh path (`VICTORY_WIDE_TEXTURES=1`, measured in the project log to reduce streaming dips), and the Flamingo stats overlay. Press **F9** to hide or show the overlay. It saves console output under `%LOCALAPPDATA%\\flamingo\\logs` and restores the process environment after the title exits.

## Fresh start for every test

The RTX 3070 launcher now starts with a fresh title profile by default. Before each run it reads the title ID and data directory from the active game manifest and VIctory config, then moves the existing `saves` and `storage` folders to timestamped sibling backups and creates empty folders. It does not permanently delete the previous state. The backup paths are printed before launch.

Use `-KeepProgress` to skip this reset and continue with the existing save/profile. Shader and pipeline caches are not cleared by the fresh-start option.

## Memory warning for 16 GiB systems

The repository's earlier Flamingo measurements were made on a 32 GiB PC. Its notes report a roughly 15–16 GiB process working set in gameplay and substantially more committed memory than the process's resident working set. On a 16 GiB PC, Windows may page frequently; this can cause severe frame-time spikes even when the GPU is not fully busy.

Before launching, close other memory-heavy applications and check **Task Manager → Performance → Memory → Committed**. Keep a Windows-managed paging file on an SSD and ensure the commit limit is comfortably above the title's demand. The script only warns about low physical RAM; it does not change paging-file or registry settings.

## Optional image experiment

The launcher can also try Flamingo's no-hit ray mode for one comparison:

```powershell
.\scripts\play-rtx3070.ps1 -GameExe "C:\path\to\game_scarlett_master.exe" -ExperimentalNoHitLighting
```

This changes every ray-tracing node test to miss when the structure builder is off. Flamingo's run log reports that it removed some black water artefacts and brightened a face, but reflection fallback streaks remained and an earlier test hung. It is not correct ray-traced lighting; use it only as a short A/B visual experiment, then relaunch without the switch.

## Optional fine-detail experiment

Flamingo's helper-lane quad reads can improve fine texture detail and edges in pixel-shader derivatives. The project log measured about an 18% frame-time cost in the test scene. Compare it only on a close-up and watch the overlay:

```powershell
.\scripts\play-rtx3070.ps1 -GameExe "C:\path\to\game_scarlett_master.exe" -ExperimentalQuadHelpers
```

This switch and the no-hit ray experiment can be combined, but test them one at a time so you can tell which changed the image or frame time. The launcher writes the console output to `%LOCALAPPDATA%\flamingo\logs\rtx3070-*.log`.

## What this profile deliberately does not enable

- The ray-tracing structure builder remains off. The source documents it as unfinished in this port; a partial or incorrect builder can corrupt title memory or crash the game.
- The ambient-light and shadow-mask stand-ins remain off. They replace real shader outputs with constants and are not a substitute for the game's lighting.
- No Windows GPU timeout / TDR registry changes are made.

## Known trade-offs and limits

- Series S mode reduces the renderer workload, but its final image is upscaled. Series X may look sharper, but costs more GPU time and VRAM.
- The repository's own documented gameplay measurements were on an RTX 4070 12 GiB, not an RTX 3070 8 GiB. There is no verified FPS promise for an RTX 3070 / Ryzen 5 2600 / 16 GiB system.
- This profile is a launch baseline, not a fix for missing ray-traced lighting, shader gaps, streaming stalls or CPU bottlenecks. The overlay's CPU, GPU, copy-back, VRAM and RAM values should be used to distinguish those limits.
