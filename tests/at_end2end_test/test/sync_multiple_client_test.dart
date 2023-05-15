import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/util/logger_util.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/at_credentials.dart';
import 'package:at_end2end_test/src/at_encryption_key_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:at_client/at_client.dart';

/// The purpose of this test is to run multiple clients in Isolate and inject
/// bulk data.
/// Finally assert the commitId and commitOp. between server and both the clients.
enum ClientId { client1, client2 }

class ChildIsolatePreferences {
  late ClientId clientId;
  late String hiveStoragePath;
  late String commitLogPath;
  late SendPort sendPort;
}

class IsolateAtClientResponse {
  ClientId clientId;
  dynamic message;

  IsolateAtClientResponse(this.clientId, this.message);

  @override
  String toString() {
    return 'clientId: ${clientId.name}  Message: ${message.toString()}';
  }
}

late AtClientManager atClientManager;

var currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
var sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
String namespace = 'wavi';
// A global variable to pause the execution of test until sync is completed.
// The variable will be used within the child isolates.
bool isSyncCompleted = false;
final _logger = AtSignLogger('Sync System Test');

List<String> atKeyEntity = [
  'country',
  'phone',
  'location',
  'worknumber',
  'city'
];

var isolateResponseQueue = Queue();

var childIsolateSendPortMap = <ClientId, SendPort>{};
bool isClientOneCompleted = false;
bool isClientTwoCompleted = false;

void main() async {
  AtSignLogger.root_level = 'finest';
  var mainIsolateReceivePort = ReceivePort('MainIsolateReceivePort');
  SyncServiceImpl.syncRequestThreshold = 1;
  SyncServiceImpl.syncRequestTriggerInSeconds = 1;
  SyncServiceImpl.syncRunIntervalSeconds = 1;
  SyncServiceImpl.queueSize = 1;

  var clientInitializationParameters = {
    'client1': ChildIsolatePreferences()
      ..clientId = ClientId.client1
      ..hiveStoragePath = 'test/hive/client'
      ..commitLogPath = 'test/hive/client/commit'
      ..sendPort = mainIsolateReceivePort.sendPort,
    'client2': ChildIsolatePreferences()
      ..clientId = ClientId.client2
      ..hiveStoragePath = 'test/hive/client2'
      ..commitLogPath = 'test/hive/client2/commit'
      ..sendPort = mainIsolateReceivePort.sendPort
  };

  test('A test to verify the commit log entries', () async {
    // Spawn isolate for client-1
    await Isolate.spawn(
        childIsolate, clientInitializationParameters['client1']!,
        debugName: clientInitializationParameters['client1']!.clientId.name);
    // Spawn isolate for client-2
    await Isolate.spawn(
        childIsolate, clientInitializationParameters['client2']!,
        debugName: clientInitializationParameters['client2']!.clientId.name);
    // Add listener for main isolate to receive messages from child isolates
    mainIsolateReceivePort.listen(mainIsolateMessageListener);

    // Wait until both the client's complete execution
    while (isClientOneCompleted == false || isClientTwoCompleted == false) {
      _logger.info(
          'Waiting for all client to complete: Client1: $isClientOneCompleted, Client2: $isClientTwoCompleted');
      await Future.delayed(Duration(seconds: 10));
    }
    _logger
        .info('Completion status of clients before requesting for commit log:'
            ' Client1 Complete: $isClientOneCompleted'
            ' Client2 Complete: $isClientTwoCompleted');

    //Call to sync after update/delete is completed on both the clients.
    childIsolateSendPortMap[ClientId.client1]?.send('finalSync');
    childIsolateSendPortMap[ClientId.client2]?.send('finalSync');

    isClientOneCompleted = false;
    isClientTwoCompleted = false;
    // Wait until both the client's complete execution
    while (isClientOneCompleted == false || isClientTwoCompleted == false) {
      _logger.info(
          'Waiting for additional sync call to complete: Client1: $isClientOneCompleted, Client2: $isClientTwoCompleted');
      await Future.delayed(Duration(seconds: 10));
    }

    // NOTE: Do not fetch local commit until all the client have finished sync process
    // Fetch client-1 commit log
    _logger.info('Fetching Client one commitLog...');
    childIsolateSendPortMap[ClientId.client1]?.send('localCommitLog');
    var clientOneCommitLog = await readFromIsolateQueue();
    _logger.info('Client one commitLog: $clientOneCommitLog');

    // Fetch client-2 commit log
    _logger.info('Fetching Client two commitLog...');
    childIsolateSendPortMap[ClientId.client2]?.send('localCommitLog');
    var clientTwoCommitLog = await readFromIsolateQueue();
    _logger.info('Client two commitLog: $clientTwoCommitLog');

    // Fetch the server commit log.
    _logger.info('Fetching Server commitLog...');
    var serverCommitLog = await _getServerCommitEntries();
    _logger.info('Server commit log: $serverCommitLog');

    var testResult = assertCommitEntries(
        serverCommitLog, clientOneCommitLog, clientTwoCommitLog);
    expect(testResult, true);
  },
      skip:
          'The test needs changes in at_server. Skipping this test until server changes are merged');
}

