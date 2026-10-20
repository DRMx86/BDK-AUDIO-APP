# Original Kotlin application

The original Android/Kotlin Multiplatform application is preserved in
[`kotlin/`](kotlin/). The active Flutter application now lives at the repository
root. The original source and its earlier Git history have not been discarded.

- [Original README and screenshots](kotlin/README.md)
- [Original Android update guide](kotlin/ANDROID_OTA_GUIDE.md)

To work on the original application, open `legacy/kotlin/` as the Gradle project
root in Android Studio, or run its wrapper from that directory:

```sh
cd legacy/kotlin
sh ./gradlew :app:assembleDebug
```

Use `gradlew.bat :app:assembleDebug` on Windows. This is archival build guidance;
the legacy app has not been rebuilt as part of the Flutter publication.

The original README describes the older app. Its feature list and screenshots
should not be read as the current Flutter platform-validation status.
