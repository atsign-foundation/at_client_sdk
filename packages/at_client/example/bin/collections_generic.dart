import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections - generic');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream
      .listen((s) => stdout.writeln('${DateTime.now()} | $s'));

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  AtCollection.registerFactory(type: 'Dog', factory: Dog.fromJson);
  AtCollection.registerFactory(type: 'Cat', factory: Cat.fromJson);
  final AtCollection generic = c.atClient.collection(
    'generic.$applicationNamespace',
    exampleDefaultExpiration,
  );

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
  generic.events.listen((CEvent e) {
    if (e is CReadReceipt) {
      progressSink.add('${e.runtimeType} :'
          ' Read Receipt from ${e.from} for ${e.id}');
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

  CItem itemToShare;

  progressSink.add('Creating some binary data, sharing with $otherAtSigns');
  itemToShare = generic.create(
    obj: Uint8List.fromList(
        'This is binary data from ${atClient.atSign}'.codeUnits),
    sharedWith: otherAtSigns,
  );
  for (final r in await generic.put(
    itemToShare,
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }
  expectedReceipts[itemToShare.id] = Set.from(otherAtSigns!);

  progressSink.add('Creating a Dog, sharing with $otherAtSigns');
  itemToShare = generic.create(
    type: 'Dog',
    obj: Dog(name: '${atClient.atSign}\'s dog Rex'),
    sharedWith: otherAtSigns,
  );
  for (final r in await generic.put(
    itemToShare,
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }
  expectedReceipts[itemToShare.id] = Set.from(otherAtSigns);

  progressSink.add('Creating a Cat, sharing with $otherAtSigns');
  itemToShare = generic.create(
      type: 'Cat',
      obj: Cat(name: '${atClient.atSign}\'s cat Felix'),
      sharedWith: otherAtSigns);
  for (final r in await generic.put(
    itemToShare,
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }
  expectedReceipts[itemToShare.id] = Set.from(otherAtSigns);

  progressSink.add('Creating a Map, sharing with $otherAtSigns');
  itemToShare = generic.create(
    obj: {'isMap': true, 'name': 'my map', 'intValue': 123},
    sharedWith: otherAtSigns,
  );
  for (final r in await generic.put(
    itemToShare,
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }
  expectedReceipts[itemToShare.id] = Set.from(otherAtSigns);

  progressSink.add('Creating a String, sharing with $otherAtSigns');
  itemToShare = generic.create(
    obj: 'this is just a String',
    sharedWith: otherAtSigns,
  );
  for (final r in await generic.put(
    itemToShare,
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }
  expectedReceipts[itemToShare.id] = Set.from(otherAtSigns);

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

  Future<void> sendReadReceipt(CItem item) async {
    if (await generic.sentReadReceipt(item)) {
      return;
    }
    progressSink.add('Sending read receipt for $item');
    bool sent = await generic.sendReadReceipt(item);
    if (sent) {
      actual++;
    }
    if (actual == expected) {
      allReceiptsSent.complete();
    }
  }

  // watch for new collection events
  generic.events.listen((CEvent e) async {
    switch (e) {
      case CItemUpdated():
        try {
          final item = await generic.get(e.id, e.owner);
          await sendReadReceipt(item);
        } catch (_) {
          return;
        }
      default:
        break;
    }
  });

  progressSink.add('${DateTime.now().toString()} : Fetching');

  for (final item in await generic.getItemsList()) {
    String msg = 'Fetched ${generic.prettyString(item)}';
    if (item.type == 'binary') {
      msg = '$msg : ${String.fromCharCodes(item.obj)}';
    }
    progressSink.add(msg);
    if (item.owner != generic.atSign) {
      await sendReadReceipt(item);
    }
  }

  await allReceiptsSent.future;
  progressSink.add('All read receipts sent');
}
