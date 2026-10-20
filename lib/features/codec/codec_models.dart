enum CodecAccess {
  initializing,
  ready,
  permissionRequired,
  associationRequired,
  bluetoothOff,
  noAudioDevice,
  apiUnavailable,
  unsupportedPlatform,
  error,
}

/// AOSP LDAC codecSpecific1 quality preference, never measured transport bitrate.
/// Android 16 BluetoothQualityDialogPreferenceController writes 1000 + index.
enum LdacQuality {
  high(1000, 'High quality'),
  balanced(1001, 'Balanced'),
  connection(1002, 'Connection priority'),
  adaptive(1003, 'Adaptive');

  const LdacQuality(this.wireValue, this.label);
  final int wireValue;
  final String label;

  /// Source-defined LDAC target for the Bluetooth sample-rate cadence.
  /// Adaptive and unknown rate masks have no fixed nominal target.
  int? nominalTargetKbps(int sampleRateMask) {
    final targets = switch (sampleRateMask) {
      1 || 4 => const [909, 606, 303],
      2 || 8 => const [990, 660, 330],
      _ => null,
    };
    return targets == null || this == adaptive ? null : targets[index];
  }

  static LdacQuality? fromWire(int value) {
    for (final quality in values) {
      if (quality.wireValue == value) return quality;
    }
    return null;
  }
}

/// Savitech V5 quality commands, only after the active vendor fields match.
/// These are requested nominal targets; peer limits can clamp a preference.
enum LhdcV5Quality {
  kbps64(64),
  kbps160(160),
  kbps192(192),
  kbps256(256),
  kbps320(320),
  kbps400(400),
  kbps500(500),
  kbps900(900),
  kbps1000(1000),
  adaptive(null);

  const LhdcV5Quality(this.nominalTargetKbps);
  final int? nominalTargetKbps;
  int get wireValue => 0x8000 | index;
  String get label =>
      nominalTargetKbps == null ? 'Adaptive' : '$nominalTargetKbps kbps';

  bool allowedAt(int rate, {required bool lossless}) {
    if (!const [1, 2, 8, 32].contains(rate)) return false;
    if (this == adaptive) return true;
    if (lossless) return false;
    return const [8, 32].contains(rate) ? index >= 3 : index <= 7;
  }

  static LhdcV5Quality? fromWire(int value) {
    if (value & 0xc000 != 0x8000) return null;
    final code = value & 0xff;
    return code < values.length ? values[code] : null;
  }
}

class CodecAudioDevice {
  const CodecAudioDevice({
    required this.id,
    required this.name,
    this.associated = false,
  });
  final String id, name;
  final bool associated;
}

class CodecConfiguration {
  const CodecConfiguration({
    required this.codecType,
    required this.codecName,
    required this.sampleRateMask,
    required this.bitsMask,
    required this.channelMask,
    this.cs1 = 0,
    this.cs2 = 0,
    this.cs3 = 0,
    this.cs4 = 0,
  });
  final int codecType,
      sampleRateMask,
      bitsMask,
      channelMask,
      cs1,
      cs2,
      cs3,
      cs4;
  final String codecName;
  LdacQuality? get ldacQuality =>
      codecType == 4 ? LdacQuality.fromWire(cs1) : null;

  /// Fixed source-defined target, not actual encoded/transmitted bitrate.
  /// AOSP A2DP_VendorGetBitRateLdac uses the 44.1/88.2 vs 48/96-kHz cadence.
  int? get ldacNominalTargetKbps =>
      ldacQuality?.nominalTargetKbps(sampleRateMask);

