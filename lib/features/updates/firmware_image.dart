import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

enum FirmwareSourceFormat { raw, legacyAesCbc }

enum FirmwareImageError {
  size,
  format,
  encryption,
  checksum,
  compatibility,
  unsupported,
}

class FirmwareImageException extends FormatException {
  const FirmwareImageException(super.message, this.kind);
  final FirmwareImageError kind;
}

/// A bounded, structurally checked application image, not a trusted release.
/// Local checks cannot attest publisher, target board/partition, secure boot
/// keys, anti-rollback settings, or the bytes eventually written by a speaker.
class FirmwareImage {
  FirmwareImage._({
    required Uint8List bytes,
    required this.sourceFormat,
    required this.version,
    required this.projectName,
    required this.idfVersion,
    required this.sha256Hex,
    required this.chipId,
    required this.segmentCount,
    required this.secureVersion,
    required this.minimumChipRevision,
    required this.maximumChipRevision,
    required this.hasAppendedHash,
  }) : bytes = bytes.asUnmodifiableView();
  static const maximumBytes = 8 * 1024 * 1024;
  final Uint8List bytes;
  int get sizeBytes => bytes.length;
  final FirmwareSourceFormat sourceFormat;
  final String version, projectName, idfVersion, sha256Hex;
  final int chipId,
      segmentCount,
      secureVersion,
      minimumChipRevision,
      maximumChipRevision;
  final bool hasAppendedHash;
  bool get isAuthenticated => false;

