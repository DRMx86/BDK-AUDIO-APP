import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';

class ProfileRun {
  ProfileRun._(this.directory, this.runId, this.processId);
  final Directory directory;
  final String runId;
  final int processId;
  bool ended = false;
  static Future<ProfileRun> begin(
    Directory directory, {
    required String runId,
    required int processId,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(runId)) {
      throw ArgumentError('Invalid run identity');
    }
    final run = ProfileRun._(directory, runId, processId);
    await run._report({'conclusiveRun': false}, 'incomplete');
    await run.progress({'state': 'starting'});
    return run;
  }

  Future<void> _write(String name, Map<String, Object?> data) async {
    final temporary = File('${directory.path}/$name.$runId.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    await temporary.rename('${directory.path}/$name');
  }

  Map<String, Object?> _identified(Map<String, Object?> data) => {
    ...data,
    'runId': runId,
    'processId': processId,
  };
  Future<void> _report(Map<String, Object?> data, String state) async {
    final value = _identified({...data, 'state': state});
    await _write('bdk-preview-profile-$runId.json', value);
    await _write('bdk-preview-profile.json', value);
  }

  Future<void> progress(Map<String, Object?> data) async {
    if (!ended) await _write('bdk-preview-progress.json', _identified(data));
  }

  Future<void> complete(Map<String, Object?> data) async {
    if (ended) return;
    await _report({
      ...data,
      'conclusiveRun': data['conclusiveRun'] == true,
    }, 'complete');
    await progress({'state': 'complete'});
    ended = true;
  }

  Future<void> fail(String error) async {
    if (ended) return;
    await _report({'conclusiveRun': false, 'error': error}, 'failed');
    await progress({'state': 'failed'});
    ended = true;
  }
}

class ProfileWorkload {
  final _renders = <int>[];
  bool backgrounded = false, reducedMotion = false, renderFailed = false;
  bool truncated = false;
  void observeReducedMotion(bool disabled) => reducedMotion |= disabled;
  void rendered(int timestamp) {
    if (_renders.length >= 20000) {
      truncated = true;
      return;
    }
    _renders.add(timestamp);
  }

  bool conclusive({required int start, required int end}) {
    if (backgrounded ||
        reducedMotion ||
        renderFailed ||
        truncated ||
        end <= start) {
      return false;
    }
    final bins = List.filled((end - start) ~/ 1000000, 0);
    if (bins.isEmpty) return false;
    for (final timestamp in _renders) {
      final bin = (timestamp - start) ~/ 1000000;
      if (timestamp >= start && bin >= 0 && bin < bins.length) bins[bin]++;
    }
    return bins.every((count) => count > 0);
  }
}

class FixedProfileWorkload extends StatelessWidget {
  const FixedProfileWorkload({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(child: ExcludeFocus(child: child)),
  );
}
