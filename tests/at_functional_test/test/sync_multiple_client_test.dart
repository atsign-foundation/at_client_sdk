import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:at_client/at_client.dart';
import 'package:version/version.dart';
import 'package:uuid/uuid.dart';
import 'package:at_functional_test/src/at_demo_credentials.dart'
    as demo_credentials;

import 'test_utils.dart';

/// The purpose of this test is to run multiple clients in Isolate and inject
/// bulk data.
/// Finally assert the commitId and commitOp. between server and both the clients.
enum ClientId { client1, client2 }

class ChildIsolatePreferences {
  late ClientId clientId;
  late String hiveStoragePath;
  late String commitLogPath;
  late SendPort sendPort;
  late List<String> localKeysList;
}

class IsolateAtClientResponse {
  final ClientId clientId;
  final String type;
  final dynamic message;

  IsolateAtClientResponse(this.clientId, this.type, this.message);
}

late AtClientManager atClientManager;

var currentAtSign = '@alice🛠';
//var sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
String namespace = 'wavi';
// A global variable to pause the execution of test until sync is completed.
// The variable will be used within the child isolates.
final _logger = AtSignLogger('SyncSystemTest')..level = 'warning';
final _mainIsolateLogger = AtSignLogger('MainIsolate')..level = 'warning';
final _childIsolateLogger = AtSignLogger('ChildIsolate')..level = 'warning';

var isolateResponseQueue = Queue();

var childIsolateSendPortMap = <ClientId, SendPort>{};
final String clientOneHiveKeyStorePath = 'test/hive/client1';
final String clientTwoHiveKeyStorePath = 'test/hive/client2';
late Isolate clientOneIsolate;
late Isolate clientTwoIsolate;
int N = 35;
late Completer clientOneAck;
late Completer clientTwoAck;