  LhdcV5Quality? get lhdcV5Quality =>
      codecType > 6 &&
          codecName.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '') ==
              'LHDCV5' &&
          const [1, 2, 8, 32].contains(sampleRateMask) &&
          cs3 & 0xff000000 == 0x5c000000
      ? LhdcV5Quality.fromWire(cs1)
      : null;
  bool get lhdcV5Lossless => cs3 & 0x180 != 0;
  int? get lhdcV5NominalTargetKbps {
    final quality = lhdcV5Quality;
    return quality?.allowedAt(sampleRateMask, lossless: lhdcV5Lossless) == true
        ? quality!.nominalTargetKbps
        : null;
  }

  int? get nominalTargetKbps =>
      ldacNominalTargetKbps ?? lhdcV5NominalTargetKbps;

  factory CodecConfiguration.fromMap(Object? value) {
    final map = _objectMap(value);
    final type = _integer(map, 'codecType');
    if (type >= 1000000) {
      throw const FormatException('Invalid Android codec type');
    }
    return CodecConfiguration(
      codecType: type,
      codecName: _string(map, 'codecName'),
      sampleRateMask: _integer(map, 'sampleRateMask'),
      bitsMask: _integer(map, 'bitsMask'),
      channelMask: _integer(map, 'channelMask'),
      cs1: _integer(map, 'cs1', signed: true),
      cs2: _integer(map, 'cs2', signed: true),
      cs3: _integer(map, 'cs3', signed: true),
      cs4: _integer(map, 'cs4', signed: true),
    );
  }
  // Android BluetoothCodecConfig bit masks, never rates supplied by a text field.
  // https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/framework/java/android/bluetooth/BluetoothCodecConfig.java
  static const rates = {
    1: '44.1 kHz',
    2: '48 kHz',
    4: '88.2 kHz',
    8: '96 kHz',
    16: '176.4 kHz',
    32: '192 kHz',
  };
  static const depths = {1: '16-bit', 2: '24-bit', 4: '32-bit'};
  static const channels = {1: 'Mono', 2: 'Stereo'};
  List<int> get sampleRates => rates.keys
      .where((bit) => sampleRateMask & bit != 0)
      .toList(growable: false);
  List<int> get bitDepths =>
      depths.keys.where((bit) => bitsMask & bit != 0).toList(growable: false);
  List<int> get channelModes => channels.keys
      .where((bit) => channelMask & bit != 0)
      .toList(growable: false);
  static String sampleRateLabel(int mask) => rates[mask] ?? 'Not reported';
  static String bitDepthLabel(int mask) => depths[mask] ?? 'Not reported';
  static String channelLabel(int mask) => channels[mask] ?? 'Not reported';
  Map<String, Object> toMap() => {
    'codecType': codecType,
    'codecName': codecName,
    'sampleRateMask': sampleRateMask,
    'bitsMask': bitsMask,
    'channelMask': channelMask,
    'cs1': cs1,
    'cs2': cs2,
    'cs3': cs3,
    'cs4': cs4,
  };
}

class CodecPreference {
  const CodecPreference({
    required this.codecType,
    required this.sampleRateMask,
    required this.bitsMask,
    required this.channelMask,
    this.ldacQuality,
    this.lhdcV5Quality,
  });
  final int codecType, sampleRateMask, bitsMask, channelMask;
  final LdacQuality? ldacQuality;
  final LhdcV5Quality? lhdcV5Quality;
  CodecPreference withLdacQuality(LdacQuality? quality) => CodecPreference(
    codecType: codecType,
    sampleRateMask: sampleRateMask,
    bitsMask: bitsMask,
    channelMask: channelMask,
    ldacQuality: quality,
    lhdcV5Quality: lhdcV5Quality,
  );
  CodecPreference withLhdcV5Quality(LhdcV5Quality? quality) => CodecPreference(
    codecType: codecType,
    sampleRateMask: sampleRateMask,
    bitsMask: bitsMask,
    channelMask: channelMask,
    ldacQuality: ldacQuality,
    lhdcV5Quality: quality,
  );
  bool matches(CodecConfiguration value) =>
      codecType == value.codecType &&
      sampleRateMask == value.sampleRateMask &&
      bitsMask == value.bitsMask &&
      channelMask == value.channelMask &&
      (ldacQuality == null || ldacQuality == value.ldacQuality) &&
      (lhdcV5Quality == null || lhdcV5Quality == value.lhdcV5Quality);
  @override
  bool operator ==(Object other) =>
      other is CodecPreference &&
      codecType == other.codecType &&
      sampleRateMask == other.sampleRateMask &&
      bitsMask == other.bitsMask &&
      channelMask == other.channelMask &&
      ldacQuality == other.ldacQuality &&
      lhdcV5Quality == other.lhdcV5Quality;
  @override
  int get hashCode => Object.hash(
    codecType,
    sampleRateMask,
    bitsMask,
    channelMask,
    ldacQuality,
    lhdcV5Quality,
  );
}

