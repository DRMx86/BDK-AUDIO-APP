# Linux preview bundle

Keep the executable, `lib/`, `data/` and `share/` together. Launch `./bdk_audio`
from the extracted bundle. To add it to your desktop's applications menu, run:

```sh
./register-launcher.sh
```

The script registers only the current user's application entry, using absolute
paths to this bundle and its icon. Run it again after moving the whole bundle.
It does not change PATH, install system libraries or require sudo. Paths with
`=` or control characters are refused before an existing entry is touched.
Spaces, quotes, dollar signs, backticks, percent signs and backslashes are passed
as literal path characters; no shell command is constructed by the launcher.

The development preview still needs target-native BLE/audio identity validation,
desktop integration and final distribution review. An isolated guest build and
headless software-rendered smoke check do not establish physical Bluetooth or
bare-metal GPU support.
