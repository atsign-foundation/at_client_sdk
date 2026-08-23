// The enrollment key-package surface is @experimental; driving it is how each
// cell gets an enrollment of its own.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show EnrolledClient, enrolAndAuthenticate;
import 'package:test/test.dart';

import 'test_utils.dart';

/// One client per `PqPosture`, stood up side by side against a live atServer.
///
/// A posture is applied at construction and cannot move on a live client, so
/// what a stage decides is only visible by building several clients and asking
/// each the same question. That is what this file is: three clients on one
/// atSign, one per stage, and the same write offered to each.
///
/// **Why three enrollments rather than three preferences.** `AtClientImpl`
/// keys its client cache by `(atSign, enrollmentId)` and refuses to hand a
/// cached client to a caller naming different rollout axes, because those axes
/// are final at construction — `AtClientImpl.refuseChangedRolloutAxes`. Three
/// postures therefore need three cache keys, and an enrollment each is how one
/// atSign supplies them.
///
/// **What only a live run shows.** The unit suite pins every value below
/// against a preference or a mock, and a mock never runs `AtClientImpl`'s
/// initialisation — so a posture that reached the constant and never reached
/// the client would pass all of them and this file would still fail. Here the
/// posture has to survive enrolment, authentication and client construction
/// before anything is asserted.
///
/// ⚠️ **The cells differ in the posture and in nothing else that is
/// deliberate, with one exception that is stated rather than hidden:** all
/// three enrollments are submitted in *pq* mode, because
/// [enrolAndAuthenticate] builds only that kind. So the `keyExchangeMode` axis
/// is held constant across the cells and is **not** what this file measures —
/// the enrollment's mode and the client's posture are separate things here.
/// Reading a result below as evidence about key exchange would be reading a
/// constant as a variable.
void main() {
  // All three cells share one atSign on purpose: they are compared against
  // each other, so anything that differs between them other than the posture
  // is a second variable, and a per-cell atSign would be exactly that.
  //
  // ⚠️ The cost is three more enrollments on the suite's most-used identity,
  // and every `enroll:listns` walks the whole roster. Nothing here revokes or
  // deletes, so the roster only grows — but if the enrollment tests start
  // slowing, this file is one of the reasons and moving it to a less-used
  // atSign costs nothing, because which atSign is not what it measures.
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;
  const namespace = 'wavi';

  /// The three stages, named, so a failure says which cell produced it.
  const stages = <String, PqPosture>{
    'legacy': PqPosture.legacy,
    'pqReady': PqPosture.pqReady,
    'pqActive': PqPosture.pqActive,
  };

  final cells = <String, EnrolledClient>{};

  AtClient clientAt(String stage) => cells[stage]!.client;

  setUpAll(() async {
    // The approver has to be able to CONVEY each enrollment's symmetric key,
    // which means holding a registered key package of its own — pq mode has
    // the approver mint and seal the key rather than unwrap one the enrollee
    // sent. Without the `atKeysIo`, `AtClient.atKeysIo` is null and there is
    // nowhere to file the package's private half, so `register()` has nothing
    // to write and `approve` refuses by name.
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final owner =
        (await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo))
            .atClient;
    await AtClientSecretSharing.forClient(owner).register();

    for (final entry in stages.entries) {
      cells[entry.key] = await enrolAndAuthenticate(
        approver: owner,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign, posture: entry.value),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        // `(appName, deviceName)` is one-shot server state: a second run of
        // this file against the same virtualenv must not collide with the
        // first's, or every cell fails at setup for a reason that is not the
        // thing under test.
        deviceName: 'stagearm-${entry.key}-'
            '${DateTime.now().microsecondsSinceEpoch}',
      );
    }
  });

  test('each stage reaches its own constructed client', () async {
    // The Given for everything below. If a cell's client did not actually
    // receive the stage's axes, every later assertion is about whatever the
    // client did receive, and the file would be measuring a default.
    for (final entry in stages.entries) {
      final preference = clientAt(entry.key).getPreferences();
      expect(preference, isNotNull,
          reason: '${entry.key}: a client with no preference cannot be '
              'carrying a posture, so the rest of this file would be reading '
              'defaults');
      expect(preference!.disallowLegacyEncryption,
          entry.value.disallowLegacyEncryption,
          reason: '${entry.key}: the refusal flag has no setter and no '
              'constructor argument, so a mismatch here means the posture did '
              'not survive client construction');
      expect(preference.authenticationKeyAlgorithm,
          entry.value.authenticationKeyAlgorithm,
          reason: '${entry.key}: the algorithm a retrofit mints under is '
              'defaulted from the posture, and it is what tells a stage-aware '
              'client from a stage-blind one');
    }

    // The cells must genuinely differ, or a comparison between them compares
    // one case with itself.
    expect(
        stages.keys.map((s) => clientAt(s).getPreferences()!.disallowLegacyEncryption).toSet(),
        {true, false},
        reason: 'the refusal flag must take both values across the three '
            'cells, or the differential below has only one arm');
    expect(cells.values.map((c) => c.enrollmentId).toSet(), hasLength(3),
        reason: 'three distinct enrollment ids, or two cells share a client '
            'cache key and one of them is not the stage it claims');
  });

  test('UC-C1.1 · the era default follows the stage on a live client',
      () async {
    for (final stage in stages.keys) {
      final resolved = CryptoConfig.forClient(clientAt(stage));

      // Reads are maximal under every posture and are not settable at all, so
      // this holds in all three cells — including the one that writes legacy.
      expect(resolved.lookup(symmetricAesGcmCryptoProviderId), isNotNull,
          reason: '$stage: an inbound post-quantum record names this '
              'provider, and a client that cannot resolve it fails on data '
              'already sent to it');
      expect(resolved.lookup(nskeyCryptoProviderId), isNotNull,
          reason: '$stage: and the content key it cites is conveyed under '
              'this one');
    }

    // What the stage does decide: which provider a new write defaults to.
    expect(CryptoConfig.forClient(clientAt('legacy')).defaultProviderId,
        legacyCryptoProviderId,
        reason: 'the default stage reads post-quantum and still writes '
            'legacy — moving this is a fleet-wide commitment');
    expect(CryptoConfig.forClient(clientAt('pqReady')).defaultProviderId,
        legacyCryptoProviderId,
        reason: 'the middle stage moves the credentials and not the data '
            'path, which is the whole reason it exists as a separate stage');
    expect(CryptoConfig.forClient(clientAt('pqActive')).defaultProviderId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the last stage is where new writes become post-quantum');
  });

  test('UC-C1.2 · pqActive refuses a legacy write that the earlier stages take',
      () async {
    // A key every post-quantum provider structurally declines: the nskey data
    // path is `(owner, namespace)`-scoped, and this key carries no namespace,
    // so the defaulted provider falls back to legacy in every cell. That
    // fallback is what the refusal exists to catch.
    AtKey namespaceless() => AtKey()
      ..key = 'stagearm-phone'
      ..sharedBy = atSign
      ..metadata = (Metadata()..namespaceAware = false);

    // Selection time, through the function the put pipeline itself calls, with
    // the real constructed client rather than a mock.
    expect(
        CryptoRuntime.providerIdFor(clientAt('legacy'), null,
            atKey: namespaceless()),
        legacyCryptoProviderId,
        reason: 'the control: the identical key under the default stage '
            'selects legacy and is not refused, so the refusal below is '
            'caused by the stage and not by anything about this key');
    expect(
        CryptoRuntime.providerIdFor(clientAt('pqReady'), null,
            atKey: namespaceless()),
        legacyCryptoProviderId,
        reason: 'the second control, and the one that matters: post-quantum '
            'credentials alone do not refuse a legacy write. The refusal '
            'arrives with the last stage specifically');
    expect(
        () => CryptoRuntime.providerIdFor(clientAt('pqActive'), null,
            atKey: namespaceless()),
        throwsA(isA<LegacyEncryptionRefusedException>()),
        reason: 'the last stage refuses the fallback rather than writing data '
            'that is harvestable now and openable later');

    // …and the error names the record, or an app cannot act on it.
    expect(
        () => CryptoRuntime.providerIdFor(clientAt('pqActive'), null,
            atKey: namespaceless()),
        throwsA(predicate((e) => '$e'.contains('stagearm-phone'))),
        reason: 'a refusal that does not say which write was refused sends '
            'the app looking through its own code for it');
  });

  test('UC-C1.2 · the refusal fires through a real put, not only at selection',
      () async {
    // The end-to-end arm. It asks for legacy explicitly rather than reaching
    // the fallback, because `put` enforces a namespace unless the key is
    // `local:` — so the namespace-less key above cannot travel this route, and
    // a test that tried would fail in validation and never reach the crypto
    // path it names.
    AtKey note() => AtKey()
      ..key = 'stagearm-note'
      ..namespace = namespace
      ..sharedBy = atSign;

    PutRequestOptions legacyRequested() =>
        PutRequestOptions()..cryptoProviderId = legacyCryptoProviderId;

    expect(
        await clientAt('legacy')
            .put(note(), 'written under the default stage',
                putRequestOptions: legacyRequested()),
        true,
        reason: 'the control: the same call on the same atSign, differing '
            'only in the stage, has to succeed — otherwise the refusal below '
            'could be this key, this namespace or this atServer');

    await expectLater(
        () => clientAt('pqActive').put(note(), 'refused',
            putRequestOptions: legacyRequested()),
        throwsA(isA<LegacyEncryptionRefusedException>()),
        reason: 'an explicit request is honoured over the default but not '
            'over the flag: the flag is the guarantee, and it holds wherever '
            'the write entered');

    // The value the control wrote is readable, which is what says the control
    // arm did the whole job rather than returning true early.
    expect((await clientAt('legacy').get(note())).value,
        'written under the default stage',
        reason: 'a control that reports success without storing anything '
            'would make the refusal above look like the only working arm');
  });
}
