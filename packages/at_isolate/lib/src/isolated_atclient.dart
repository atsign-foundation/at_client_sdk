import 'dart:async' show Completer;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';

// ignore: implementation_imports
import 'package:at_client/src/response/response.dart' show AtResponse;
import 'package:at_isolate/src/atclient/split_stream.dart' show takeFromStream;
import 'package:mutex/mutex.dart' show Mutex;
import 'dart:isolate' show ReceivePort, SendPort, RawReceivePort, Isolate;

// ignore: implementation_imports
import 'package:at_client/src/service/encryption_service.dart';
// ignore: implementation_imports
import 'package:at_client/src/stream/at_stream_response.dart';
// ignore: implementation_imports
import 'package:at_client/src/stream/file_transfer_object.dart';
// ignore: implementation_imports
import 'package:at_client/src/manager/sync_manager.dart';

export 'package:at_client/at_client.dart';

part 'atclient/isolate.dart';
part 'atclient/request.dart';
part 'atclient/response.dart';
part 'atclient/worker.dart';

/// An [AtClient] implementation that runs in a separate isolate.
///
/// [IsolatedAtClient] wraps a standard [AtClient] and runs it in a dedicated
/// isolate, communicating via message passing. This provides isolation and
/// prevents blocking the main isolate during AtClient operations.
///
/// ## Usage
///
/// ```dart
/// final preference = AtClientPreference()
///   ..isLocalStoreRequired = false
///   ..namespace = 'myapp';
///
/// final client = await IsolatedAtClient.spawn(
///   Atsign('@alice'),
///   AtRootDomain.atsignDomain,
///   atKeys,
///   preference,
/// );
///
/// // Use like a normal AtClient
/// await client.put(key, value);
/// final result = await client.get(key);
///
/// // Clean up when done
/// client.close();
/// ```
///
/// ## Thread Safety
///
/// Operations are serialized using a mutex to ensure thread-safe access
/// across the isolate boundary. Multiple operations can be called concurrently
/// and they will be queued and executed in order.
///
/// ## Limitations
///
/// The following AtClient members are not implemented:
/// - Deprecated methods (notify, notifyChange, startMonitor, etc.)
/// - Service getters (syncService, notificationService, etc.)
/// - Configuration methods (setPreferences, getPreferences)
///
/// These throw [UnimplementedError] if called.
abstract class IsolatedAtClient implements AtClient {
  /// Spawns a new [IsolatedAtClient] in a separate isolate.
  ///
  /// Creates a new isolate, authenticates with the specified [atSign],
  /// [root] domain, and [atKeys], and returns an [IsolatedAtClient]
  /// instance for communicating with it.
  ///
  /// The [preference] parameter configures the AtClient behavior including
  /// namespace, local storage requirements, and other settings.
  ///
  /// Throws an exception if authentication fails or the isolate
  /// cannot be spawned.
  ///
  /// Example:
  /// ```dart
  /// final preference = AtClientPreference()
  ///   ..namespace = 'myapp'
  ///   ..isLocalStoreRequired = true
  ///   ..hiveStoragePath = '/tmp/myapp/storage'
  ///   ..commitLogPath = '/tmp/myapp/commit';
  ///
  /// final client = await IsolatedAtClient.spawn(
  ///   Atsign('@alice'),
  ///   AtRootDomain.atsignDomain,
  ///   atKeys,
  ///   preference,
  /// );
  /// ```
  static Future<IsolatedAtClient> spawn(Atsign atSign, AtRootDomain root,
      AtKeys atKeys, AtClientPreference preference) async {
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ));
    };

    try {
      await Isolate.spawn(AtClientWorker.main, (initPort.sendPort));
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort receivePort, SendPort sendPort) =
        await connection.future;
    Stream recvStream;
    void Function() closeRecv;
    try {
      sendPort.send(atSign.str);
      sendPort.send(root.toString());
      sendPort.send(jsonEncode(atKeys.toJson()));
      // Send preference fields as a simple map
      sendPort.send({
        'namespace': preference.namespace,
        'isLocalStoreRequired': preference.isLocalStoreRequired,
        'hiveStoragePath': preference.hiveStoragePath,
        'commitLogPath': preference.commitLogPath,
        'rootDomain': preference.rootDomain,
        'rootPort': preference.rootPort,
      });
      List<Object?> taken;
      (taken, recvStream, closeRecv) = await takeFromStream(1, receivePort);
      if (taken.first is! bool || !(taken.first as bool)) {
        throw taken.first ?? "Received empty stream element";
      }
    } catch (e) {
      receivePort.close();
      rethrow;
    }
    return _IsolatedAtClient(
      recv: recvStream,
      closeRecv: () {
        receivePort.close();
        closeRecv();
      },
      send: sendPort,
      atSign: atSign,
    );
  }

  /// Closes the isolate and releases resources.
  ///
  /// After calling [close], this [IsolatedAtClient] instance should not
  /// be used for any further operations. The worker isolate will be terminated
  /// and all communication channels will be closed.
  void close();
}
