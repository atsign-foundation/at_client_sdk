import 'dart:async' show Completer;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AtChops;
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

abstract class IsolatedAtClient implements AtClient {
  static Future<IsolatedAtClient> spawn(
      Atsign atSign, AtRootDomain root, AtKeys atKeys) async {
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
      await Isolate.spawn(_AtClientWorker.main, (initPort.sendPort));
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

  void close();
}
