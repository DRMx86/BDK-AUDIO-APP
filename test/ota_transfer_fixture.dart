import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// Independent .NET AES/CBC/PKCS7 fixture, Key 00..1f, IV 10..1f. Plaintext is
// exactly otaImageBytes(). Synthetic metadata only; never a built device image.
const otaEncryptedFixtureBase64 =
    'EBESExQVFhcYGRobHB0eH4dwxC1NXW7Yofn9ENhdCE1lnKSaYe0b1YPOGYqlBexMMOaGjrPm8ME9qGk3eAYxzeM2xBqnXCuL447NzgelKzFxXAAumZNw+1wQgYIZAmh0Fhg1oe0+DqtORSgPM+6P5PPNoldhtiZY2fDZUdCnYFS+9rU+/OfL3QBQ6dJVejqw2d8pUHgHUiYfTSn1PK1NNhoSrRCjNXgoIyO0W2qQhqztm93n+HvA0N3myyVU8CDDLKGbI6fOfBNw8TA7K0beebMzsSFHY1a5NkuPNya0qpSklzgcnr/WX93uUAkkaGjfMAe/c5j0cu9xrq4s/TnCZl1z9Szf9669n77MkbRvG81daR3UEX5g5rVbc2iYIGsqEOOtShOPmzzbjLK8Mgf3zKDwrZTihn661Y+Br2a9nquJRjjkAnAgVv4F57Mrw3aRUWIBHWC1Q6OTOwFJ6jcpcwAPhbAVr4hE3st37flPW2o=';

Uint8List otaMultiSegmentImageBytes() {
  final first = otaImageBytes(hash: false);
  final raw = Uint8List(352)..setRange(0, 288, first);
  final header = ByteData.sublistView(raw);
  raw[1] = 2;
  raw[23] = 1;
  header.setUint32(288, 0x3ffb0000, Endian.little);
  header.setUint32(292, 8, Endian.little);
  raw.setRange(296, 304, [1, 2, 3, 4, 5, 6, 7, 8]);
  raw[319] = [
    ...raw.sublist(32, 288),
    ...raw.sublist(296, 304),
  ].fold(0xef, (sum, value) => sum ^ value);
  raw.setRange(
    320,
    352,
    sha256.convert(Uint8List.sublistView(raw, 0, 320)).bytes,
  );
  return raw;
}

// Synthetic application-like data, never built/flashed firmware.
Uint8List otaImageBytes({
  String version = '2.4.0',
  int chipId = 0,
  bool hash = true,
  int dataLength = 256,
  bool descriptor = true,
}) {
  final data = Uint8List(dataLength);
  final desc = ByteData.sublistView(data);
  if (descriptor && dataLength >= 256) {
    desc.setUint32(0, 0xabcd5432, Endian.little);
    desc.setUint32(4, 1, Endian.little);
    void text(int at, String value, int size) {
      final encoded = utf8.encode(value);
      data.setRange(at, at + encoded.length.clamp(0, size), encoded.take(size));
    }

    text(16, version, 32);
    text(48, 'bdk_audio', 32);
    text(112, 'v5.5-fixture', 32);
  }
  final checksumIndex = ((24 + 8 + data.length + 16) ~/ 16) * 16 - 1;
  final raw = Uint8List(checksumIndex + 1 + (hash ? 32 : 0));
  final header = ByteData.sublistView(raw);
  raw[0] = 0xe9;
  raw[1] = 1;
  raw[2] = 2;
  raw[3] = 0x20;
  raw[8] = 0xee;
  header.setUint32(4, 0x40080000, Endian.little);
  header.setUint16(12, chipId, Endian.little);
  header.setUint16(17, 65535, Endian.little);
  raw[23] = hash ? 1 : 0;
  header.setUint32(24, 0x3f400020, Endian.little);
  header.setUint32(28, data.length, Endian.little);
  raw.setRange(32, 32 + data.length, data);
  raw[checksumIndex] = data.fold(0xef, (sum, value) => sum ^ value);
  if (hash) {
    raw.setRange(
      checksumIndex + 1,
      raw.length,
      sha256.convert(Uint8List.sublistView(raw, 0, checksumIndex + 1)).bytes,
    );
  }
  return raw;
}
