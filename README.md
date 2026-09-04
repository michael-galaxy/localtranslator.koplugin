# Local Translator

A KOReader plugin that translates selected text by sending it to another Android app via Intent. The target app (e.g. [Translator by DavidVentura](https://github.com/DavidVentura/offline-translator)) shows a floating popup, so you never leave KOReader.

## Features

- **Floating popup translation** — uses Android's `ACTION_PROCESS_TEXT` intent, the target app overlays on top of KOReader
- **Offline capable** — works with any offline translator app; no network required
- **Customizable target app** — set any Android package name; presets for popular translator apps
- **Two intent modes** — `PROCESS_TEXT` (floating popup) or `ACTION_SEND` (full app)
- **Clipboard test** — quickly test the configuration with clipboard text
- **Debug logging** — logs to `localtranslator.log` in the plugin directory

## Installation

1. Download the latest `localtranslator.koplugin.zip` from Releases
2. Unzip `localtranslator.koplugin.zip`
3. Copy the `localtranslator.koplugin` folder to KOReader's `plugins/` directory
   - Android: `/sdcard/koreader/plugins/`
4. Restart KOReader

## Usage

1. Open a document in KOReader
2. Long-press and select the text you want to translate
3. Tap **Local Translation** in the highlight popup
4. The configured translator app opens with the selected text

## Configuration

Go to **Search → Settings → Local Translator**:

| Option | Description |
|--------|-------------|
| **Target app** | Set the Android package name of your translator app |
| **Choose from presets** | Select from a list of popular translator apps |
| **Intent action** | `PROCESS_TEXT` (floating popup) or `ACTION_SEND` (full app) |
| **Test with clipboard** | Send current clipboard text to the target app |

### Default settings

- **Target app:** `dev.davidv.translator` ([Translator by DavidVentura](https://github.com/DavidVentura/offline-translator))
- **Intent action:** `text` (`PROCESS_TEXT` — floating popup)

### Preset apps

| App | Package | Action |
|-----|---------|--------|
| Translator (DavidVentura) | `dev.davidv.translator` | PROCESS_TEXT |
| Microsoft Translator | `com.microsoft.translator` | ACTION_SEND |
| Google Translate | `com.google.android.apps.translate` | ACTION_SEND |
| DeepL Translate | `com.deepl.translate` | ACTION_SEND |
| Naver Papago | `com.nhn.android.naversdic` | ACTION_SEND |
| DictTango | `cn.jimex.dict` | ACTION_SEND |

You can also set any custom package name via **Target app**.

## How it works

The plugin calls KOReader's built-in `android.dictLookup(text, package, action)` JNI function, which constructs an Android Intent and starts the target activity:

- **`text` action** → `ACTION_PROCESS_TEXT` with `EXTRA_PROCESS_TEXT` — shows a floating dialog (requires the target app to have a `PROCESS_TEXT` activity)
- **`send` action** → `ACTION_SEND` with `EXTRA_TEXT` — opens the target app's main activity

This is the same mechanism KOReader uses for its built-in external dictionary lookup (see `frontend/device/android/device.lua` → `doExternalDictLookup`).

## Troubleshooting

### Nothing happens when I tap "Local Translation"

1. Check the log file at `plugins/localtranslator.koplugin/localtranslator.log`
2. Verify the target app is installed: `adb shell pm list packages | grep translator`
3. Try switching the intent action from `PROCESS_TEXT` to `ACTION_SEND` (some apps only support `ACTION_SEND`)
4. Use **Test with clipboard** to verify the configuration without selecting text

### The app opens but doesn't show a floating popup

The target app may not support `ACTION_PROCESS_TEXT`. Switch to `ACTION_SEND` in settings, or use an app that supports floating translation (e.g. Translator by DavidVentura).

### Log file

The plugin logs all calls to `localtranslator.log` in the plugin directory. The log is cleared each time a new document is opened. It records:
- Platform and API availability checks
- Target package and action
- Text preview (first 80 characters)
- Call result or error

## Development

### Project structure

```
localtranslator.koplugin/
├── _meta.lua          # Plugin metadata (name, version, description)
├── main.lua           # Core plugin logic
├── README.md          # This file
└── LICENSE            # AGPL v3
```

### Key implementation notes

- **Parameter order:** `android.dictLookup(text, package, action)` — this matches KOReader's internal `doExternalDictLookup` in `frontend/device/android/device.lua`.
- **Highlight dialog integration:** uses `self.ui.highlight:addToHighlightDialog(id, callback)` to add a menu item to the long-press text selection popup.
- **Settings persistence:** uses `G_reader_settings:readSetting/saveSetting` with the `localtranslator_` prefix.
- **Android-only:** the plugin loads the `android` module only on Android devices; on other platforms it shows an informational message.

### Building

No build step required. The plugin is pure Lua. To package for distribution:

```bash
zip -r localtranslator.koplugin.zip localtranslator.koplugin/
```

## License

[GNU Affero General Public License v3.0](LICENSE) — same as KOReader.
