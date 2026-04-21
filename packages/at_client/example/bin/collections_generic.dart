import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections - generic');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream.listen(
    (s) => stdout.writeln('${DateTime.now()} | $s'),
  );

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final AtCollection generic =
      c.atClient.collection(
          'generic.$applicationNamespace',
          exampleDefaultExpiration,
        )
        ..registerFactory<Dog>(Dog.fromJson)
        ..registerFactory<Cat>(Cat.fromJson);

  switch (c.role) {
    case ExampleRole.sender:
      await sender(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        generic,
      );
      break;
    case ExampleRole.receiver:
      await receiver(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        generic,
      );
      break;
  }
  await Future.delayed(Duration(milliseconds: 100));

  exit(0);
}

Future<void> sender(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection generic,
) async {
  Map<String, Set<Atsign>> expectedReceipts = {};
  Completer allReceiptsReceived = Completer();
  generic.watch().listen((CEvent e) {
    if (e is CReadReceipt) {
      progressSink.add(
        '${e.runtimeType} :'
        ' Read Receipt from ${e.from} for ${e.id}',
      );
      expectedReceipts[e.id]?.remove(e.from);
      if (expectedReceipts[e.id]?.isEmpty ?? true) {
        expectedReceipts.remove(e.id);
      }
      if (expectedReceipts.isEmpty) {
        allReceiptsReceived.complete();
      }
    } else {
      progressSink.add(e.toString());
    }
  });

  Future<void> saveAndTrack(String label, Object obj) async {
    progressSink.add('Creating $label, sharing with $otherAtSigns');
    try {
      final item = await generic.create(obj: obj, sharedWith: otherAtSigns);
      progressSink.add('  ...saved.');
      expectedReceipts[item.id] = Set.from(otherAtSigns!);
    } on CollectionOpException catch (e) {
      for (final r in e.results) {
        progressSink.add(r.toString());
      }
    }
  }

  await saveAndTrack(
    'some binary data',
    Uint8List.fromList('This is binary data from ${atClient.atSign}'.codeUnits),
  );
  await saveAndTrack('a Dog', Dog(name: '${atClient.atSign}\'s dog Rex'));
  await saveAndTrack('a Cat', Cat(name: '${atClient.atSign}\'s cat Felix'));
  await saveAndTrack('a Map', {
    'isMap': true,
    'name': 'my map',
    'intValue': 123,
  });
  await saveAndTrack('a String', 'this is just a String');

  await allReceiptsReceived.future;
  progressSink.add('All read receipts received');
}

Future<void> receiver(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection generic,
) async {
  // We're expecting to receive 5 things; we will send read receipts for each;
  // once we've sent 5 read receipts, we're done

  int expected = 5;
  int actual = 0;
  Completer allReceiptsSent = Completer();

  Future<void> sendReadReceiptAndTrack(CItem item) async {
    if (await generic.hasSentReadReceipt(item)) return;
    progressSink.add('Sending read receipt for $item');
    await generic.sendReadReceipt(item);
    actual++;
    if (actual == expected) {
      allReceiptsSent.complete();
    }
  }

  // watch for incoming item updates and send a read receipt for each
  generic.updates.listen((e) async {
    try {
      final item = await generic.get(e.id, e.owner);
      await sendReadReceiptAndTrack(item);
    } catch (_) {
      return;
    }
  });

  progressSink.add('${DateTime.now().toString()} : Fetching');

  for (final item in await generic.getItems()) {
    String msg = 'Fetched ${generic.prettyString(item)}';
    if (item.type == 'binary') {
      msg = '$msg : ${String.fromCharCodes(item.obj)}';
    }
    progressSink.add(msg);
    if (item.owner != generic.atSign) {
      await sendReadReceiptAndTrack(item);
    }
  }

  await allReceiptsSent.future;
  progressSink.add('All read receipts sent');
}