void main() async {
  AtSignLogger.root_level = 'shout';
  var mainIsolateReceivePort = ReceivePort('MainIsolateReceivePort');
  SyncServiceImpl.queueSize = 1;
  String uniqueId = Uuid().v4().hashCode.toString();

  List<String> atKeyEntityList = [
    'country-$uniqueId',
    'phone-$uniqueId',
    'location-$uniqueId',
    'work_number-$uniqueId',
    'city-$uniqueId'
  ];
  // create 35 keys
  for (int i = 1; i <= 7; i++) {
    atKeyEntityList.add('country_$i-$uniqueId');
    atKeyEntityList.add('phone_$i-$uniqueId');
    atKeyEntityList.add('location_$i-$uniqueId');
    atKeyEntityList.add('work_number_$i-$uniqueId');
    atKeyEntityList.add('city_$i-$uniqueId');
  }

  var clientInitializationParameters = {
    'client1': ChildIsolatePreferences()
      ..clientId = ClientId.client1
      ..hiveStoragePath = clientOneHiveKeyStorePath
      ..commitLogPath = '$clientOneHiveKeyStorePath/commit'
      ..sendPort = mainIsolateReceivePort.sendPort
      ..localKeysList = atKeyEntityList,
    'client2': ChildIsolatePreferences()
      ..clientId = ClientId.client2
      ..hiveStoragePath = clientTwoHiveKeyStorePath
      ..commitLogPath = '$clientTwoHiveKeyStorePath/commit'
      ..sendPort = mainIsolateReceivePort.sendPort
      ..localKeysList = atKeyEntityList
  };

  test(
      'A test to verify keys synced from multiple clients converge to the '
      'same value', () async {
    // Add listener for main isolate to receive messages from child isolates
    mainIsolateReceivePort.listen(mainIsolateMessageListener);

    // Spawn isolate for client-1
    clientOneAck = Completer();
    clientOneIsolate = await Isolate.spawn(
        childIsolate, clientInitializationParameters['client1']!,
        debugName: clientInitializationParameters['client1']!.clientId.name);

    // Spawn isolate for client-2
    clientTwoAck = Completer();
    clientTwoIsolate = await Isolate.spawn(
        childIsolate, clientInitializationParameters['client2']!,
        debugName: clientInitializationParameters['client2']!.clientId.name);

    // Wait until both the client's complete execution
    _logger.info('Waiting for all clients to finish starting up');
    await clientOneAck.future;
    await clientTwoAck.future;

    // Do an initial sync
    _logger.info('Requesting clients perform an initial sync');
    clientOneAck = Completer();
    clientTwoAck = Completer();
    childIsolateSendPortMap[ClientId.client1]?.send('doSync');
    childIsolateSendPortMap[ClientId.client2]?.send('doSync');
    _logger.info('Waiting for client sync calls to complete');
    await clientOneAck.future;
    await clientTwoAck.future;

    // Do the ops
    _logger.info('Requesting clients perform their update / delete ops');
    clientOneAck = Completer();
    clientTwoAck = Completer();
    childIsolateSendPortMap[ClientId.client1]?.send('doOpsAndSync');
    childIsolateSendPortMap[ClientId.client2]?.send('doOpsAndSync');
    _logger.info('Waiting for client update / delete ops to complete');
    await clientOneAck.future;
    await clientTwoAck.future;

    // Do a final sync
    await Future.delayed(Duration(seconds: 1));
    _logger.info('Requesting clients perform a final sync');
    clientOneAck = Completer();
    clientTwoAck = Completer();
    childIsolateSendPortMap[ClientId.client1]?.send('doSync');
    childIsolateSendPortMap[ClientId.client2]?.send('doSync');
    _logger.info('Waiting for client sync calls to complete');
    await clientOneAck.future;
    await clientTwoAck.future;

    // NOTE: Do not fetch local state until all the clients have finished
    // their sync process.
    // Commit-log-free clients carry no local commit log, so multi-client
    // convergence is proven by VALUE: each client's local (decrypted)
    // value per key, cross-checked against the server's per-key presence
    // from its commit log.
    _logger.info('Fetching Client one local values...');
    childIsolateSendPortMap[ClientId.client1]?.send('localValues');
    final clientOneValues =
        Map<String, String?>.from(await readFromIsolateQueue() as Map);
    _logger.finer('Client one values: $clientOneValues');

    _logger.info('Fetching Client two local values...');
    childIsolateSendPortMap[ClientId.client2]?.send('localValues');
    final clientTwoValues =
        Map<String, String?>.from(await readFromIsolateQueue() as Map);
    _logger.finer('Client two values: $clientTwoValues');

    // Fetch the server commit log (per-key [commitId, opSymbol]).
    _logger.info('Fetching Server commitLog...');
    var serverCommitLog = await _getServerCommitEntries(uniqueId);
    _logger.finer('Server commit log: $serverCommitLog');

    var testResult = assertConvergence(
        atKeyEntityList, serverCommitLog, clientOneValues, clientTwoValues);
    expect(testResult, true);
  });

  // Kill the isolates at the end of the test
  tearDown(() {
    clientOneIsolate.kill();
    clientTwoIsolate.kill();
    // Remove the hive boxes
    var client1 = Directory(clientOneHiveKeyStorePath);
    if (client1.existsSync()) {
      client1.deleteSync(recursive: true);
    }
    var client2 = Directory(clientTwoHiveKeyStorePath);
    if (client2.existsSync()) {
      client2.deleteSync(recursive: true);
    }
  });
}

/// Reads the message from [isolateResponseQueue] and returns
/// Waits for maximum of 1 minute and throws TimeoutException if response is not received
Future<dynamic> readFromIsolateQueue() async {
  dynamic response;
  for (int i = 0; i < 600; i++) {
    _logger.finer('Polling for message');
    if (isolateResponseQueue.isNotEmpty) {
      response = isolateResponseQueue.removeFirst();
      _logger.finer('Found message: $response');
      isolateResponseQueue.clear();
      return response;
    }
    await Future.delayed(Duration(milliseconds: 100));
  }
  if (response == null) {
    throw AtTimeoutException('No response received from isolate');
  }
}

/// Main Isolate listener
void mainIsolateMessageListener(dynamic data) {
  if (data is IsolateAtClientResponse) {
    _mainIsolateLogger.info('RCVD ${data.type} message from ${data.clientId}');
    _mainIsolateLogger.finer('\tMessage: ${data.message}');
    if (data.message is String && data.message == 'completed') {
      if (data.clientId == ClientId.client1) {
        clientOneAck.complete();
      } else if (data.clientId == ClientId.client2) {
        clientTwoAck.complete();
      }
    } else if (data.message is SendPort) {
      childIsolateSendPortMap[data.clientId] = data.message;
    } else {
      _mainIsolateLogger.finer('Adding message to queue: ${data.message}');
      isolateResponseQueue.add(data.message);
    }
  }
}