class CodecSnapshot {
  CodecSnapshot({
    required this.access,
    List<CodecAudioDevice> devices = const [],
    this.selectedDeviceId,
    this.active,
    List<CodecConfiguration> capabilities = const [],
    bool canApply = false,
    this.source = 'none',
    this.observedAtMs = 0,
    this.reason,
  }) : devices = List.unmodifiable(devices),
       capabilities = List.unmodifiable(capabilities),
       _writable = canApply;
  final CodecAccess access;
  final List<CodecAudioDevice> devices;
  final String? selectedDeviceId, reason;
  final CodecConfiguration? active;
  final List<CodecConfiguration> capabilities;
  final String source;
  final int observedAtMs;
  final bool _writable;
  factory CodecSnapshot.fromMap(Object? value) {
    final map = _objectMap(value);
    final states = CodecAccess.values.where(
      (state) => state.name == map['state'],
    );
    if (states.isEmpty) {
      throw const FormatException('Unknown codec access state');
    }
    if (map['devices'] is! List ||
        map['capabilities'] is! List ||
        map['canApply'] is! bool) {
      throw const FormatException('Malformed codec snapshot');
    }
    final devices = <CodecAudioDevice>[];
    final identities = <String>{};
    for (final raw in map['devices']! as List) {
      final device = _objectMap(raw);
      final id = _string(device, 'id');
      if (!identities.add(id.toLowerCase()) || device['associated'] is! bool) {
        throw const FormatException('Ambiguous audio device');
      }
      devices.add(
        CodecAudioDevice(
          id: id,
          name: _string(device, 'name'),
          associated: device['associated']! as bool,
        ),
      );
    }
    final selected = map['selectedDeviceId'];
    if (selected != null &&
        (selected is! String || !identities.contains(selected.toLowerCase()))) {
      throw const FormatException('Selected audio identity is absent');
    }
    final active = map['active'] == null
        ? null
        : CodecConfiguration.fromMap(map['active']);
    final source = _string(map, 'source');
    if (!const ['none', 'direct', 'broadcast'].contains(source)) {
      throw const FormatException('Unknown codec observation source');
    }
    final observedAt = _integer(map, 'observedAtMs', timestamp: true);
    if (states.first == CodecAccess.ready &&
        (selected == null ||
            active == null ||
            source == 'none' ||
            observedAt == 0)) {
      throw const FormatException('Incomplete current codec observation');
    }
    if (map['reason'] != null && map['reason'] is! String) {
      throw const FormatException('Invalid codec reason');
    }
    return CodecSnapshot(
      access: states.first,
      devices: devices,
      selectedDeviceId: selected as String?,
      active: active,
      capabilities: (map['capabilities']! as List)
          .map(CodecConfiguration.fromMap)
          .toList(),
      canApply: map['canApply']! as bool,
      source: source,
      observedAtMs: observedAt,
      reason: map['reason'] as String?,
    );
  }
  bool get canApply =>
      _writable &&
      access == CodecAccess.ready &&
      active != null &&
      selectedDeviceId != null &&
      preferences.isNotEmpty;
  List<CodecPreference> get preferences {
    final values = <CodecPreference>{};
    for (final cap in capabilities) {
      for (final rate in cap.sampleRates) {
        for (final bits in cap.bitDepths) {
          for (final channel in cap.channelModes) {
            values.add(
              CodecPreference(
                codecType: cap.codecType,
                sampleRateMask: rate,
                bitsMask: bits,
                channelMask: channel,
              ),
            );
          }
        }
      }
    }
    return List.unmodifiable(values);
  }

