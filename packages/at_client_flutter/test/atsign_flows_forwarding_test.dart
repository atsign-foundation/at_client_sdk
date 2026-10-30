import 'dart:convert';

import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtAuthenticator, AtLookupImpl, AtLookupMuxable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _ScriptedLookUp extends Mock implements AtLookupImpl {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// What each `AtsignFlows` verb hands its `Atsign` verb, observed where the
/// `Atsign` verb acts on it: in the request it sends, or on the client it
/// opens.
///
/// Catalogue: features/at_client_flutter/platform_defaults.feature
void main() {
  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  /// Stops [client] once its post-quantum startup has run.
  Future<void> stopAfterStartup(AtClient client) async {
    if (client is AtClientImpl) await client.pqBootstrap?.startupComplete;
    await client.stop();
  }

  tearDown(() async {
    for (final client in List<AtClient>.from(
      AtClientImpl.atClientInstanceMap.values,
    )) {
      await stopAfterStartup(client);
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  late String encryptionPublicKey;
  setUpAll(
    () => encryptionPublicKey = RsaKeyPair.generate().atPublicKey.publicKey,
  );

  /// An atServer that answers what an activation, an open and an enrollment
  /// send, and records each command in [sent]. Asked whether the atSign is
  /// activated, it says not, as for a newly registered one; asked for its
  /// encryption public key, as an enrollment asks, it gives one.
  _ScriptedLookUp scriptedAtServer(
    List<String> sent, {
    String enrollStatus = 'approved',
  }) {
    final lookUp = _ScriptedLookUp();
    String answer(String command, {required bool asVerb}) {
      sent.add(command.trim());
      if (command.startsWith('lookup:publickey')) {
        return asVerb ? 'data:$encryptionPublicKey' : 'data:null';
      }
      if (command.startsWith('enroll:')) {
        return 'data:${jsonEncode({'enrollmentId': 'e-1', 'status': enrollStatus})}';
      }
      if (command.startsWith('stats')) {
        return 'data:${jsonEncode([
          {'id': '3', 'name': 'lastCommitID', 'value': '-1'},
        ])}';
      }
      if (command.startsWith('update:') || command.startsWith('delete:')) {
        return 'data:1';
      }
      throw StateError('the scripted atServer has no answer for: $command');
    }

    when(
      () => lookUp.secondaryAddressFinder,
    ).thenReturn(FixedSecondaryAddressFinder('127.0.0.1', 1));
    when(
      () => lookUp.executeCommand(any(), auth: any(named: 'auth')),
    ).thenAnswer(
      (i) async => answer(i.positionalArguments.first as String, asVerb: false),
    );
    when(() => lookUp.executeVerb(any())).thenAnswer(
      (i) async => answer(
        (i.positionalArguments.first as VerbBuilder).buildCommand(),
        asVerb: true,
      ),
    );
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(lookUp.stop).thenAnswer((_) async {});
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return lookUp;
  }

  AtLookUpFactory handing(AtLookupMuxable lookUp) =>
      ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) => lookUp;

  /// The JSON of the one enrollment request in [sent].
  Map<String, dynamic> enrollRequestIn(List<String> sent) {
    final requests = sent.where((c) => c.startsWith('enroll:request:'));
    expect(requests, hasLength(1), reason: 'one enrollment request was sent');
    return jsonDecode(requests.single.substring('enroll:request:'.length))
        as Map<String, dynamic>;
  }

  Future<List<String>> activating({String? device}) async {
    const atSign = '@flowsactivate';
    final sent = <String>[];
    final lookUps = handing(scriptedAtServer(sent));
    final storage = InMemoryAtClientStorage(atSign: atSign);
    final client = device == null
        ? await const AtsignFlows().activate(
            atSign,
            cramSecret: 'the-one-time-secret',
            keys: InMemoryAtKeysIo(),
            preference: AtClientPreference(),
            storage: storage,
            lookUps: lookUps,
          )
        : await const AtsignFlows().activate(
            atSign,
            cramSecret: 'the-one-time-secret',
            keys: InMemoryAtKeysIo(),
            preference: AtClientPreference(),
            storage: storage,
            lookUps: lookUps,
            device: device,
          );
    await stopAfterStartup(client);
    return sent;
  }

  Future<AtClient> opening({String? namespace}) {
    const atSign = '@flowsopen';
    final keys = InMemoryAtKeysIo.holding(
      atSign,
      AtKeys.legacy(
        apkamPublicKey: base64Encode(utf8.encode('apkam-public')),
        apkamPrivateKey: base64Encode(utf8.encode('apkam-private')),
        encryptionPublicKey: base64Encode(utf8.encode('encryption-public')),
        encryptionPrivateKey: base64Encode(utf8.encode('encryption-private')),
        selfEncryptionKey: base64Encode(utf8.encode('self')),
      ),
    );
    return const AtsignFlows().open(
      atSign,
      keys: keys,
      preference: AtClientPreference(),
      storage: InMemoryAtClientStorage(atSign: atSign),
      lookUps: handing(scriptedAtServer([])),
      namespace: namespace,
    );
  }

  Future<List<String>> enrolling({Duration? apkamKeysExpiry}) async {
    final sent = <String>[];
    await const AtsignFlows().enroll(
      '@flowsenroll',
      otp: 'ABC123',
      app: 'my_app',
      device: 'my_phone',
      namespaces: {'my_app': 'rw'},
      keys: InMemoryAtKeysIo(),
      preference: AtClientPreference(),
      lookUps: handing(scriptedAtServer(sent, enrollStatus: 'pending')),
      apkamKeysExpiry: apkamKeysExpiry,
    );
    return sent;
  }

  test(
    'An activation through AtsignFlows names the device the app gave',
    () async {
      final sent = await activating(device: 'flows-device');

      expect(
        enrollRequestIn(sent)['deviceName'],
        'flows-device',
        reason: 'AtsignFlows.activate passes device on to Atsign.activate',
      );
    },
  );

  test('An activation given no device names Atsign.activate\'s own', () async {
    final sent = await activating();

    expect(
      enrollRequestIn(sent)['deviceName'],
      firstEnrollmentDeviceName,
      reason: 'with no device given, Atsign.activate\'s default reaches it',
    );
  });

  test(
    'A client opened through AtsignFlows takes the namespace the app gave',
    () async {
      final client = await opening(namespace: 'flows_ns');

      expect(
        client.getPreferences()?.namespace,
        'flows_ns',
        reason: 'AtsignFlows.open passes namespace on to Atsign.open',
      );
    },
  );

  test(
    'A client opened given no namespace takes the preference\'s own',
    () async {
      final client = await opening();

      expect(
        client.getPreferences()?.namespace,
        isNull,
        reason:
            'with no namespace given, the preference\'s own, here none, '
            'is the client\'s',
      );
    },
  );

  test(
    'An enrollment through AtsignFlows asks for the key expiry the app gave',
    () async {
      final sent = await enrolling(apkamKeysExpiry: const Duration(hours: 1));

      expect(
        enrollRequestIn(sent)['apkamKeysExpiryInMillis'],
        const Duration(hours: 1).inMilliseconds,
        reason:
            'AtsignFlows.enroll passes apkamKeysExpiry on to '
            'Atsign.enroll',
      );
    },
  );

  test('An enrollment given no key expiry asks for none', () async {
    final sent = await enrolling();

    expect(
      enrollRequestIn(sent)['apkamKeysExpiryInMillis'],
      isNull,
      reason: 'with no expiry given, Atsign.enroll asks for none',
    );
  });
}