/// Reads the message from [isolateResponseQueue] and returns
/// Waits for maximum of 1 minute and throws TimeoutException if response is not received
Future<dynamic> readFromIsolateQueue() async {
  dynamic response;
  for (int i = 0; i < 600; i++) {
    _logger.info('Polling for message');
    if (isolateResponseQueue.isNotEmpty) {
      response = isolateResponseQueue.removeFirst();
      _logger.info('Found message: $response');
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
void mainIsolateMessageListener(data) {
  if (data is IsolateAtClientResponse) {
    _logger.info('${data.clientId} RCVD message: ${data.message}');
    if (data.message is String && data.message == 'completed') {
      if (data.clientId == ClientId.client1) {
        isClientOneCompleted = true;
      } else if (data.clientId == ClientId.client2) {
        isClientTwoCompleted = true;
      }
    } else if (data.message is SendPort) {
      childIsolateSendPortMap[data.clientId] = data.message;
    } else {
      _logger.finer('Adding message to queue: ${data.message}');
      isolateResponseQueue.add(data.message);
    }
  }
}

Future<void> childIsolate(ChildIsolatePreferences clientParameters) async {
  AtSignLogger.root_level = 'finer';
  int numberOfRepetitions = 5;
  int counter = 0;
  var random = Random();
  var clientReceivePort = ReceivePort(clientParameters.clientId.name);
  // Send isolate's sendPort to mainIsolate for communication
  clientParameters.sendPort.send(IsolateAtClientResponse(
      clientParameters.clientId, clientReceivePort.sendPort));

  // Child isolate listener
  clientReceivePort.listen((message) async {
    _logger
        .info('${clientParameters.clientId}: RCVD from main isolate: $message');
    if (message is String && message == 'localCommitLog') {
      Map<String, Map<String, dynamic>> localCommitLogMap =
          await _getLocalCommitEntries(
              clientId: clientParameters.clientId.name);
      _logger.info(
          '${clientParameters.clientId}SENT: LocalCommitLog: $localCommitLogMap');
      clientParameters.sendPort.send(IsolateAtClientResponse(
          clientParameters.clientId, localCommitLogMap));
    }
    // Adding an additional call to sync after both the client complete update/delete
    if (message is String && message == 'finalSync') {
      await waitForSyncToComplete(clientId: clientParameters.clientId.name);
      _logger.info(
          '${clientParameters.clientId}: Additional Final sync completed. Sending ACK to main isolate');
      clientParameters.sendPort.send(
          IsolateAtClientResponse(clientParameters.clientId, 'completed'));
    }
  });

  // Initializes the AtClient Instance
  await startClient(clientParameters);

  _logger.info('${clientParameters.clientId}: Starting initial sync');
  await waitForSyncToComplete(clientId: clientParameters.clientId.name);
  _logger.info(
      '${clientParameters.clientId}: Initial sync completed successfully');

  // Execute Update/delete operation on the client
  for (counter = 0; counter < numberOfRepetitions; counter++) {
    _logger.info('(${clientParameters.clientId}) Counter: $counter');
    await updateDeleteKey(random.nextInt(3), random.nextInt(5),
        clientId: clientParameters.clientId.name);
    await Future.delayed(Duration(milliseconds: 100));
  }

  // Wait until sync is completed. Since bulk of keys are being inserted,
  // SyncProgress will be triggered intermittently when a batch is
  // completed. So adding an additional check to wait until counter
  // is less than "numberOfRepetitions"
  while (!isSyncCompleted || counter < numberOfRepetitions) {
    _logger.info(
        '(${clientParameters.clientId}) SyncCompletedStatus: $isSyncCompleted, Counter: $counter');
    atClientManager.atClient.syncService.sync();
    await Future.delayed(Duration(seconds: 1));
  }

  _logger.info('${clientParameters.clientId}: Starting final sync');
  await waitForSyncToComplete(clientId: clientParameters.clientId.name);
  _logger.info(
      '${clientParameters.clientId}: Final sync completed. Sending ACK to main isolate');
  clientParameters.sendPort
      .send(IsolateAtClientResponse(clientParameters.clientId, 'completed'));
}

Future<void> startClient(ChildIsolatePreferences clientParameters) async {
  atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign,
      namespace,
      _getAtClientPreference(currentAtSign,
          hiveStoragePath: clientParameters.hiveStoragePath,
          commitLogPath: clientParameters.commitLogPath));
  await AtEncryptionKeysLoader.getInstance()
      .setEncryptionKeys(atClientManager.atClient, currentAtSign);
  MySyncProgressListener mySyncProgressListener = MySyncProgressListener();
  atClientManager.atClient.syncService
      .addProgressListener(mySyncProgressListener);
}

Future<void> waitForSyncToComplete({String clientId = ''}) async {
  if ((await atClientManager.atClient.syncService.isInSync())) {
    _logger.info(_logger.getLogMessageWithClientParticulars(
        atClientManager.atClient.getPreferences()!.atClientParticulars,
        '($clientId)|Client and Server are in Sync'));
    return;
  }
  isSyncCompleted = false;
  _logger.info(_logger.getLogMessageWithClientParticulars(
      atClientManager.atClient.getPreferences()!.atClientParticulars,
      '($clientId): Client and Server are not in Sync... Initializing sync process'));
  atClientManager.atClient.syncService.sync();
  while (!isSyncCompleted) {
    _logger.finer(_logger.getLogMessageWithClientParticulars(
        atClientManager.atClient.getPreferences()!.atClientParticulars,
        '($clientId) SyncCompletedStatus: $isSyncCompleted'));
    atClientManager.atClient.syncService.sync();
    await Future.delayed(Duration(seconds: 1));
  }
  _logger.info(_logger.getLogMessageWithClientParticulars(
      atClientManager.atClient.getPreferences()!.atClientParticulars,
      '($clientId) Sync Completed Successfully'));
  // Resetting back to false for future use
  isSyncCompleted = false;
  await Future.delayed(Duration(seconds: 60));
}

Future<void> updateDeleteKey(int randomValueForOperation, int randomValueForKey,
    {String clientId = ''}) async {
  switch (randomValueForOperation) {
    case 1:
      _logger
          .info('($clientId) Key to delete: ${atKeyEntity[randomValueForKey]}');
      await atClientManager.atClient.delete((AtKey.shared(
              atKeyEntity[randomValueForKey],
              namespace: namespace,
              sharedBy: currentAtSign)
            ..sharedWith(sharedWithAtSign))
          .build());
      break;
    case 2:
    default:
      _logger
          .info('($clientId) Key to update: ${atKeyEntity[randomValueForKey]}');
      await atClientManager.atClient.put(
          (AtKey.shared(atKeyEntity[randomValueForKey],
                  namespace: namespace, sharedBy: currentAtSign)
                ..sharedWith(sharedWithAtSign))
              .build(),
          randomValueForKey.toString());
      break;
  }
}

Future<dynamic> _getServerCommitEntries() async {
  atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign,
      namespace,
      AtClientPreference()
        ..privateKey = AtCredentials
            .credentialsMap[currentAtSign]![TestConstants.PKAM_PRIVATE_KEY]
        ..isLocalStoreRequired = false
        ..rootDomain = ConfigUtil.getYaml()['root_server']['url']);
  var serverCommitLogResponse = await atClientManager.atClient
      .getRemoteSecondary()
      ?.executeCommand('stats:15\n', auth: true);
  var serverCommitLogMap = jsonDecode(
      jsonDecode(serverCommitLogResponse!.replaceAll('data:', ''))[0]['value']);
  return serverCommitLogMap;
}

Future<Map<String, Map<String, dynamic>>> _getLocalCommitEntries(
    {String clientId = ''}) async {
  var commitLog =
      await AtCommitLogManagerImpl.getInstance().getCommitLog(currentAtSign);
  var commitLogEntriesMap = <String, Map<String, dynamic>>{};

  for (MapEntry<int, CommitEntry> mapEntry
      in (await commitLog?.commitLogKeyStore.toMap())!.entries) {
    if (mapEntry.value.commitId == null) {
      continue;
    }
    if (atKeyEntity.contains(AtKey.fromString(mapEntry.value.atKey!).key)) {
      _logger.finest(
          '($clientId) Commit-Entry from local: Key: ${mapEntry.value.atKey!}, CommitId: ${mapEntry.value.commitId!}, CommitOp. ${mapEntry.value.operation.toString()}');
      if (commitLogEntriesMap.containsKey(mapEntry.value.atKey) &&
          (commitLogEntriesMap[mapEntry.value.atKey]!['commitId'] >
              mapEntry.value.commitId!)) {
        _logger.finest(
            '($clientId) Key: ${mapEntry.value.atKey} Existing CommitId ${commitLogEntriesMap[mapEntry.value.atKey]!['commitId']} is greater than new commitId: ${mapEntry.value.commitId!}. Not updating the localCommitId Map');
        continue;
      }
      commitLogEntriesMap[mapEntry.value.atKey!] = {
        'commitId': mapEntry.value.commitId!,
        'commitOp': mapEntry.value.operation.toString()
      };
    }
  }
  _logger.info('($clientId) Client CommitEntries: $commitLogEntriesMap');
  return commitLogEntriesMap;
}

bool assertCommitEntries(
    serverCommitLogMap,
    Map<String, Map<String, dynamic>> clientOneCommitLog,
    Map<String, Map<String, dynamic>> clientTwoCommitLog) {
  for (MapEntry<String, Map<String, dynamic>> mapEntry
      in clientOneCommitLog.entries) {
    if (!(atKeyEntity.contains(AtKey.fromString(mapEntry.key).key))) {
      continue;
    }
    // Compare server commit id with both client's commit log
    if ((serverCommitLogMap[mapEntry.key][0] != mapEntry.value['commitId']) ||
        (serverCommitLogMap[mapEntry.key][0] !=
            clientTwoCommitLog[mapEntry.key]!['commitId'])) {
      _logger.severe('Assertion failed: Key: ${mapEntry.key} '
          'Server CommitId: ${serverCommitLogMap[mapEntry.key][0]} '
          'Client-One CommitId: ${mapEntry.value['commitId']} '
          'Client-Two CommitId: ${clientTwoCommitLog[mapEntry.key]!['commitId']}');
      return false;
    }
  }
  return true;
}

class MySyncProgressListener extends SyncProgressListener {
  @override
  Future<void> onSyncProgressEvent(SyncProgress syncProgress) async {
    if (syncProgress.syncStatus == SyncStatus.success) {
      _logger.info(_logger.getLogMessageWithClientParticulars(
          atClientManager.atClient.getPreferences()!.atClientParticulars,
          'SyncProgress: $syncProgress'));
      // Setting isSyncCompleted to true to mark sync is completed and break the loop
      // in waitForSyncToComplete method
      isSyncCompleted = await atClientManager.atClient.syncService.isInSync();
      _logger.info(_logger.getLogMessageWithClientParticulars(
          atClientManager.atClient.getPreferences()!.atClientParticulars,
          'IsInSync from sync progress listener: $isSyncCompleted'));
    }
  }
}

AtClientPreference _getAtClientPreference(String currentAtSign,
    {required String hiveStoragePath, required String commitLogPath}) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = hiveStoragePath;
  preference.commitLogPath = commitLogPath;
  preference.isLocalStoreRequired = true;
  preference.privateKey = AtCredentials
      .credentialsMap[currentAtSign]![TestConstants.PKAM_PRIVATE_KEY];
  preference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
  preference.atClientParticulars = AtClientParticulars()
    ..appName = 'wavi'
    ..appVersion = '3.0.2'
    ..platform = 'android';
  return preference;
}
