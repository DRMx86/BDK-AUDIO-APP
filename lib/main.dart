import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'connection/speaker_session.dart';
import 'connection/speaker_setup_controller.dart';
import 'platform/audio_connection_adapter.dart';
import 'connection/universal_ble_transport.dart';
import 'persistence/profile_store.dart';
import 'persistence/saved_speaker_store.dart';
import 'features/sounds/sound_draft_store.dart';
import 'features/sounds/sound_import_controller.dart';
import 'features/startup/bdk_startup_app.dart';
import 'features/light/light_diffusion.dart';
import 'features/light/gpu_light_fields.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(BdkStartupApp(loadApplication: _loadApplication));
}

Future<Widget> _loadApplication() async {
  const previewOnly = bool.fromEnvironment('BDK_PREVIEW_ONLY');
  final preferences = SharedPreferencesAsync();
  final store = ProfileStore(preferences);
  ProfileData data;
  String? profileWarning;
  try {
    data = await store.load();
  } catch (_) {
    data = const ProfileData();
    profileWarning =
        'Saved presets could not be read. The existing data has been kept.';
  }
  FileSoundDraftStore? soundStore;
  Map<int, PreparedSound> sounds = const {};
  String? soundWarning;
  try {
    final support = await getApplicationSupportDirectory();
    soundStore = FileSoundDraftStore(
      File('${support.path}${Platform.pathSeparator}sound_previews_v1.json'),
    );
    sounds = await soundStore.load();
  } catch (_) {
    soundWarning = 'Saved sound previews could not be loaded.';
  }
  final session = SpeakerSession(UniversalBleTransport());
  final setup = SpeakerSetupController(
    session,
    const SystemAudioConnectionAdapter(),
    savedSpeakerStore: SharedPreferencesSavedSpeakerStore(preferences),
    autoConnectEnabled: !previewOnly,
    autoDiscoverEnabled: true,
  );
  try {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await Future.wait([
      LedDiffusion.load(),
      GpuLightFieldRenderer.load(),
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {
    // Keep startup usable if a backend cannot prepare the optical program.
  }
  return BdkApp(
    session: session,
    setup: setup,
    store: store,
    initialProfiles: data,
    profileWarning: profileWarning,
    soundDraftStore: soundStore,
    initialSounds: sounds,
    soundDraftWarning: soundWarning,
    previewOnly: previewOnly,
  );
}
