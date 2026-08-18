// `EnvelopeSigning` and the envelope types carry at_client's `@experimental`
// marker. Reaching for them is the point: this file measures what one stage's
// signer produces and what another stage's verifier makes of it, and only
// at_client's own code path can settle that.
// ignore_for_file: experimental_member_use

import 'dart:convert' show jsonDecode;

import 'package:at_client/at_client.dart'
    show AtClient, AtKey, GetRequestOptions, PutRequestOptions;
// ignore: implementation_imports
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
// ignore: implementation_imports
import 'package:at_client/src/mixins/envelope_signing.dart' show EnvelopeSigning;
// ignore: implementation_imports
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart' show ExchangeSpec;

/// This arm only. The published arm cannot compile any of it: 3.14.0's
/// `wrapAndSign` returns a `Map<String, Object?>` where this tree's returns a
/// `SignedEnvelope`, and 3.14.0 ships no `lib/src/signing/` at all — which is
/// also why the envelope grid is a `now`/`rollout1`/`rollout2` 3×3 rather than
/// a fourth row and column of the data-path matrix.
///
/// What the grid is for: under
/// `docs/projects/pq/detail/decisions.md` 108 the rollout ladder **swaps**
/// algorithms rather than overlapping them, so a `rollout2` sender emits an
/// ML-DSA-65 signature alone and a `rollout1` receiver — which signs RSA-2048 —
/// must still verify it. That is a claim about an ungated verifier, and this is
/// the measurement that settles it.

/// The record the sender leaves its signed envelope in.
///
/// Its own record rather than a field on an existing one: the data-path cells
/// assert exact values for those, and a cell that failed would not say which
/// half broke.
String _envelopeName(ExchangeSpec spec) => 'pqmenv${spec.runId}';

final _remoteWrite = PutRequestOptions()..useRemoteAtServer = true;
final _remoteRead = GetRequestOptions()..useRemoteAtServer = true;

AtKey _envelopeKey(ExchangeSpec spec,
        {required String from, required String to}) =>
    AtKey()
      ..key = _envelopeName(spec)
      ..namespace = spec.namespace
      ..sharedWith = to
      ..sharedBy = from;

/// Signs an envelope at this cell's stage and leaves it for the peer.
///
/// Reports the algorithms it actually emitted, **not** merely that it signed.
/// A grid whose cells only assert "verified" passes just as well for a harness
/// where no stage does anything — which is how the previous version of this
/// matrix came to assert a property no cell exercised. The driver compares
/// these across stages, so a `rollout2` cell that quietly signed RSA-2048
/// fails on the algorithm before anything gets as far as verifying.
Future<Map<String, Object?>?> signEnvelopeForPeer(
    AtClient client, ExchangeSpec spec) async {
  final me = client.getCurrentAtSign()!;
  final signer = _MatrixEnvelopeSigner(client);

  final envelopeJson = await signer.wrapAndSignAndJsonEncode({
    'runId': spec.runId,
    'from': me,
  });

  final key = _envelopeKey(spec, from: me, to: spec.peerAtSign);
  final ok = await client.put(key, envelopeJson, putRequestOptions: _remoteWrite);
  if (!ok) {
    throw StateError('put ${_envelopeName(spec)} returned false');
  }

  // Parsed back from the JSON that was actually written, so what is reported
  // is what the peer will read rather than what this process meant to send.
  final envelope = SignedEnvelope.fromJson(jsonDecode(envelopeJson) as Map);
  return {
    'envelope': {
      'wrote': _envelopeName(spec),
      'algs': [for (final s in envelope.signatures) s.alg],
      'signerEnrollmentId': envelope.signerEnrollmentId,
    },
  };
}

/// Reads the peer's envelope and verifies it with this cell's own build.
///
/// Never throws: a refusal is the result for the cells that are expected to
/// refuse, and an exception here would be indistinguishable from the harness
/// breaking. The driver decides which outcome a cell should have.
///
/// Verification fetches the signer's `_apsk` from the atServer, so this
/// exercises the whole path — the sender's advertisement, the receiver's
/// reader, and the algorithm both ends have to agree on — rather than a
/// signature checked against a key handed over locally.
Future<Map<String, Object?>?> verifyPeerEnvelope(
    AtClient client, ExchangeSpec spec) async {
  final me = client.getCurrentAtSign()!;
  final verifier = _MatrixEnvelopeSigner(client);

  final key = _envelopeKey(spec, from: spec.peerAtSign, to: me);

  String raw;
  try {
    final value = await client.get(key, getRequestOptions: _remoteRead);
    if (value.value is! String) {
      return {
        'envelope': {
          'read': false,
          'error': 'value of ${_envelopeName(spec)} is not a String',
        },
      };
    }
    raw = value.value as String;
  } on Object catch (e) {
    return {
      'envelope': {'read': false, 'error': '$e'},
    };
  }

  SignedEnvelope envelope;
  try {
    envelope = SignedEnvelope.fromJson(jsonDecode(raw) as Map);
  } on Object catch (e) {
    return {
      'envelope': {'read': true, 'parsed': false, 'error': '$e'},
    };
  }

  final algs = [for (final s in envelope.signatures) s.alg];
  try {
    await verifier.verifyEnvelopeSignature(envelope,
        signerAtSign: spec.peerAtSign);
    return {
      'envelope': {'read': true, 'parsed': true, 'verified': true, 'algs': algs},
    };
  } on Object catch (e) {
    return {
      'envelope': {
        'read': true,
        'parsed': true,
        'verified': false,
        'algs': algs,
        // Type and message separately, for the same reason the protocol's
        // failure line splits them: a pin on the type survives a reworded
        // message, and the message is what names the cause.
        'errorType': e.runtimeType.toString(),
        'error': '$e',
      },
    };
  }
}

/// The smallest thing that can hold [EnvelopeSigning].
///
/// Signing and verifying share one class because they share one `_apsk`
/// address: a verifier that resolved the record differently from the signer
/// would be testing two spellings rather than one exchange.
class _MatrixEnvelopeSigner with ApkamSigning, EnvelopeSigning {
  _MatrixEnvelopeSigner(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('pqMatrixEnvelope');

  /// Null: a cached public key would let one cell verify against the key a
  /// previous cell published, which is exactly the confusion a grid over
  /// stages exists to expose.
  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;
}
