@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Pins what a `public:__`-prefixed key is visible to: it takes a real commit
/// id and syncs, is served on an exact `plookup`, and stays out of an
/// outsider's scan, which ignores `showhidden` — so the set of namespaces an
/// atSign uses is not enumerable.
///
/// Every assertion goes to the remote secondary; `put` and `get` write and read
/// locally, so they would pass without the key ever reaching the atServer.
void main() {
  TestUtils.isolateStorage('underscore_public_key_hiding_test');
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
    final visible = 'public:nskeyprobevisible.$namespace$atSign';
    final alsoHidden = 'public:__nskeyprobecontrol.$namespace$atSign';

    for (final key in [subject, visible, alsoHidden]) {
      final response = await remote('update:$key probe-value\n');
      expect(response.trim(), isNot(endsWith('-1')),
          reason: '$key must get a real commit id — a -1 means it is outside '
              'the commit log, so sync can never push it');
    }

    expect(await remote('plookup:${subject.replaceFirst("public:", "")}\n'),
        contains('probe-value'),
        reason: 'a sender that knows the namespace must be able to fetch it');

    final ownScan = await remote('scan\n');
    expect(ownScan, contains('nskeyprobevisible'));
    expect(ownScan, isNot(contains('__nskeyprobe')));

    final ownScanHidden = await remote('scan:showhidden:true\n');
    expect(ownScanHidden, contains('__nskeyprobecontrol'),
        reason:
            'control: showhidden must really reveal double-underscore keys, '
            'or the outsider assertion below is vacuous');

    // NOTE: only a fresh AtLookup is a genuine outsider — the client's own
    // remote secondary with `auth: false` reuses the already authenticated
    // connection.
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
