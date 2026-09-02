# Desktop environment

<!-- toc -->

- [Desktop environment](#desktop-environment)
  - [Compositor (labwc)](#compositor-labwc)
  - [Keybindings](#keybindings)
  - [Right-click menu](#right-click-menu)
  - [Panel (wayle)](#panel-wayle)
    - [Layout (DSI-1 panel)](#layout-dsi-1-panel)
    - [Custom modules](#custom-modules)
    - [Wallpaper](#wallpaper)
    - [Weather](#weather)
  - [App launcher (Vicinae)](#app-launcher-vicinae)
    - [Favorites](#favorites)
    - [Power aliases](#power-aliases)
  - [On-screen keyboard (wvkbd)](#on-screen-keyboard-wvkbd)
    - [How it works](#how-it-works)
    - [Manual toggle](#manual-toggle)
  - [Screen lock (swayidle + swaylock)](#screen-lock-swayidle--swaylock)
  - [Auto-rotation (rot8)](#auto-rotation-rot8)
  - [Output management (kanshi)](#output-management-kanshi)
  - [Power management](#power-management)
    - [Power button](#power-button)
    - [fydetab-perf](#fydetab-perf)
    - [Auto power profiles](#auto-power-profiles)
  - [Theming](#theming)

<!-- /toc -->

## Compositor (labwc)

The default compositor is [labwc](https://labwc.github.io/) — a wlroots-based stacking compositor. If you have used Openbox on X11, labwc will be familiar: it uses the same `rc.xml` and `menu.xml` config format, but runs natively on Wayland.

labwc starts automatically via greetd. The greeter (ReGreet) itself runs inside a separate labwc session so that touch/stylus mapping and output transforms are applied right from the moment you see the login screen.

Touch and stylus input are mapped to the panel output (`DSI-1`) in `rc.xml`, which means wlroots automatically applies the correct rotation transform to input devices — touch and stylus follow the screen in every orientation without any hardcoded / static calibration matrix.

## Keybindings

Custom keybindings are defined in the labwc `rc.xml`. All default labwc keybindings are also active (e.g. `A-Tab` for window switching, `Super+A` to toggle full screen).

| Key                     | Action                           |
| ----------------------- | -------------------------------- |
| `Super+Return`          | Open terminal (Alacritty)        |
| `Super+D`               | Toggle app launcher (Vicinae)    |
| `Print`                 | Screenshot region (grim + slurp) |
| `XF86AudioRaiseVolume`  | Volume up 5%                     |
| `XF86AudioLowerVolume`  | Volume down 5%                   |
| `XF86AudioMute`         | Toggle mute                      |
| `XF86MonBrightnessUp`   | Brightness up 5%                 |
| `XF86MonBrightnessDown` | Brightness down 5%               |

Screenshots are saved to `~/Pictures/Screenshot-<timestamp>.png`.

## Right-click menu

Right-clicking / tapping anywhere on the wallpaper opens the root menu:

| Item           | Launches                     |
| -------------- | ---------------------------- |
| Launcher       | Vicinae toggle               |
| Browser        | LibreWolf                    |
| Files          | Thunar                       |
| Terminal       | Alacritty                    |
| Documents      | Evince                       |
| Images         | Gwenview                     |
| Video          | Haruna                       |
| System Monitor | btop (in Alacritty)          |
| Network        | nmtui (in Alacritty)         |
| Screenshot     | Region select (grim + slurp) |
| Log Out        | Exit labwc session           |
| Power Off      | `systemctl poweroff`         |

## Panel (wayle)

[wayle](https://github.com/wayle-rs/wayle) is the status bar at the top of the screen.

### Layout (DSI-1 panel)

| Section    | Modules                                                                    |
| ---------- | -------------------------------------------------------------------------- |
| **Left**   | Dashboard, clock, auto-rotate toggle, tablet-mode toggle, system tray      |
| **Center** | CPU, RAM, storage usage, weather                                           |
| **Right**  | Volume, microphone, brightness, network, bluetooth, battery, notifications |

On any other monitor the bar is hidden.

### Custom modules

- **Auto-rotate** — shows On/Off, click to toggle the rot8 auto-rotation service.
- **Tablet mode** — shows On/Off, click to toggle the on-screen keyboard irrespective of the keyboard attach/detach state.
- **Storage** — shows root disk usage.

### Wallpaper

The bar includes a wallpaper engine that fills `DSI-1` with the default wallpaper - the wallpaper file is at `/run/current-system/sw/share/backgrounds/fydetab-duo/wallpaper.jpg`.

### Weather

Weather requires latitude/longitude to be set. Add to your configuration:

```nix
fydetabShell.wayle.weather.latitude = "51.5";
fydetabShell.wayle.weather.longitude = "-0.1";
```

## App launcher (Vicinae)

Vicinae is the app launcher, opened with `Super+D`. It starts automatically as a systemd user service.

### Favorites

The launcher sidebar shows these by default:

- `system:run` (aliased to `cmd`) — run a command.
- `files:search` — file search.
- `clipboard:history` — clipboard history.
- `power:power-off` (aliased to `sd`).

### Power aliases

| Alias | Action      |
| ----- | ----------- |
| `sd`  | Power off   |
| `rb`  | Reboot      |
| `lc`  | Lock screen |

Type any of these in the launcher to trigger the action straight away.

## On-screen keyboard (wvkbd)

The on-screen keyboard uses [wvkbd-mobintl](https://github.com/nicke/wvkbd) and is managed by the tablet-mode module (`hardware.fydetabduo.tabletMode.enable`).

### How it works

- When the pogo-pin USB keyboard (Apple, vendor `05ac`) is **detached**, the OSK appears automatically (when in an input box).
- When the keyboard is **attached**, the OSK hides.
- The OSK auto-shows when a text field gains focus via the `zwp_text_input_v3` Wayland protocol.
- In portrait mode it uses the `full` layout; in landscape it switches to `landscape`.

### Manual toggle

- **Swipe from the bottom of the screen** (lisgd gesture) — toggles OSK visibility (ONLY in greeter).
- **Tablet-mode button** in the wayle bar — toggles OSK independently of keyboard state.

## Screen lock (swayidle + swaylock)

Screen locking is handled by swayidle with swaylock-effects:

| Timeout           | Action                              |
| ----------------- | ----------------------------------- |
| 10 minutes (600s) | Lock screen with blurred screenshot |
| 15 minutes (900s) | Screen off (`wlopm --off '*'`)      |
| On resume         | Screen on (`wlopm --on '*'`)        |
| Before sleep      | Lock screen                         |

The lock screen uses a blurred screenshot of your current screen as the background.

## Auto-rotation (rot8)

When `hardware.fydetabduo.sensors.autoRotate` is enabled, [rot8](https://github.com/nicke/nicke.github.io) runs as a user service. It reads the lis2dw12 accelerometer via iio-sensor-proxy and rotates the DSI-1 output via `wlr-randr` (wlr-output-management protocol).

This works under any wlroots compositor. Touch and stylus automatically follow the rotation because labwc maps them to the panel output.

Auto-rotation can be toggled from the wayle bar's auto-rotate button. You can also use `hardware.fydetabduo.landscape.enable` alongside auto-rotation — kanshi applies the landscape transform at startup, and rot8 overrides it automatically when the device is physically rotated.

## Output management (kanshi)

[kanshi](https://github.com/emersion/kanshi) manages display output transforms. By default it applies no transform to DSI-1 (portrait mode).

To use landscape mode as the default, enable:

```nix
hardware.fydetabduo.landscape.enable = true;
```

This applies a 270-degree transform to DSI-1 via kanshi at startup. Touch and stylus mapping follows automatically.

## Power management

### Power button

- **Short press** — suspend (sleep)
- **Long press** — power off

This differs from the NixOS default (which powers off on short press). The tablet firmware expects suspend on short press.

### fydetab-perf

The `fydetab-perf` script toggles CPU and GPU governors directly:

```sh
fydetab-perf on      # performance governor on all CPUs + GPU
fydetab-perf off     # back to schedutil / simple_ondemand
fydetab-perf status  # prints "on" or "off"
```

A reboot restores default governors. The wayle bar does not currently have a toggle for this, but the script is passwordless using sudo for the `wheel` group.

### Auto power profiles

When `hardware.fydetabduo.shell.power.autoProfile.enable` is true, power profiles switch automatically based on battery percentage:

| Condition                                   | Profile     |
| ------------------------------------------- | ----------- |
| Plugged in (if `forcePerformanceOnAC`)      | performance |
| Battery above `highThreshold` (default 50%) | performance |
| Battery between low and high                | balanced    |
| Battery below `lowThreshold` (default 20%)  | power-saver |

Polling interval defaults to 60 seconds.
