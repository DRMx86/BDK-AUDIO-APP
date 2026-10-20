# Bring presets from the original Android app

The Flutter app accepts Android `BDKAudioPrefs.xml`, a curated Android JSON backup,
or a BDK version1 preset JSON file. Both original key families are supported:
`custom_preset_1_*` and `custom_1_*`, including slots1–3. Percent values use the
original Kotlin integer conversion. Existing presets, favorites and appearance
are preserved. Import previews the curves and lets the user select which to add;
it does not apply an equalizer setting to the speaker.

For the connected development phone, the original application is debuggable.
This read-only helper exports only custom-preset fields, without printing or
saving the other private preferences:

```powershell
python tools/export_android_presets.py --serial 9125299103B7 --output artifacts/android-presets-backup.json
```

Choose a new output filename for each backup; the helper refuses to overwrite an
existing one. It uses Android's normal `run-as` boundary and never roots, installs,
changes settings, stops the original app, or operates on the speaker. A release
app that is not debuggable needs an authorized exported backup instead; this tool
does not bypass Android app isolation.

Open Sound → Saved presets → Import presets in Flutter and choose the backup.
Review the selected names/curves, then import. Exact duplicates are skipped.
Different settings with the same name are added under a distinct display name;
very long colliding names are abbreviated to make room for their numeric suffix,
without splitting Unicode characters. IDs remain stable for repeat imports.

Files are limited to256KiB and the library to128 presets. XML documents with DTDs,
external entity declarations, excessive nesting, duplicate relevant keys or invalid
types are rejected. Invalid/newer existing Flutter storage is preserved rather than
silently replaced after a startup fallback. Save failure does not publish a success.

The current phone's original preferences read successfully but contained **zero
custom-preset fields**. No personal presets were migrated. Native preview testing
used explicitly synthetic sample presets and did not commit them to the library.
