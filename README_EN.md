# Codex Quota Mac

[中文](README.md)

A lightweight macOS menu bar app for checking your Codex 5-hour and 7-day quota. The app runs as an accessory app, hides the Dock icon, and shows quota information directly in the macOS menu bar.

![Main window](main.png)

![Settings menu](setting.png)

## Features

- Shows Codex remaining quota in the macOS menu bar.
- Supports both 5-hour and 7-day quota windows.
- Can show quota reset times.
- Supports manual refresh.
- Supports configurable auto-refresh intervals.
- Runs locally without any extra backend service.

## Requirements

- macOS 15.1 or later.
- Xcode 16 or later.
- Codex CLI / Codex App installed and signed in.
- `codex app-server --listen stdio://` must be available on your machine.

The app looks for `codex` in this order:

1. `CODEX_CLI_PATH` environment variable.
2. `/Applications/Codex.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. `~/.npm-global/bin/codex`
6. `~/.local/bin/codex`
7. `codex` from the current `PATH`

## Run From Source

1. Clone the repository:

   ```bash
   git clone https://github.com/BaoXiaoShuai/codex-quota-mac.git
   cd codex-quota-mac
   ```

2. Open the project in Xcode:

   ```bash
   open codex-quota-mac.xcodeproj
   ```

3. Select the `codex-quota-mac` scheme.

4. Click Run in Xcode.

5. The app will not appear in the Dock. Look for the `Codex` text in the macOS menu bar.

## Where Is the App Bundle?

After running the project from Xcode, the generated app bundle is usually under DerivedData:

```text
~/Library/Developer/Xcode/DerivedData/codex-quota-mac-*/Build/Products/Debug/codex-quota-mac.app
```

You can also find it from the Xcode menu:

1. Click the top menu `Product`.
2. Choose `Show Build Folder in Finder`.
3. Open `Products/Debug` and find `codex-quota-mac.app`.

Once you find the `.app`, you can copy it to `/Applications` or any other location you prefer. This is a menu bar app, so it will not appear in the Dock after launch. Look for `Codex` in the macOS menu bar.

## Usage

- Left-click the menu bar text to open the quota panel.
- Right-click the menu bar text to open the menu.
- Use the menu to refresh quota, toggle display options, change refresh interval, or quit the app.

Menu bar example:

```text
5h 86% 08:09 | 7d 72% 7/14
```

Meaning:

- `5h`: remaining quota for the 5-hour window.
- `7d`: remaining quota for the 7-day window.
- The trailing time: reset time for that quota window.

## How It Works

The app starts the local Codex app-server and calls this stdio JSON-RPC method:

```text
account/rateLimits/read
```

It then reads `usedPercent`, `resetsAt`, and `windowDurationMins` from the response and calculates the remaining quota shown in the UI.

## Troubleshooting

### The menu bar shows `Codex --`

This usually means the quota request failed. Please check:

- Codex CLI / Codex App is installed.
- You are signed in to Codex.
- `codex` works from your terminal.
- If `codex` is installed in a custom location, set `CODEX_CLI_PATH`.

### I cannot find the app window

This is expected. The app is a menu bar utility. It hides the Dock icon and Cmd+Tab entry. Look for `Codex` in the macOS menu bar.

### Where can I change the refresh interval?

Right-click the menu bar text and choose an interval from the refresh interval submenu: 1, 3, 5, 10, or 30 minutes.

## Notes

This project is a local utility. It does not upload your account information or quota data. It only talks to the local Codex app-server on your machine.
