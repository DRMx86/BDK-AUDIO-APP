import 'speaker_state.dart';

/// Remembers light power settings for one speaker during an app session.
class LightPowerMemory {
  int _brightness = 70, _effect = 0;

  void remember(LedSettings settings) {
    if (settings.brightness > 0) _brightness = settings.brightness;
    if (!settings.isOff) _effect = settings.effect;
  }

  LedSettings restore(LedSettings settings) => settings.copyWith(
    effect: settings.isOff ? _effect : settings.effect,
    brightness: _brightness,
  );
}
