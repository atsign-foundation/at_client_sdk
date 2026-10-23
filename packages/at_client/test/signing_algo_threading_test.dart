import 'dart:io';

import 'package:test/test.dart';

/// The per-enrollment signing algorithm must reach every connection the
/// client owns. A self-retrofit's ML-DSA enrollment re-authenticates on
/// every reconnect — verb, monitor and sync alike — so a connection stamped
/// with the preference's rsa2048 default fails against the
/// record-authoritative atServer no matter how correct its AtChops are.
void main() {
  group('RemoteSecondary', () {
    /// Asserted against the source, like the Monitor test below: the
    /// resolved algorithm is captured inside the authenticator closure
    /// `_installAuthenticator` builds, with nothing on the constructed
    /// object to read it back from.
    test('resolves and threads the signing algorithm through the seam', () {
      final source =
          File('lib/src/client/remote_secondary.dart').readAsStringSync();

      expect(source, contains('signingAlgoType ?? preference.signingAlgoType'),
          reason: 'an explicit signingAlgoType overrides the preference '
              'default, so one preference can still serve two enrollments '
              'that sign differently');
      expect(source, contains('signingAlgo: _signingAlgoType'),
          reason: 'the resolved algorithm, not the preference default, is '
              'what the authenticator seam actually signs with');
    });
  });

  group('AtClientImpl.buildRemoteSecondary', () {
    /// Asserted against the source: the forward is a plain pass-through with
    /// no branch or default to exercise live, and RemoteSecondary's own
    /// resolution of what it's handed is the 'RemoteSecondary' group above.
    test(
        'threads the client\'s enrollment id and algorithm into the '
        'connection it builds', () {
      final source =
          File('lib/src/client/at_client_impl.dart').readAsStringSync();
      final wiring = source
          .substring(source.indexOf('RemoteSecondary buildRemoteSecondary('));

      expect(wiring, contains('enrollmentId: enrollmentId'),
          reason: 'so the seam authenticates as this client\'s own '
              'enrollment, not the primary one');
      expect(wiring, contains('signingAlgoType: signingAlgoType'),
          reason: 'so a connection opened for an ML-DSA enrollment signs '
              'with ML-DSA rather than the preference\'s rsa2048 default');
    });

    test('is the only way this class opens a connection', () {
      // NOTE: `stream()` opens a connection of its own and cannot be driven
      // from a unit test — it needs a file on disk and a real socket — so what
      // is pinned instead is that no site in the class builds one by hand. A
      // hand-rolled site fails here rather than at an ML-DSA atSign's first
      // file transfer.
      final source =
          File('lib/src/client/at_client_impl.dart').readAsStringSync();
      final constructions =
          RegExp(r'(?<![A-Za-z_])RemoteSecondary\(').allMatches(source);

      expect(constructions, hasLength(1),
          reason: 'the one permitted construction is inside '
              'buildRemoteSecondary; every other site calls it');
      final only = source.substring(0, constructions.single.start);
      expect(only, contains('RemoteSecondary buildRemoteSecondary('),
          reason: 'the surviving construction must be the builder itself, not '
              'a hand-rolled site that happens to be the last one left');
    });
  });

  group('Monitor', () {
    /// Monitor holds an `AtLookupMuxable` rather than a signing algorithm, and
    /// the algorithm travels inside the authenticator `NotificationServiceImpl`
    /// builds for it: a monitor connection stamped with the preference's
    /// rsa2048 default fails every re-authentication for an ML-DSA enrollment.
    ///
    /// Asserted against the source because the algorithm is captured in a
    /// closure, with nothing on the built object to read it back from.
    test('the resolved algorithm reaches the monitor connection', () {
      final source = File('lib/src/service/notification_service_impl.dart')
          .readAsStringSync();
      final wiring = source.substring(source.indexOf('lookUp: lookUps('));

      expect(wiring, contains('signingAlgo: signingAlgoOf(atClient)'),
          reason: 'the monitor connection must authenticate with the '
              'RESOLVED algorithm, not the preference default - '
              'signingAlgoOf() is what reads the enrollment key material');
      expect(wiring, contains('enrollmentId: atClient.enrollmentId'),
          reason: 'and as the right enrollment, or the atServer refuses it');
      expect(wiring, contains('hashingAlgo: preference.hashingAlgoType'),
          reason: 'hashing travels with signing - the pair is one setting');
    });
  });
}
