import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart'
    show CLIBase, getHomeDirectory;
import 'package:at_client/at_client.dart' show AtClient, AtNotification;
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence_sqlite.dart';
import 'package:at_telemetry_service/at_telemetry_service.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('bind-address', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '4318')
    ..addOption('database', defaultsTo: 'sqlite')
    ..addOption('database-path')
    ..addOption('api-keys-file')
    ..addOption('reader-api-keys-file')
    ..addOption('tls-certificate-chain')
    ..addOption('tls-private-key')
    ..addOption('atsign')
    ..addOption('atsign-producers-file')
    ..addOption('atkeys-file')
    ..addOption('atsign-storage-dir')
    ..addOption('root-server', defaultsTo: 'root.atsign.org:64')
    ..addOption(
      'max-request-bytes',
      defaultsTo: '${AtTelemetryService.defaultMaxRequestBytes}',
    );

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (results.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final String database = results.option('database')!;
  if (database != 'sqlite') {
    stderr.writeln('Unsupported database adapter: $database');
    exitCode = 64;
    return;
  }

  final String? databasePath = _setting(
    results,
    'database-path',
    'AT_TELEMETRY_DATABASE_PATH',
  );
  final String? apiKeysFile = _setting(
    results,
    'api-keys-file',
    'AT_TELEMETRY_API_KEYS_FILE',
  );
  final String? readerApiKeysFile = _setting(
    results,
    'reader-api-keys-file',
    'AT_TELEMETRY_READER_API_KEYS_FILE',
  );
  final String? tlsCertificateChain = _setting(
    results,
    'tls-certificate-chain',
    'AT_TELEMETRY_TLS_CERTIFICATE_CHAIN',
  );
  final String? tlsPrivateKey = _setting(
    results,
    'tls-private-key',
    'AT_TELEMETRY_TLS_PRIVATE_KEY',
  );
  final String? atsign = _setting(results, 'atsign', 'AT_TELEMETRY_ATSIGN');
  final String? atsignProducersFile = _setting(
    results,
    'atsign-producers-file',
    'AT_TELEMETRY_ATSIGN_PRODUCERS_FILE',
  );

  if (databasePath == null) {
    stderr.writeln('Provide --database-path or AT_TELEMETRY_DATABASE_PATH');
    exitCode = 64;
    return;
  }
  if (apiKeysFile == null) {
    stderr.writeln('Provide --api-keys-file or AT_TELEMETRY_API_KEYS_FILE');
    exitCode = 64;
    return;
  }
  if ((tlsCertificateChain == null) != (tlsPrivateKey == null)) {
    stderr.writeln(
      'Provide both --tls-certificate-chain and --tls-private-key, or neither',
    );
    exitCode = 64;
    return;
  }
  if ((atsign == null) != (atsignProducersFile == null)) {
    stderr.writeln(
      'Provide both --atsign and --atsign-producers-file, or neither',
    );
    exitCode = 64;
    return;
  }

  final int port;
  final int maxRequestBytes;
  try {
    port = int.parse(results.option('port')!);
    maxRequestBytes = int.parse(results.option('max-request-bytes')!);
  } on FormatException {
    stderr.writeln('Port and max-request-bytes must be integers');
    exitCode = 64;
    return;
  }

  final AtTelemetryApiKeyAuthenticator producerAuthenticator;
  try {
    producerAuthenticator = AtTelemetryApiKeyAuthenticator(
      <AtTelemetryApiKeyCredential>[
        for (final Map<String, String> entry in await _loadEntries(
          File(apiKeysFile),
          <String>['apiKey', 'producerId', 'tenantId'],
        ))
          AtTelemetryApiKeyCredential(
            apiKey: entry['apiKey']!,
            producerId: entry['producerId']!,
            tenantId: entry['tenantId']!,
          ),
      ],
    );
  } on Object {
    stderr.writeln('Unable to load API key configuration');
    exitCode = 78;
    return;
  }

  AtTelemetryReaderApiKeyAuthenticator? readerAuthenticator;
  if (readerApiKeysFile != null) {
    try {
      final List<Map<String, String>> entries = await _loadEntries(
        File(readerApiKeysFile),
        <String>['apiKey', 'readerId', 'tenantId'],
      );
      for (final Map<String, String> entry in entries) {
        if (await producerAuthenticator.authenticate(entry['apiKey']!) !=
            null) {
          throw ArgumentError('Reader API keys must differ from producer keys');
        }
      }
      readerAuthenticator = AtTelemetryReaderApiKeyAuthenticator(
        <AtTelemetryReaderApiKeyCredential>[
          for (final Map<String, String> entry in entries)
            AtTelemetryReaderApiKeyCredential(
              apiKey: entry['apiKey']!,
              readerId: entry['readerId']!,
              tenantId: entry['tenantId']!,
            ),
        ],
      );
    } on Object {
      stderr.writeln('Unable to load reader API key configuration');
      exitCode = 78;
      return;
    }
  }

  AtTelemetryAtsignAuthenticator? atsignAuthenticator;
  if (atsignProducersFile != null) {
    try {
      atsignAuthenticator = AtTelemetryAtsignAuthenticator(
        <AtTelemetryAtsignCredential>[
          for (final Map<String, String> entry in await _loadEntries(
            File(atsignProducersFile),
            <String>['atsign', 'tenantId'],
          ))
            AtTelemetryAtsignCredential(
              atsign: entry['atsign']!,
              tenantId: entry['tenantId']!,
            ),
        ],
      );
    } on Object {
      stderr.writeln('Unable to load Atsign producer configuration');
      exitCode = 78;
      return;
    }
  }

  SecurityContext? securityContext;
  if (tlsCertificateChain != null && tlsPrivateKey != null) {
    try {
      securityContext = SecurityContext()
        ..useCertificateChain(tlsCertificateChain)
        ..usePrivateKey(tlsPrivateKey);
    } on Object {
      stderr.writeln('Unable to load TLS certificate chain or private key');
      exitCode = 78;
      return;
    }
  }

  final AtTelemetrySqlitePersistence persistence =
      AtTelemetrySqlitePersistence.open(databasePath);
  final AtTelemetryIngestor ingestor = AtTelemetryIngestor(
    persistence: persistence,
  );
  AtTelemetryService? service;
  AtClient? atClient;
  StreamSubscription<AtTelemetryNotificationOutcome>? notifications;
  try {
    service = await AtTelemetryService.bind(
      address: results.option('bind-address')!,
      port: port,
      authenticator: producerAuthenticator,
      ingestor: ingestor,
      maxRequestBytes: maxRequestBytes,
      readerAuthenticator: readerAuthenticator,
      persistence: readerAuthenticator == null ? null : persistence,
      securityContext: securityContext,
    );
    stdout.writeln(
      'at_telemetry_service listening on '
      '${securityContext == null ? 'http' : 'https'}://'
      '${service.address.address}:${service.port}',
    );

    if (atsign != null && atsignAuthenticator != null) {
      final CLIBase cli = CLIBase(
        atSign: atsign,
        nameSpace: AtTelemetryNotificationCodec.namespace,
        rootDomain: results.option('root-server'),
        homeDir: getHomeDirectory(),
        atKeysFilePath: results.option('atkeys-file'),
        storageDir: results.option('atsign-storage-dir'),
      );
      await cli.init();
      atClient = cli.atClient;
      final AtTelemetryNotificationReceiver receiver =
          AtTelemetryNotificationReceiver(
        authenticator: atsignAuthenticator,
        ingestor: ingestor,
        maxPayloadCharacters: 4 * ((maxRequestBytes + 2) ~/ 3),
        onOutcome: _reportNotificationOutcome,
      );
      notifications = receiver.listen(
        atClient.notificationService.subscribeFiltered(
          namespace: AtTelemetryNotificationCodec.namespace,
        ),
      );
      stdout.writeln(
        'at_telemetry_service receiving notifications as ${cli.atSign} '
        'in namespace ${AtTelemetryNotificationCodec.namespace}',
      );
    }

    await Future.any(<Future<ProcessSignal>>[
      ProcessSignal.sigint.watch().first,
      ProcessSignal.sigterm.watch().first,
    ]);
  } on Object catch (error) {
    stderr.writeln('at_telemetry_service failed: ${error.runtimeType}');
    exitCode = 70;
  } finally {
    await notifications?.cancel();
    atClient?.notificationService.stopAllSubscriptions();
    await atClient?.stop();
    await service?.close(force: true);
    await persistence.close();
  }
}

void _reportNotificationOutcome(
  AtNotification notification,
  AtTelemetryNotificationOutcome outcome,
) {
  if (outcome == AtTelemetryNotificationOutcome.accepted) {
    return;
  }
  stderr.writeln(
    'Rejected telemetry notification ${notification.id} '
    'from ${notification.from}: ${outcome.name}',
  );
}

String? _setting(ArgResults results, String option, String environment) {
  final String? value =
      results.option(option) ?? Platform.environment[environment];
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value;
}

Future<List<Map<String, String>>> _loadEntries(
  File file,
  List<String> requiredKeys,
) async {
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! List<Object?>) {
    throw const FormatException('Configuration must be a JSON array');
  }

  final List<Map<String, String>> entries = <Map<String, String>>[];
  for (final Object? entry in decoded) {
    if (entry is! Map<String, Object?>) {
      throw const FormatException('Each configuration entry must be an object');
    }

    final Map<String, String> values = <String, String>{};
    for (final String key in requiredKeys) {
      final Object? value = entry[key];
      if (value is! String) {
        throw FormatException(
          'Each entry requires ${requiredKeys.join(', ')} strings',
        );
      }
      values[key] = value;
    }
    entries.add(values);
  }
  return entries;
}
