// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file, so the annotation has nothing to tell us here.
// ignore_for_file: experimental_member_use

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The secret-sharing substrate against a live atServer, same-atSign.
///
/// Until this file existed the substrate had **no live coverage at all** —
/// every claim about it rested on a unit fixture that backs local storage and
/// the atServer with a single map. That fixture cannot tell a local-first
/// write from a remote-first one, which is how an ordering defect reached the
/// branch: the envelope was written local-first while its wake-up
/// notification went straight out remote, so the nudge could arrive before
/// the value it pointed at.
///
/// Both tests here deliberately run with the wake-up **off**. That isolates
/// the two properties worth proving on a real wire: that the envelope is on
/// the atServer by the time `sendEnvelope` returns, and that a client which
/// has never synced can still fetch and decrypt it.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    atClient = manager.atClient;
  });

  /// Two independently-constructed instances over one client: same atSign and
  /// same APKAM signing key, but each generates its own X-Wing keypair, so
  /// they have distinct kpids — which is all that envelope addressing turns
  /// on. `forClient` deliberately caches one instance per AtClient, so the
  /// plain constructor is the documented way to get a second identity.
  Future<AtClientSecretSharing> newParty() async {
    final party = AtClientSecretSharing(atClient)
      ..sendWakeUpNotification = false;
    await party.register();
    return party;
  }

  test('the envelope is on the atServer by the time sendEnvelope returns',
      () async {
    final sender = await newParty();
    final recipient = await newParty();

    await sender.sendEnvelope(recipient.myKeyPackage, namespace, {'n': 1});

    // No sync in between, deliberately: a local-first write would still be
    // sitting on this device at this point, and a recipient woken by the
    // notification would read an atServer that does not hold it yet.
    final remote = await atClient.getAtKeys(
        regex: '.*\\.${recipient.kpid}\\.__ssenv\\..*',
        useRemoteAtServer: true);

    expect(remote, hasLength(1),
        reason: 'sendEnvelope writes remote-first precisely so that anything '
            'the wake-up reaches can find the envelope already there');
  });

  test(
      'a client that has never synced fetches and decrypts it from the '
      'atServer', () async {
    final sender = await newParty();
    final recipient = await newParty();

    final received = <ReceivedEnvelope>[];
    // Listener before trigger: receivedEnvelopes is a broadcast stream and
    // does not replay what it emitted before subscription.
    final sub = recipient.receivedEnvelopes.listen(received.add);
    addTearDown(sub.cancel);

    await sender.sendEnvelope(recipient.myKeyPackage, namespace, {'hi': 'bob'});

    // The lazy-fetch path: no wake-up fired and nothing synced this envelope
    // into local storage, so a local sweep could not see it. This is what a
    // sync-less client does — automatically, once clientRunsSync is false.
    final consumed = await recipient.sweepOnce(fromRemote: true);

    expect(consumed, 1);
    expect(received, hasLength(1));
    expect(received.single.payload, {'hi': 'bob'});
    expect(received.single.fromKpid, sender.kpid,
        reason: 'the envelope carries its sender, verified against the '
            'publishing enrollment signing key before it is decrypted');

    // A consumed envelope is deleted where it was read from, so the same
    // payload cannot be delivered twice.
    final remaining = await atClient.getAtKeys(
        regex: '.*\\.${recipient.kpid}\\.__ssenv\\..*',
        useRemoteAtServer: true);
    expect(remaining, isEmpty);
  });
}