Future<void> childIsolate(ChildIsolatePreferences clientParameters) async {
  AtSignLogger.defaultLoggingHandler = AtSignLogger.stdErrLoggingHandler;
  AtSignLogger.root_level = 'warning';
  int numberOfRepetitions = N;
  int counter = 0;
  var random = Random();

  var clientReceivePort = ReceivePort(clientParameters.clientId.name);
  // Send isolate's sendPort to mainIsolate for communication
  clientParameters.sendPort.send(IsolateAtClientResponse(
      clientParameters.clientId, 'SendPort', clientReceivePort.sendPort));

  // Child isolate listener
  clientReceivePort.listen((message) async {
    _childIsolateLogger
        .info('${clientParameters.clientId}: RCVD from MainIsolate: $message');
    if (message is String) {
      switch (message) {
        case 'localValues':
          Map<String, String?> localValues = await _getLocalValues(
              clientParameters.localKeysList,
              clientId: clientParameters.clientId.name);
          _childIsolateLogger.finer(
              '${clientParameters.clientId}: SENT: LocalValues: $localValues');
          clientParameters.sendPort.send(IsolateAtClientResponse(
              clientParameters.clientId, 'LocalValues', localValues));
          break;

        case 'doOpsAndSync':
          // Execute Update/delete operations on the client
          _childIsolateLogger.info(
              '${clientParameters.clientId}: Will perform $numberOfRepetitions update or delete operations');

          for (counter = 0; counter < numberOfRepetitions; counter++) {
            AtKey atKey = (AtKey.self(
                    clientParameters.localKeysList[random.nextInt(N)],
                    namespace: namespace,
                    sharedBy: currentAtSign))
                .build();
            await updateOrDeleteKey(
              atKey,
              random.nextInt(3),
              clientId: clientParameters.clientId.name,
            );
            await Future.delayed(Duration(milliseconds: 1));
          }

          _childIsolateLogger.info(
              '${clientParameters.clientId}: $numberOfRepetitions operations complete');

          _childIsolateLogger.info('${clientParameters.clientId}: Syncing');
          await FunctionalTestSyncService.getInstance()
              .syncData(label: clientParameters.clientId.toString());
          _childIsolateLogger.info(
              '${clientParameters.clientId}: Sync completed. Sending ACK to main isolate');

          clientParameters.sendPort.send(IsolateAtClientResponse(
              clientParameters.clientId, 'completed', 'completed'));
          break;

        case 'doSync':
          _childIsolateLogger.info('${clientParameters.clientId}: Syncing');
          await FunctionalTestSyncService.getInstance()
              .syncData(label: clientParameters.clientId.toString());
          _childIsolateLogger.info(
              '${clientParameters.clientId}: Sync completed. Sending ACK to main isolate');
          clientParameters.sendPort.send(IsolateAtClientResponse(
              clientParameters.clientId, 'completed', 'completed'));
          break;

        default:
          _childIsolateLogger
              .shout('UNRECOGNIZED REQUEST FROM MAIN ISOLATE: $message');
      }
    }
  });

  // Initializes the AtClient Instance
  await startClient(clientParameters);

  clientParameters.sendPort.send(IsolateAtClientResponse(
      clientParameters.clientId, 'completed', 'completed'));
}

Future<void> startClient(ChildIsolatePreferences clientParameters) async {
  var atClientPreferences = _getAtClientPreference(
      currentAtSign, clientParameters.clientId.name,
      hiveStoragePath: clientParameters.hiveStoragePath,
      commitLogPath: clientParameters.commitLogPath);
  atClientManager = await TestUtils.initAtClient(currentAtSign, namespace,
      preference: atClientPreferences);
}

Future<void> updateOrDeleteKey(AtKey atKey, int randomValueForOperation,
    {String clientId = ''}) async {
  switch (randomValueForOperation) {
    case 1:
      _logger.finer('($clientId) Key to delete: ${atKey.toString()}');
      await atClientManager.atClient.delete(atKey);
      break;
    case 2:
    default:
      _logger.finer('($clientId) Key to update: ${atKey.toString()}');
      await atClientManager.atClient
          .put(atKey, '${clientId.hashCode}-${atKey.hashCode}');
      break;
  }
}

