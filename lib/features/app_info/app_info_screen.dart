import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../licenses.dart';

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key, this.loadPackageInfo});

  final Future<PackageInfo> Function()? loadPackageInfo;

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  late final Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    registerBundledLicenses();
    _packageInfo = (widget.loadPackageInfo ?? PackageInfo.fromPlatform)();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/branding/bdk-mark.png',
                    width: 64,
                    height: 64,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text('BDK Audio', style: text.headlineMedium),
                const SizedBox(height: 12),
                FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('App version unavailable');
                    }
                    final info = snapshot.data;
                    if (info == null) {
                      return const Text('Reading app version…');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.version.trim().isEmpty
                              ? 'Version unavailable'
                              : 'Version ${info.version}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info.buildNumber.trim().isEmpty
                              ? 'Build unavailable'
                              : 'Build ${info.buildNumber}',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About', style: text.titleLarge),
                const SizedBox(height: 12),
                const Text(
                  'Bluetooth DSP controller for your BDK speaker.\n\n'
                  'Connect, adjust sound and lighting, and update firmware '
                  'over BLE.',
                ),
                const SizedBox(height: 24),
                Text('Original creator', style: text.titleMedium),
                const SizedBox(height: 6),
                const Text('WillyBilly'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licenses and notices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'BDK Audio'),
          ),
        ),
      ],
    );
  }
}
