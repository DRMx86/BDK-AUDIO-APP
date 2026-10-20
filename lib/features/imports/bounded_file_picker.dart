import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class SelectedImportFile {
  const SelectedImportFile({
    required this.name,
    required this.openStream,
    this.length,
  });
  final String name;
  final int? length;
  final Stream<List<int>> Function() openStream;
}

class ImportedFile {
  ImportedFile(this.name, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String name;
  final Uint8List bytes;
}

class BoundedFilePicker {
  BoundedFilePicker({
    Future<SelectedImportFile?> Function(List<String>)? picker,
  }) : _picker = picker ?? _nativePick;
  final Future<SelectedImportFile?> Function(List<String>) _picker;

  static Future<SelectedImportFile?> _nativePick(
    List<String> extensions,
  ) async {
    // Mobile MIME dictionaries do not reliably recognize .enc/.xml aliases.
    // The chosen bytes, never the filename, determine whether import succeeds.
    final filtered =
        (Platform.isWindows || Platform.isLinux) && extensions.isNotEmpty;
    final file = await FilePicker.pickFile(
      type: filtered ? FileType.custom : FileType.any,
      allowedExtensions: filtered ? extensions : null,
      dialogTitle: 'Choose a file',
    );
    if (file == null) return null;
    return SelectedImportFile(
      name: file.name,
      length: file.lengthSync() ?? await file.length(),
      openStream: file.readAsByteStream,
    );
  }

  Future<ImportedFile?> pick({
    required int maximumBytes,
    required List<String> extensions,
  }) async {
    if (maximumBytes < 1 || maximumBytes > 16 * 1024 * 1024) {
      throw ArgumentError('Invalid import size limit.');
    }
    try {
      final file = await _picker(extensions);
      if (file == null) return null;
      if (file.name.isEmpty ||
          file.name.length > 1024 ||
          (file.length != null &&
              (file.length! < 1 || file.length! > maximumBytes))) {
        throw const FormatException(
          'This file is empty or exceeds the import size limit.',
        );
      }
      final bytes = BytesBuilder(copy: true);
      await for (final chunk in file.openStream().timeout(
        const Duration(seconds: 15),
      )) {
        if (chunk.length > maximumBytes - bytes.length) {
          throw const FormatException(
            'This file exceeds the import size limit.',
          );
        }
        bytes.add(chunk);
      }
      if (bytes.isEmpty ||
          (file.length != null && file.length != bytes.length)) {
        throw const FormatException(
          'The selected file changed or could not be read completely.',
        );
      }
      return ImportedFile(file.name, bytes.takeBytes());
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'This file could not be read. Select it again and try once more.',
      );
    }
  }
}
