import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Complements Flutter's generated package notices with bundled asset and
/// native-source notices. Registration is lazy and does not read assets until
/// a license page requests them.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    const notices = <String, List<String>>{
      'Manrope': [
        'assets/fonts/Manrope-OFL.txt',
        'assets/fonts/Manrope-NOTICE.txt',
      ],
      'Space Grotesk': ['assets/fonts/SpaceGrotesk-OFL.txt'],
      'miniaudio': ['assets/licenses/miniaudio-LICENSE.txt'],
      'Unicode': ['assets/licenses/Unicode-LICENSE.txt'],
      'scrypt': ['assets/licenses/scrypt-LICENSE.txt'],
      'Microsoft C++/WinRT': ['assets/licenses/CppWinRT-LICENSE.txt'],
      'Windows Implementation Library': ['assets/licenses/WIL-LICENSE.txt'],
    };
    for (final notice in notices.entries) {
      final parts = await Future.wait(notice.value.map(rootBundle.loadString));
      yield LicenseEntryWithLineBreaks([notice.key], parts.join('\n\n'));
    }
  });
}
