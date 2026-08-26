@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// What a `public:__`-prefixed key is, and is not, visible to.
///
/// Eager nskey publication rests on this: `public:__nskey.<ns>@<owner>` is
/// written at mint and served to any sender that knows the namespace, while the
/// *set* of namespaces an atSign uses — which is the set of apps it runs — stays
/// unenumerable by an outsider.
///
/// The double underscore is deliberate. A single-underscore public key is hidden
/// from every scan but is written with **commit id −1**, so it sits outside the
/// commit log and sync can never push it. A double-underscore key gets a real
/// commit id and syncs, and is still invisible to an outsider because an
/// unauthenticated scan does not honour `showhidden`.
///
/// Every assertion here goes to the **remote secondary**. An earlier version of
/// this test used `put` and `get`, which wrote locally and read locally — so it
/// passed without the key ever reaching the atServer, and proved nothing.
void main() {
  late AtClientManager atClientManager;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
  });

  Future<String> remote(String command, {bool auth = true}) async =>
      (await atClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand(command, auth: auth)) ??
      '';

  test('a public:__ key syncs, is served by plookup, and is not enumerable',
      () async {
    final subject = 'public:__nskeyprobe.$namespace$atSign';
    // Control 1: an ordinary public key must appear in a scan, or "absent"
    // proves nothing.
    final visible = 'public:nskeyprobevisible.$namespace$atSign';
    // Control 2: proves showhidden is genuinely honoured on the authenticated
    // scan — otherwise the subject's absence from it means nothing either.
    final alsoHidden = 'public:__nskeyprobecontrol.$namespace$atSign';

    for (final key in [subject, visible, alsoHidden]) {
      final response = await remote('update:$key probe-value\n');
      expect(response.trim(), isNot(endsWith('-1')),
          reason: '$key must get a real commit id — a -1 means it is outside '
              'the commit log, so sync can never push it');
    }

    // Served on an exact lookup, which is what a sender does.
    expect(await remote('plookup:${subject.replaceFirst("public:", "")}\n'),
        contains('probe-value'),
        reason: 'a sender that knows the namespace must be able to fetch it');

    // The owner's own authenticated scan: hidden by default, revealed by
    // showhidden — control 2 proves that flag is working at all.
    final ownScan = await remote('scan\n');
    expect(ownScan, contains('nskeyprobevisible'));
    expect(ownScan, isNot(contains('__nskeyprobe')));

    final ownScanHidden = await remote('scan:showhidden:true\n');
    expect(ownScanHidden, contains('__nskeyprobecontrol'),
        reason:
            'control: showhidden must really reveal double-underscore keys, '
            'or the outsider assertion below is vacuous');

    // The view that actually matters. A fresh AtLookup that has never
    // authenticated is a genuine outsider — note this cannot be done through the
    // client's own remote secondary, whose `auth: false` reuses the already
    // authenticated connection and so is not an outsider at all.
    final outsider =
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
    try {
      final plain = await outsider.executeCommand('scan\n');
      final hidden = await outsider.executeCommand('scan:showhidden:true\n');

      expect(plain, contains('nskeyprobevisible'),
          reason: 'control: an outsider does see ordinary public keys, so an '
              'absence below is a real absence and not an empty response');
      for (final scan in [plain, hidden]) {
        expect(scan, isNot(contains('__nskeyprobe')),
            reason:
                'an outsider must not be able to enumerate which namespaces '
                'this atSign uses — an unauthenticated scan ignores showhidden, '
                'and that is what makes eager publication safe');
      }
    } finally {
      await outsider.close();
    }
  });
}
