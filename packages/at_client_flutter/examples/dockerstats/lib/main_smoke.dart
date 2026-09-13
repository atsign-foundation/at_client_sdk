/// Smoke entry point: bypasses interactive onboarding and opens a client
/// directly on a pre-existing `.atKeys` file at
/// `${HOME}/.atsign/keys/<atSign>_key.atKeys`.
///
/// Used by the round-trip end-to-end smoke test:
///
///   flutter run -t lib/main_smoke.dart -d macos \
///       --dart-define=DOCKERSTATS_SMOKE_ATSIGN=@baboonblue18
///
/// The canonical entrypoint at `lib/main.dart` is unchanged — this
/// affordance exists so the dashboard's data path can be exercised
/// against a real atServer in a non-interactive environment (CI,
/// agent harnesses).
library;

import 'dart:io';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'screens/dashboard.dart';
import 'services/dockerstats_service.dart';

void _smokeLog(String s) => debugPrint('[smoke] $s');

const _atSignDefine = String.fromEnvironment('DOCKERSTATS_SMOKE_ATSIGN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AtSignLogger.defaultLoggingHandler = AtSignLogger.stdErrLoggingHandler;
  AtSignLogger.root_level = 'INFO';
  _smokeLog('main entered');
  runApp(const _SmokeApp());
}

class _SmokeApp extends StatelessWidget {
  const _SmokeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Docker stats — smoke',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _SmokeBootstrap(),
    );
  }
}

class _SmokeBootstrap extends StatefulWidget {
  const _SmokeBootstrap();

  @override
  State<_SmokeBootstrap> createState() => _SmokeBootstrapState();
}

class _SmokeBootstrapState extends State<_SmokeBootstrap> {
  String _status = 'Booting...';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  void _setStatus(String s) {
    _smokeLog(s);
    if (mounted) setState(() => _status = s);
  }

  Future<void> _bootstrap() async {
    try {
      _setStatus('bootstrap starting');
      final atSign = _atSignDefine;
      if (atSign.isEmpty) {
        _setStatus(
          'Set --dart-define=DOCKERSTATS_SMOKE_ATSIGN=@<atsign> to launch.',
        );
        return;
      }
      _setStatus('Opening $atSign...');
      final home = Platform.environment['HOME'] ?? '/Users/gary';
      final keysPath = '$home/.atsign/keys/${atSign}_key.atKeys';
      if (!File(keysPath).existsSync()) {
        _setStatus('No atKeys file at $keysPath');
        return;
      }
      final dir = await getApplicationSupportDirectory();
      final acp = AtClientPreference()..namespace = applicationNamespace;
      // closedByClient: this app picks the location and the client still closes
      // the store when it stops, so there is nothing to tear down.
      final storage = HiveAtClientStorage(
        atSign: atSign,
        storagePath: dir.path,
        closedByClient: true,
      );
      final client = await Atsign(atSign).open(
        keys: FileAtKeysIo(filePath: (_) => keysPath),
        preference: acp,
        storage: storage,
      );
      // The smoke test reads live data, so an offline client is no use to it.
      final connection = await client.connection.awaitOnline(
        budget: const Duration(seconds: 30),
      );
      if (!connection.isOnline) {
        _setStatus(
          'Could not get $atSign online: ${connection.outcome.name} '
          '(${connection.cause?.name})',
        );
        await client.stop();
        return;
      }
      AtClientManager.getInstance().use(client);
      _setStatus('AtClient ready, navigating to dashboard');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } catch (e, st) {
      _setStatus('Bootstrap failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(_status, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
