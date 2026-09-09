// The substrate this file exercises is @experimental.
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
/// A unit fixture backing local storage and the atServer with a single map
/// cannot tell a local-first write from a remote-first one, and that ordering
/// is what these tests are for: an envelope written local-first while its
/// wake-up notification goes straight out remote leaves the nudge racing the
/// value it points at.
///
/// Every party here is built with the wake-up **off**, which isolates what is
/// worth proving on a real wire: that the envelope is on the atServer by the
/// time `sendEnvelope` returns, that the negotiated construction is the one
/// stored, and that a client which has never synced can fetch and decrypt it.
void main() {
  TestUtils.isolateStorage('secret_sharing_delivery_test');
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    atClient = manager.atClient;
  });

  /// A further secret-sharing identity over one client: same atSign and same
  /// APKAM signing key, but its own X-Wing keypair and so its own kpid, which
  /// is all that envelope addressing turns on. `forClient` caches one instance
  /// per AtClient, so the plain constructor is the way to get another.
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
    // A fixture backing local and remote with a single map cannot show that
    // the negotiated version is the one on the wire, so read the envelope back
    // off the atServer and look at the byte.
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
