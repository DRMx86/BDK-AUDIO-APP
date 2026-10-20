import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/profile_run.dart';

void main() {
  test(
    'new failed or interrupted runs cannot reuse an earlier successful report',
    () async {
      final base = await Directory(
        'build/profile-run-tests',
      ).create(recursive: true);
      final dir = await base.createTemp('case-');
      addTearDown(() async {
        final root = await base.resolveSymbolicLinks();
        final target = await dir.resolveSymbolicLinks();
        if (!target.startsWith('$root${Platform.pathSeparator}')) {
          throw StateError('Unexpected cleanup scope');
        }
        await dir.delete(recursive: true);
      });
      final first = await ProfileRun.begin(dir, runId: 'first', processId: 1);
      await first.complete({'conclusiveRun': true});
      final second = await ProfileRun.begin(dir, runId: 'second', processId: 2);
      Map current() =>
          jsonDecode(
                File('${dir.path}/bdk-preview-profile.json').readAsStringSync(),
              )
              as Map;
      expect(current()['conclusiveRun'], false);
      expect(current()['runId'], 'second');
      await second.fail('native renderer unavailable');
      expect(current()['state'], 'failed');
      expect(current()['processId'], 2);
      expect(
        jsonDecode(
          File('${dir.path}/bdk-preview-profile-first.json').readAsStringSync(),
        )['conclusiveRun'],
        true,
      );
      await ProfileRun.begin(dir, runId: 'interrupted', processId: 3);
      expect(current()['runId'], 'interrupted');
      expect(current()['state'], 'incomplete');
      expect(current()['conclusiveRun'], false);
    },
  );
  test(
    'late reduced motion and partial stopped rendering invalidate a window',
    () {
      final valid = ProfileWorkload();
      for (var i = 0; i < 6; i++) {
        valid.rendered(i * 1000000 + 100000);
      }
      expect(valid.conclusive(start: 0, end: 6000000), true);
      valid.observeReducedMotion(true);
      valid.observeReducedMotion(false);
      expect(valid.conclusive(start: 0, end: 6000000), false);
      final stopped = ProfileWorkload();
      for (var i = 0; i < 60; i++) {
        stopped.rendered(i * 16000);
      }
      expect(stopped.conclusive(start: 0, end: 6000000), false);
      final failed = ProfileWorkload()..renderFailed = true;
      for (var i = 0; i < 6; i++) {
        failed.rendered(i * 1000000 + 100000);
      }
      expect(failed.conclusive(start: 0, end: 6000000), false);
    },
  );
  testWidgets(
    'benchmark workloads cannot be paused by pointer, focus or semantic interaction',
    (tester) async {
      var taps = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FixedProfileWorkload(
              child: TextButton(
                focusNode: focus,
                onPressed: () => taps++,
                child: const Text('Pause preview'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pause preview'), warnIfMissed: false);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, false);
      expect(taps, 0);
    },
  );
}
