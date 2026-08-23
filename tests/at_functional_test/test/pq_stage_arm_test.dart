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
///
/// ⚠️ **Each pq cell runs under a DIFFERENT enrollment id from the one it was
/// enrolled as, and both ids are real.** [enrolAndAuthenticate] hands back the
/// id the atServer assigned to the OTP enrollment it submitted; two of the
/// three clients then leave that enrollment behind before their constructor
/// returns.
///
/// The OTP path has no algorithm to ask with. `AtEnrollmentRequest` carries no
/// `signingAlgo` field, and the APKAM keypair that
/// `EnrollmentSubmitter._handleAtEnrollmentRequest` submits comes from
/// `AtChopsUtil.generateAtPkamKeyPair`, which takes a key size and nothing
/// else and is RSA-2048 always — so an enrollment minted this way
/// authenticates with RSA whichever posture ends up holding it. A pqReady or
/// pqActive preference therefore arrives at
/// `AtClientImpl._settleEnrollmentIdentity` holding rsa2048 and wanting
/// mldsa65, `AtClientImpl.retrofitIsDue` says a retrofit is due, and the
/// client self-enrols and comes up on a NEW enrollment id — all of it inside
/// `AtClientImpl.create`.
///
/// So: `AtClient.enrollmentId` is the id a client is authenticated as,
/// [EnrolledClient.enrollmentId] is the id it was enrolled as, and for the two
/// pq cells they are different strings. Anything asserting what a client IS
/// has to read the first. Reading the second compares ids that no client is
/// running under, which passes just as happily and measures nothing.
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

    // Read off the CLIENT rather than off the EnrolledClient. The cache key is
    // the id the client is authenticated as *now*, and for two of these cells
    // that is not the id their enrolment returned — see the note above [main].
    final runningIds = {
      for (final stage in stages.keys) stage: clientAt(stage).enrollmentId
    };
    for (final entry in runningIds.entries) {
      expect(entry.value, isNotNull,
          reason: '${entry.key}: a client with no enrollment id is not '
              'authenticated as an enrollment at all, and a set of nulls '
              'collapses the distinctness check below into one element');
    }
    expect(runningIds.values.toSet(), hasLength(3),
        reason: 'three distinct enrollment ids, or two cells share a client '
            'cache key and one of them is not the stage it claims');

    // And the retrofit itself, which nothing else in this file would notice.
    // A posture wanting a key the OTP path cannot mint must have MOVED its
    // client off the enrollment it was handed; the posture wanting exactly
    // what that path mints must have stayed. Both arms, because a changed id
    // on its own would also be produced by handing a cell the wrong client.
    for (final entry in stages.entries) {
      final enrolledAs = cells[entry.key]!.enrollmentId;
      if (entry.value.authenticationKeyAlgorithm == SigningAlgoType.rsa2048) {
        expect(runningIds[entry.key], enrolledAs,
            reason: '${entry.key}: this posture wants the rsa2048 key the OTP '
                'enrollment already minted, so no retrofit is due and the '
                'client must still be running as the enrolled id $enrolledAs');
      } else {
        expect(runningIds[entry.key], isNot(enrolledAs),
            reason: '${entry.key}: this posture wants '
                '${entry.value.authenticationKeyAlgorithm.name} while the OTP '
                'enrollment minted rsa2048, so the client must have '
                'retrofitted itself off the enrolled id $enrolledAs during '
                'construction. Still running as it means the retrofit never '
                'fired and this cell is a legacy client wearing a pq '
                'preference');
      }
    }
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
