import 'dart:typed_data';
import 'package:bdk_audio/features/imports/bounded_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file cancellation has no read side effect', () async {
    final io = BoundedFilePicker(picker: (_) async => null);
    expect(await io.pick(maximumBytes: 16, extensions: const ['json']), isNull);
  });
  test('reads only selected bytes and owns the imported result', () async {
    final data = Uint8List.fromList([1, 2, 3]);
    final io = BoundedFilePicker(
      picker: (_) async => SelectedImportFile(
        name: '../keep.json',
        length: 3,
        openStream: () => Stream.value(data),
      ),
    );
    final result = (await io.pick(
      maximumBytes: 16,
      extensions: const ['json'],
    ))!;
    data[0] = 99;
    expect(result.name, '../keep.json');
    expect(result.bytes, [1, 2, 3]);
    expect(() => result.bytes[0] = 0, throwsUnsupportedError);
  });
  test('oversize metadata is refused before opening the file', () async {
    var opened = false;
    final io = BoundedFilePicker(
      picker: (_) async => SelectedImportFile(
        name: 'big',
        length: 17,
        openStream: () {
          opened = true;
          return const Stream.empty();
        },
      ),
    );
    await expectLater(
      io.pick(maximumBytes: 16, extensions: const []),
      throwsFormatException,
    );
    expect(opened, isFalse);
  });
  test(
    'unknown length is bounded while reading without silent truncation',
    () async {
      var read = 0;
      Stream<List<int>> stream() async* {
        for (var i = 0; i < 100; i++) {
          read++;
          yield [1, 2, 3, 4];
        }
      }

      final io = BoundedFilePicker(
        picker: (_) async =>
            SelectedImportFile(name: 'big', openStream: stream),
      );
      await expectLater(
        io.pick(maximumBytes: 10, extensions: const []),
        throwsFormatException,
      );
      expect(read, lessThan(100));
    },
  );
  test(
    'changed or empty provider content never becomes a successful file',
    () async {
      for (final n in [0, 4]) {
        final io = BoundedFilePicker(
          picker: (_) async => SelectedImportFile(
            name: 'bad',
            length: n,
            openStream: () => Stream.value([1, 2]),
          ),
        );
        await expectLater(
          io.pick(maximumBytes: 10, extensions: const []),
          throwsFormatException,
        );
      }
    },
  );
}