  List<LdacQuality> get ldacQualities {
    final current = active;
    if (current == null ||
        current.codecType != 4 ||
        (current.cs1 != 0 && current.ldacQuality == null) ||
        !const [1, 2, 4, 8].contains(current.sampleRateMask) ||
        !preferences.any((p) => p.matches(current))) {
      return const [];
    }
    // AOSP exposes all four LDAC settings; there is no per-quality bitmask.
    // Zero is the source-defined device default, whose effective quality is
    // unknown. It still permits choosing one of these explicit known codes.
    return LdacQuality.values;
  }

  List<LhdcV5Quality> get lhdcV5Qualities =>
      lhdcV5QualitiesForRate(active?.sampleRateMask ?? 0);
  List<LhdcV5Quality> lhdcV5QualitiesForRate(int rate) {
    final current = active;
    if (current == null ||
        current.lhdcV5Quality == null ||
        !preferences.any((p) => p.matches(current))) {
      return const [];
    }
    return LhdcV5Quality.values
        .where(
          (quality) =>
              quality.allowedAt(rate, lossless: current.lhdcV5Lossless),
        )
        .toList(growable: false);
  }

  bool supports(CodecPreference value) =>
      !(value.ldacQuality != null && value.lhdcV5Quality != null) &&
      preferences.contains(
        value.withLdacQuality(null).withLhdcV5Quality(null),
      ) &&
      (value.ldacQuality == null ||
          value.codecType == 4 &&
              const [1, 2, 4, 8].contains(value.sampleRateMask) &&
              ldacQualities.contains(value.ldacQuality)) &&
      (value.lhdcV5Quality == null ||
          value.codecType == active?.codecType &&
              lhdcV5QualitiesForRate(
                value.sampleRateMask,
              ).contains(value.lhdcV5Quality)) &&
      (value.codecType != active?.codecType ||
          active?.lhdcV5Quality == null ||
          lhdcV5QualitiesForRate(
            value.sampleRateMask,
          ).contains(value.lhdcV5Quality ?? active!.lhdcV5Quality));
  bool isFresh(DateTime now) {
    final age = now.millisecondsSinceEpoch - observedAtMs;
    return access == CodecAccess.ready &&
        observedAtMs > 0 &&
        age >= 0 &&
        age <= 5000;
  }

  String codecName(int type) {
    if (active?.codecType == type) return active!.codecName;
    for (final cap in capabilities) {
      if (cap.codecType == type) return cap.codecName;
    }
    return const {
          0: 'SBC',
          1: 'AAC',
          2: 'aptX',
          3: 'aptX HD',
          4: 'LDAC',
          5: 'LC3',
          6: 'Opus',
        }[type] ??
        'Codec $type';
  }

  CodecConfiguration configurationFor(CodecPreference value) {
    if ((value.ldacQuality != null ||
            value.lhdcV5Quality != null ||
            value.codecType == active?.codecType &&
                active?.lhdcV5Quality != null) &&
        !supports(value)) {
      throw ArgumentError(
        'This connection does not expose that codec quality.',
      );
    }
    final same = active?.codecType == value.codecType ? active : null;
    return CodecConfiguration(
      codecType: value.codecType,
      codecName: codecName(value.codecType),
      sampleRateMask: value.sampleRateMask,
      bitsMask: value.bitsMask,
      channelMask: value.channelMask,
      cs1: value.lhdcV5Quality != null
          ? (same!.cs1 & ~0xff) | value.lhdcV5Quality!.index
          : value.ldacQuality?.wireValue ?? same?.cs1 ?? 0,
      cs2: same?.cs2 ?? 0,
      cs3: same?.cs3 ?? 0,
      cs4: same?.cs4 ?? 0,
    );
  }
}

Map<Object?, Object?> _objectMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected codec object');
  return Map<Object?, Object?>.from(value);
}

String _string(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key');
  }
  return value.trim();
}

int _integer(
  Map<Object?, Object?> map,
  String key, {
  bool signed = false,
  bool timestamp = false,
}) {
  final value = map[key];
  if (value is! int ||
      (!signed && value < 0) ||
      (!signed && !timestamp && value > 0x7fffffff)) {
    throw FormatException('Invalid integer $key');
  }
  return value;
}
