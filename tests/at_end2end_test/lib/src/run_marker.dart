import 'dart:math';

/// The label naming the workflow run, and its attempt, that creates an
/// enrollment: `<GITHUB_RUN_ID>-<GITHUB_RUN_ATTEMPT>` under GitHub Actions,
/// and `local-` with a random suffix anywhere else.
///
/// It labels an enrollment for whoever reads the atSign's roster, and never
/// authorises anything: whoever submits an enrollment request chooses its
/// appName.
String runMarker(Map<String, String> environment, {Random? random}) {
  final runId = environment['GITHUB_RUN_ID'] ?? '';
  final attempt = environment['GITHUB_RUN_ATTEMPT'] ?? '';
  if (runId.isNotEmpty && attempt.isNotEmpty) return '$runId-$attempt';
  final suffix = (random ?? Random.secure()).nextInt(1 << 32).toRadixString(16);
  return 'local-$suffix';
}

/// The appName `enrollment_setup.dart` submits under [marker], with a
/// [suffix] so that two setups under one marker never ask for the same
/// (appName, deviceName).
String enrollmentAppName(String marker, int suffix) => 'wavi-$marker-$suffix';
