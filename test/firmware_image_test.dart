import 'dart:typed_data';
import 'dart:convert';
import 'package:bdk_audio/features/updates/firmware_image.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ota_transfer_fixture.dart';

void main() {
  test(
    'multiple segments contribute to checksum and preserve first application descriptor',
    () {
      final image = FirmwareImage.parse(otaMultiSegmentImageBytes());
      expect(image.segmentCount, 2);
      expect(image.version, '2.4.0');
      expect(
        () => FirmwareImage.parse(otaMultiSegmentImageBytes()..[300] ^= 1),
        throwsA(
          isA<FirmwareImageException>().having(
            (error) => error.kind,
            'kind',
            FirmwareImageError.checksum,
          ),
        ),
      );
    },
  );
  test(
    'footer alignment hash flag and segment alignment are checked before acceptance',
    () {
      final nonzeroPad = otaImageBytes(hash: false)..[290] = 1;
      final badHashFlag = otaImageBytes()..[23] = 2;
      final oddSegment = otaImageBytes()..[28] = 255;
      final invalidEntry = otaImageBytes(hash: false)..[7] = 0;
      for (final bytes in [nonzeroPad, badHashFlag, oddSegment, invalidEntry]) {
        expect(
          () => FirmwareImage.parse(bytes),
          throwsA(isA<FirmwareImageException>()),
        );
      }
    },
  );
  test(
    'invalid descriptor text with otherwise valid checksums is rejected',
    () {
      expect(
        () => FirmwareImage.parse(otaImageBytes(version: 'bad\nversion')),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () => FirmwareImage.parse(otaImageBytes(version: '')),
        throwsA(isA<FirmwareImageException>()),
      );
    },
  );
  test(
    'raw encrypted and decrypted size bounds never fall back to a different format',
    () {
      final container = base64Decode(otaEncryptedFixtureBase64);
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      expect(
        () => FirmwareImage.parse(container),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () => FirmwareImage.parse(
          otaImageBytes(),
          encrypted: true,
          legacyAesKey: key,
        ),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () => FirmwareImage.parse(
          container,
          encrypted: true,
          legacyAesKey: key,
          maxBytes: 335,
        ),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () => FirmwareImage.parse(
          otaImageBytes(),
          maxBytes: FirmwareImage.maximumBytes + 1,
        ),
        throwsA(isA<FirmwareImageException>()),
      );
    },
  );
  test(
    'legacy AES256 CBC IV-prefix PKCS7 fixture matches independently encrypted bytes',
    () {
      final container = base64Decode(otaEncryptedFixtureBase64);
      final image = FirmwareImage.parse(
        container,
        encrypted: true,
        legacyAesKey: Uint8List.fromList(List.generate(32, (i) => i)),
      );
      expect(image.bytes, otaImageBytes());
      expect(image.sourceFormat, FirmwareSourceFormat.legacyAesCbc);
      expect(image.isAuthenticated, isFalse);
    },
  );
  test(
    'wrong key and invalid PKCS7 padding cannot become an accepted image',
    () {
      final container = base64Decode(otaEncryptedFixtureBase64);
      expect(
        () => FirmwareImage.parse(
          container,
          encrypted: true,
          legacyAesKey: Uint8List(32),
        ),
        throwsA(isA<FirmwareImageException>()),
      );
      // Last plaintext block is16 bytes of padding; corrupt CBC previous block.
      container[container.length - 17] ^= 1;
      expect(
        () => FirmwareImage.parse(
          container,
          encrypted: true,
          legacyAesKey: Uint8List.fromList(List.generate(32, (i) => i)),
        ),
        throwsA(isA<FirmwareImageException>()),
      );
    },
  );
  test(
    'raw application bytes are validated owned readonly and described without authenticity claim',
    () {
      final input = otaImageBytes();
      final original = input.toList();
      final image = FirmwareImage.parse(input);
      input.fillRange(0, input.length, 0);
      expect(image.bytes, original);
      expect(() => image.bytes[0] = 1, throwsUnsupportedError);
      expect(image.version, '2.4.0');
      expect(image.projectName, 'bdk_audio');
      expect(image.idfVersion, 'v5.5-fixture');
      expect(image.chipId, 0);
      expect(image.segmentCount, 1);
      expect(image.secureVersion, 1);
      expect(image.minimumChipRevision, 0);
      expect(image.maximumChipRevision, 65535);
      expect(image.sourceFormat, FirmwareSourceFormat.raw);
      expect(image.hasAppendedHash, isTrue);
      expect(image.sha256Hex, sha256.convert(original).toString());
      expect(image.isAuthenticated, isFalse);
    },
  );
  test(
    'checksum-only raw image remains a corruption check not a signature',
    () {
      final image = FirmwareImage.parse(otaImageBytes(hash: false));
      expect(image.hasAppendedHash, isFalse);
      expect(image.isAuthenticated, isFalse);
    },
  );
  test(
    'rejects malformed bounds magic segment count and truncated segment sizes',
    () {
      final cases = <Uint8List>[
        Uint8List(0),
        Uint8List(24),
        otaImageBytes()..[0] = 0,
        otaImageBytes()..[1] = 0,
        otaImageBytes()..[1] = 17,
        otaImageBytes()
          ..[28] = 255
          ..[29] = 255
          ..[30] = 255
          ..[31] = 127,
        Uint8List.fromList(otaImageBytes().take(80).toList()),
      ];
      for (final bytes in cases) {
        expect(
          () => FirmwareImage.parse(bytes),
          throwsA(isA<FirmwareImageException>()),
        );
      }
    },
  );
  test(
    'rejects other chips bootloader-like bytes and unsupported appended envelopes',
    () {
      expect(
        () => FirmwareImage.parse(otaImageBytes(chipId: 9)),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () => FirmwareImage.parse(otaImageBytes(descriptor: false)),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () =>
            FirmwareImage.parse(Uint8List.fromList([...otaImageBytes(), 0xff])),
        throwsA(isA<FirmwareImageException>()),
      );
      expect(
        () => FirmwareImage.parse(otaImageBytes(), maxBytes: 100),
        throwsA(isA<FirmwareImageException>()),
      );
    },
  );
  test(
    'detects corruption independently in segment XOR and optional SHA256',
    () {
      expect(
        () => FirmwareImage.parse(otaImageBytes(hash: false)..[200] = 1),
        throwsA(
          isA<FirmwareImageException>().having(
            (error) => error.kind,
            'kind',
            FirmwareImageError.checksum,
          ),
        ),
      );
      expect(
        () => FirmwareImage.parse(otaImageBytes()..[335] = 0),
        throwsA(
          isA<FirmwareImageException>().having(
            (error) => error.kind,
            'kind',
            FirmwareImageError.checksum,
          ),
        ),
      );
    },
  );
  test(
    'encrypted input requires an explicit32byte key and aligned bounded container',
    () {
      for (final key in [null, Uint8List(16), Uint8List(31), Uint8List(33)]) {
        expect(
          () => FirmwareImage.parse(
            Uint8List(48),
            encrypted: true,
            legacyAesKey: key,
          ),
          throwsA(isA<FirmwareImageException>()),
        );
      }
      for (final count in [0, 16, 17, 31, 33]) {
        expect(
          () => FirmwareImage.parse(
            Uint8List(count),
            encrypted: true,
            legacyAesKey: Uint8List(32),
          ),
          throwsA(isA<FirmwareImageException>()),
        );
      }
    },
  );
}
