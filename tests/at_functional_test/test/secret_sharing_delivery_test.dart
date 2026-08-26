// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file, so the annotation has nothing to tell us here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert' show base64Decode, jsonDecode;

import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
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
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
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

  test('the negotiated construction is what actually reaches the atServer',
      () async {
    // The unit suite proves the negotiation picks RFC 9180 for a peer that
    // advertises it and falls back for one that does not. What it cannot show
    // is that the chosen version is the one on the wire — its fixture backs
    // local and remote with a single map. Read the envelope back off the
    // atServer and look at the byte.
    final sender = await newParty();
    final recipient = await newParty();

    await sender.sendEnvelope(recipient.myKeyPackage, namespace, {'n': 1});

    final remote = await atClient.getAtKeys(
        regex: '.*\\.${recipient.kpid}\\.__ssenv\\..*',
        useRemoteAtServer: true);
    final value = await atClient.get(remote.single,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    final payload = (SignedEnvelope.fromJson(
                jsonDecode(value.value as String) as Map)
            .payload as Map)
        .cast<String, dynamic>();

    expect(payload['suite'], SecretSharingAlgos.xWingRfc9180,
        reason: 'both parties are this build, so both advertise the RFC 9180 '
            'suite and the negotiation must settle on it');
    expect(base64Decode(payload['sealed'] as String).first, 0x02,
        reason: 'and the declared suite must agree with the version byte the '
            'recipient will dispatch on — a mismatch opens as an AEAD '
            'failure that names neither side');
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