Future<dynamic> _getServerCommitEntries(String regex) async {
  AtChopsKeys atChopsKeys = AtChopsKeys.create(
      AtEncryptionKeyPair.create(
          demo_credentials.encryptionPublicKeyMap[currentAtSign]!,
          demo_credentials.encryptionPrivateKeyMap[currentAtSign]!),
      AtPkamKeyPair.create(demo_credentials.pkamPublicKeyMap[currentAtSign]!,
          demo_credentials.pkamPrivateKeyMap[currentAtSign]!));

  AtChops atChops = AtChopsImpl(atChopsKeys);
  atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign,
      namespace,
      AtClientPreference()
        ..privateKey = demo_credentials.pkamPrivateKeyMap[currentAtSign]
        ..isLocalStoreRequired = false
        ..rootDomain = 'vip.ve.atsign.zone',
      atChops: atChops);
  var infoResponse = await atClientManager.atClient
      .getRemoteSecondary()
      ?.executeCommand('info:brief\n');
  infoResponse = infoResponse?.replaceAll('data:', '');
  var serverVersion = await jsonDecode(infoResponse!)['version'];
  if (Version.parse(serverVersion.split('+')[0]) >= Version(3, 0, 32)) {
    var serverCommitLogResponse = await atClientManager.atClient
        .getRemoteSecondary()
        ?.executeCommand('stats:15:$regex\n', auth: true);
    var serverCommitLogMap = jsonDecode(
        jsonDecode(serverCommitLogResponse!.replaceAll('data:', ''))[0]
            ['value']);
    return serverCommitLogMap;
  }
}

// Commit-log-free convergence: read each test key's DECRYPTED value from
// the client's local store (the raw keystore holds ciphertext that
// differs per write because every put generates a fresh IV, so it can't
// be compared across clients — `atClient.get` decrypts with the shared
// self key). Keyed by the short key-name (the [atKeyList] entry); `null`
// means the key is absent / deleted locally.
Future<Map<String, String?>> _getLocalValues(List<String> atKeyList,
    {String clientId = ''}) async {
  final values = <String, String?>{};
  for (final keyName in atKeyList) {
    final atKey =
        AtKey.self(keyName, namespace: namespace, sharedBy: currentAtSign)
            .build();
    try {
      final atValue = await atClientManager.atClient.get(atKey);
      values[keyName] = atValue.value;
    } on Exception {
      // KeyNotFoundException / AtKeyNotFoundException → absent / deleted.
      values[keyName] = null;
    }
  }
  _logger.finer('($clientId) Client values: $values');
  return values;
}

/// Convergence proof for the commit-log-free clients:
///
/// 1. **Value convergence** — both clients ended with the same value for
///    every test key (or both have it absent). Since each client pulls its
///    final state from the same server, identical local state means they
///    converged. The update value is opaque (a deterministic
///    `clientId-atKey` string); only equality matters.
/// 2. **Server agreement** — the presence/absence of each key on the
///    clients matches the server's final state, derived from its commit
///    log (`serverCommitLogMap[fullKey] == [commitId, opSymbol]`; a `-`
///    op means the key's last write was a delete, so it's absent).
bool assertConvergence(
    List<String> atKeyList,
    serverCommitLogMap,
    Map<String, String?> clientOneValues,
    Map<String, String?> clientTwoValues) {
  // Short key-names the server reports as present (final op is not delete).
  final serverPresent = <String>{};
  (serverCommitLogMap as Map).forEach((fullKey, entry) {
    final shortKey = AtKey.fromString(fullKey as String).key;
    if (!atKeyList.contains(shortKey)) return;
    final opSymbol = (entry as List)[1];
    if (opSymbol != '-') serverPresent.add(shortKey);
  });

  var converged = true;
  for (final keyName in atKeyList) {
    final c1 = clientOneValues[keyName];
    final c2 = clientTwoValues[keyName];
    if (c1 != c2) {
      _logger.severe('Value divergence for $keyName: client1=$c1 client2=$c2');
      converged = false;
      continue;
    }
    final clientHas = c1 != null;
    final serverHas = serverPresent.contains(keyName);
    if (clientHas != serverHas) {
      _logger.severe('Presence mismatch for $keyName: '
          'clients=${clientHas ? "present" : "absent"} '
          'server=${serverHas ? "present" : "absent"}');
      converged = false;
    }
  }
  return converged;
}

AtClientPreference _getAtClientPreference(String currentAtSign, String clientId,
    {required String hiveStoragePath, required String commitLogPath}) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = hiveStoragePath;
  preference.commitLogPath = commitLogPath;
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[currentAtSign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  preference.atClientParticulars = AtClientParticulars()
    ..appName = 'wavi_$clientId'
    ..appVersion = '3.0.2'
    ..platform = 'android';
  return preference;
}