  /// .enc exactly preserves the original Android IV16 + AES256 CBC PKCS7
  /// container. Its placeholder key is deliberately not an implicit default.
  static FirmwareImage parse(
    Uint8List input, {
    bool encrypted = false,
    Uint8List? legacyAesKey,
    int maxBytes = maximumBytes,
    int expectedChipId = 0,
  }) {
    if (maxBytes < 1 ||
        maxBytes > maximumBytes ||
        expectedChipId < 0 ||
        expectedChipId > 65535) {
      throw const FirmwareImageException(
        'Invalid image validation bounds.',
        FirmwareImageError.size,
      );
    }
    if (input.isEmpty || input.length > maxBytes + (encrypted ? 32 : 0)) {
      throw const FirmwareImageException(
        'Application image exceeds the local size bound or is empty.',
        FirmwareImageError.size,
      );
    }
    final raw = encrypted
        ? _decrypt(input, legacyAesKey)
        : Uint8List.fromList(input);
    if (raw.length < 24 + 8 + 256 + 1 || raw.length > maxBytes) {
      throw const FirmwareImageException(
        'Use a bounded application binary, not a bootloader or merged image.',
        FirmwareImageError.size,
      );
    }
    final view = ByteData.sublistView(raw);
    if (raw[0] != 0xe9 || raw[1] < 1 || raw[1] > 16 || raw[23] > 1) {
      throw const FirmwareImageException(
        'Unsupported application image header.',
        FirmwareImageError.format,
      );
    }
    final chip = view.getUint16(12, Endian.little);
    if (chip != expectedChipId) {
      throw FirmwareImageException(
        'Image chip ID $chip does not match expected chip ID $expectedChipId.',
        FirmwareImageError.compatibility,
      );
    }
    final entry = view.getUint32(4, Endian.little);
    if (expectedChipId == 0 && (entry < 0x40000000 || entry >= 0x40400000)) {
      throw const FirmwareImageException(
        'Image entry point is outside the supported ESP32 executable range.',
        FirmwareImageError.compatibility,
      );
    }
    var offset = 24, checksum = 0xef, firstLength = 0;
    for (var segment = 0; segment < raw[1]; segment++) {
      if (offset + 8 > raw.length) {
        throw const FirmwareImageException(
          'Truncated application segment header.',
          FirmwareImageError.format,
        );
      }
      final length = view.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (length > maxBytes ||
          length > raw.length - offset ||
          length % 4 != 0) {
        throw const FirmwareImageException(
          'Invalid or truncated application segment.',
          FirmwareImageError.format,
        );
      }
      if (segment == 0) firstLength = length;
      for (var index = offset; index < offset + length; index++) {
        checksum ^= raw[index];
      }
      offset += length;
    }
    final checksumIndex = ((offset + 16) ~/ 16) * 16 - 1;
    if (checksumIndex >= raw.length) {
      throw const FirmwareImageException(
        'Application checksum is missing.',
        FirmwareImageError.format,
      );
    }
    for (var index = offset; index < checksumIndex; index++) {
      if (raw[index] != 0) {
        throw const FirmwareImageException(
          'Unsupported nonzero image footer padding.',
          FirmwareImageError.format,
        );
      }
    }
    if (raw[checksumIndex] != checksum) {
      throw const FirmwareImageException(
        'Application segment checksum does not match.',
        FirmwareImageError.checksum,
      );
    }
    final hashed = raw[23] == 1;
    final expectedLength = checksumIndex + 1 + (hashed ? 32 : 0);
    if (raw.length != expectedLength) {
      throw const FirmwareImageException(
        'Truncated image or unsupported signed/merged trailer. No bytes were stripped.',
        FirmwareImageError.unsupported,
      );
    }
    if (hashed) {
      final actual = crypto.sha256
          .convert(Uint8List.sublistView(raw, 0, checksumIndex + 1))
          .bytes;
      var difference = 0;
      for (var i = 0; i < 32; i++) {
        difference |= actual[i] ^ raw[checksumIndex + 1 + i];
      }
      if (difference != 0) {
        throw const FirmwareImageException(
          'Application SHA256 corruption check does not match.',
          FirmwareImageError.checksum,
        );
      }
    }
    if (firstLength < 256 || view.getUint32(32, Endian.little) != 0xabcd5432) {
      throw const FirmwareImageException(
        'Missing supported ESP-IDF application descriptor. Bootloader/merged files are not accepted.',
        FirmwareImageError.compatibility,
      );
    }
    String text(int at, int length) {
      final field = Uint8List.sublistView(raw, at, at + length);
      final zero = field.indexOf(0);
      late String value;
      try {
        value = utf8.decode(zero < 0 ? field : field.sublist(0, zero)).trim();
      } on FormatException {
        throw const FirmwareImageException(
          'Invalid application descriptor text.',
          FirmwareImageError.format,
        );
      }
      if (value.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FirmwareImageException(
          'Application descriptor text is missing or invalid.',
          FirmwareImageError.format,
        );
      }
      return value;
    }

    return FirmwareImage._(
      bytes: raw,
      sourceFormat: encrypted
          ? FirmwareSourceFormat.legacyAesCbc
          : FirmwareSourceFormat.raw,
      version: text(48, 32),
      projectName: text(80, 32),
      idfVersion: text(144, 32),
      sha256Hex: crypto.sha256.convert(raw).toString(),
      chipId: chip,
      segmentCount: raw[1],
      secureVersion: view.getUint32(36, Endian.little),
      minimumChipRevision: view.getUint16(15, Endian.little),
      maximumChipRevision: view.getUint16(17, Endian.little),
      hasAppendedHash: hashed,
    );
  }

  static Uint8List _decrypt(Uint8List input, Uint8List? key) {
    if (key == null ||
        key.length != 32 ||
        input.length < 32 ||
        (input.length - 16) % 16 != 0) {
      throw const FirmwareImageException(
        'Legacy encrypted import requires an explicit 32-byte key and IV-prefixed AES-CBC container.',
        FirmwareImageError.encryption,
      );
    }
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV<KeyParameter>(
          KeyParameter(Uint8List.fromList(key)),
          Uint8List.fromList(input.sublist(0, 16)),
        ),
      );
    final plaintext = Uint8List(input.length - 16);
    try {
      for (var offset = 16; offset < input.length; offset += 16) {
        cipher.processBlock(input, offset, plaintext, offset - 16);
      }
      final count = plaintext.last;
      var invalid = count < 1 || count > 16;
      if (!invalid) {
        for (var i = plaintext.length - count; i < plaintext.length; i++) {
          invalid |= plaintext[i] != count;
        }
      }
      if (invalid) throw const FormatException('Invalid padding');
      return Uint8List.fromList(plaintext.sublist(0, plaintext.length - count));
    } catch (_) {
      throw const FirmwareImageException(
        'Legacy decryption failed. Check the key and file.',
        FirmwareImageError.encryption,
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }
}
