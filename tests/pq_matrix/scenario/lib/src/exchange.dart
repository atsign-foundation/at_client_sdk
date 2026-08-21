// `EnvelopeSigning` carries at_client's `@experimental` marker in both builds,
// and reaching for it anyway is the point rather than a compromise. UC-G1.14's
// claim is about what a DEPLOYED reader makes of a rollout-1 `_apsk`, and only
// that reader's own code path can settle it — the marker warns app authors
// that the API may move, which is a different question from whether this
// harness may call the exact version it pins.
// ignore_for_file: experimental_member_use

import 'dart:async' show Completer, StreamSubscription, TimeoutException;

import 'package:at_client/at_client.dart'
    show
        AtClient,
        AtKey,
        AtNotification,
        GetRequestOptions,
        NotificationParams,
        PutRequestOptions;
// ignore: implementation_imports
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
// ignore: implementation_imports
import 'package:at_client/src/mixins/envelope_signing.dart' show EnvelopeSigning;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:crypton/crypton.dart' show RSAPublicKey;

import 'protocol.dart';

/// What one cell of the matrix exchanges.
///
/// Both processes derive every record name from [runId], so neither has to be
/// told what the other wrote. A run-unique id also keeps cells from reading
/// each other's records: sixteen cells over one pair of atSigns would
/// otherwise have a later cell pass on an earlier cell's data.
class ExchangeSpec {
  /// Lowercase and alphanumeric — atKey names are lowercased, so an id that
  /// is not already lowercase would name one record on the way out and
  /// another on the way back.
  final String runId;
  final String namespace;

  /// The other side of this cell.
  final String peerAtSign;

  /// The enrollment id this client publishes and signs under — `primary` for
  /// a client with no enrollment record. It addresses this client's own
  /// `_apsk` read-back in [runSender].
  final String ownEnrollmentId;

  /// The enrollment id the PEER publishes and signs under. The receiver needs
  /// it to fetch the sender's advertisement: an `_apsk` address is
  /// `(atSign, enrollment)`, and a reader handed only the atSign would read
  /// `primary`, which an enrolled sender never writes.
  final String peerEnrollmentId;

  /// **Several, not one.** A shape that survives the first exchange and breaks
  /// on the second is the failure this catches, and one put cannot see it
  /// (`docs/projects/pq/acceptance.md` 16.1).
  final int putCount;

  final Duration timeout;

  const ExchangeSpec({
    required this.runId,
    required this.namespace,
    required this.peerAtSign,
    this.ownEnrollmentId = 'primary',
    this.peerEnrollmentId = 'primary',
    this.putCount = 3,
    this.timeout = const Duration(minutes: 2),
  });

  /// The nth shared record's name.
  String recordName(int n) => 'pqm${runId}x$n';

  /// The record the sender notifies on, once the puts are done.
  String get wakeName => 'pqmwake$runId';

  /// The nth record's value. Derived rather than random, so the receiver
  /// asserts the exact bytes the sender wrote rather than merely that
  /// *something* arrived.
  String valueFor(int n) => 'pq-matrix/$runId/$n';

  String get wakeValue => 'pq-matrix/$runId/wake';
}

// A record another atSign must read NOW goes straight to the atServer rather
// than waiting for sync. The notification travels by its own transport and
// would otherwise outrun the record it announces.
final _remoteWrite = PutRequestOptions()..useRemoteAtServer = true;
final _remoteRead = GetRequestOptions()..useRemoteAtServer = true;

AtKey _sharedKey(String name, ExchangeSpec spec,
        {required String from, required String to}) =>
    AtKey()
      ..key = name
      ..namespace = spec.namespace
      ..sharedWith = to
      ..sharedBy = from;

/// An arm's own extra work inside a cell, run at the point in the sequence
/// where it is safe.
///
/// Returns whatever it wants reported, or null to report nothing. It exists
/// because the **envelope** half of the matrix is not shared code: 3.14.0's
/// `wrapAndSign` returns a `Map` and this tree's returns a `SignedEnvelope`,
/// and 3.14.0 ships no `lib/src/signing/` at all, so a file in this package
/// that signed an envelope would not compile on the published arm and would
/// take the whole matrix down rather than the rows it applies to.
///
/// The ordering is why it is a hook here rather than a call in each `bin/`:
/// the sender's step has to land **before** the notification (the receiver
/// starts reading the moment it wakes) and the receiver's **after** its reads.
/// Both constraints live in this file, so the hook is invoked from this file.
typedef ExchangeStep = Future<Map<String, Object?>?> Function(
    AtClient client, ExchangeSpec spec);

/// Writes this cell's records and announces them.
///
/// Each put is read back before the next one is written: a put that returns
/// true and stored something else fails here, next to the write, rather than
/// as an unexplained mismatch in the other process.
Future<void> runSender(AtClient client, ExchangeSpec spec,
    {ExchangeStep? step}) async {
  final me = client.getCurrentAtSign()!;
  final written = <String>[];

  for (var n = 0; n < spec.putCount; n++) {
    final key =
        _sharedKey(spec.recordName(n), spec, from: me, to: spec.peerAtSign);
    final ok = await client.put(key, spec.valueFor(n),
        putRequestOptions: _remoteWrite);
    if (!ok) {
      throw StateError('put ${spec.recordName(n)} returned false');
    }
    final readBack = await client.get(key, getRequestOptions: _remoteRead);
    if (readBack.value != spec.valueFor(n)) {
      throw StateError('put ${spec.recordName(n)} stored '
          '"${readBack.value}", not "${spec.valueFor(n)}"');
    }
    written.add(spec.recordName(n));
  }

  // Before the notification, because the receiver starts reading as soon as it
  // wakes: anything this step writes has to be on the atServer by then, for
  // the same reason the puts are.
  final stepResult = step == null ? null : await step(client, spec);

  // The notification last, and only once every record it announces is on the
  // atServer.
  final wake = _sharedKey(spec.wakeName, spec, from: me, to: spec.peerAtSign);
  final notified = await client.notificationService
      .notify(NotificationParams.forUpdate(wake, value: spec.wakeValue));

  emit(MatrixVerb.sent, {
    'atSign': me,
    'written': written,
    'notification': notified.notificationStatusEnum.name,
    // What this stage left on the atServer for peers to verify against. Read
    // back rather than reported from memory: UC-G1.14's claim is about the
    // published record, and a client's idea of what it published is not that.
    'apsk': await readApsk(client, spec.ownEnrollmentId),
    if (stepResult != null) ...stepResult,
  });
}

/// The `_apsk` record this client has published, verbatim, or null when there
/// is none.
///
/// The address shape is spelled as a **raw literal** on purpose. It is a wire
/// contract, and a harness that composed it from the same constants the
/// production code uses would follow a renamed constant silently — the record
/// could move and every assertion here would keep passing. Only the
/// enrollment id varies: `primary` for a client with no enrollment record,
/// the enrollment's own id otherwise — an `_apsk` address is
/// `(atSign, enrollment)`.
Future<String?> readApsk(AtClient client, String enrollmentId) async {
  final me = client.getCurrentAtSign()!;
  try {
    final response = await client
        .getRemoteSecondary()!
        .executeCommand('llookup:public:_apsk.$enrollmentId.a.__e$me\n',
            auth: true);
    if (response == null || !response.startsWith('data:')) return null;
    final value = response.replaceFirst('data:', '').trim();
    return value.isEmpty || value == 'null' ? null : value;
  } on Object {
    // Absent reads as null, the same as an empty value: the caller compares
    // two stages against each other and "neither published one" is a real,
    // equal answer.
    return null;
  }
}

/// What **this build's own reader** makes of [peerAtSign]'s `_apsk` — the
/// measurement UC-G1.14 turns on.
///
/// Reached through at_client's `EnvelopeSigning.getApkamPublicKey` rather than
/// a lookup written here, and the `src/` import is the point rather than a
/// shortcut. The property under test is that *a deployed peer* can still read
/// a rollout-1 sender's advertisement, and only the deployed build's own code
/// path can settle that — a fetch reimplemented in this file would test the
/// reimplementation. Both arms compile this, so on the published arm it is
/// literally at_client 3.14.0 doing the reading.
///
/// `RSAPublicKey.fromString` is the call at_chops makes when it verifies a
/// pkam signature, so `rsa: true` means the value is one a released verifier
/// could actually have used — not merely that it looked like base64.
///
/// Never throws: every outcome is reported, because "the released reader threw"
/// is the result this row exists to detect and an exception here would be
/// indistinguishable from the harness failing.
Future<Map<String, Object?>> readPeerApskAsReleasedReader(
    AtClient client, String peerAtSign, String peerEnrollmentId) async {
  final reader = _ReleasedApskReader(client);
  String value;
  try {
    // The sender's own enrollment id — `primary` when it has no enrollment
    // record. A released reader can read any enrollment's record given the
    // id; what it cannot do is guess one, which is why the driver threads it.
    value = await reader.getApkamPublicKey(peerAtSign, peerEnrollmentId);
  } on Object catch (e) {
    return {'fetched': false, 'rsa': false, 'error': '$e'};
  }

  try {
    RSAPublicKey.fromString(value);
    return {'fetched': true, 'rsa': true, 'value': value};
  } on Object catch (e) {
    return {'fetched': true, 'rsa': false, 'value': value, 'error': '$e'};
  }
}

/// The smallest thing that can hold [EnvelopeSigning].
///
/// Its three members are declared identically in at_client 3.14.0 and in this
/// tree — checked, because a mixin member present in only one of them would
/// make this file uncompilable on that arm and take the whole matrix down
/// rather than the one row.
class _ReleasedApskReader with ApkamSigning, EnvelopeSigning {
  _ReleasedApskReader(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('pqMatrixApskReader');

  /// Null: caching is what would make a second read return the first read's
  /// answer, and each cell wants the record as it stands now.
  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;
}

/// Subscribes, announces readiness, then reads what the sender wrote.
///
/// The subscription is established **before** [MatrixVerb.ready] is emitted and
/// the driver will not start the sender until it sees that line. Notification
/// streams are broadcast and do not replay, so a receiver that subscribes after
/// the sender has run waits for an event that has already been and gone.
Future<void> runReceiver(AtClient client, ExchangeSpec spec,
    {ExchangeStep? step}) async {
  final me = client.getCurrentAtSign()!;
  final arrived = Completer<AtNotification>();
  final StreamSubscription<AtNotification> subscription = client
      .notificationService
      .subscribe(regex: spec.wakeName, shouldDecrypt: true)
      .listen((notification) {
    if (!arrived.isCompleted) arrived.complete(notification);
  });

  try {
    emit(MatrixVerb.ready, {'atSign': me, 'awaiting': spec.wakeName});

    final AtNotification wake = await arrived.future.timeout(
      spec.timeout,
      onTimeout: () => throw TimeoutException(
          'no notification for ${spec.wakeName} within ${spec.timeout}',
          spec.timeout),
    );
    // The notification's own value, decrypted. A wake-up that arrives but
    // cannot be decrypted is a different failure from one that never arrives,
    // and asserting only arrival would report the first as a pass.
    if (wake.value != spec.wakeValue) {
      throw StateError('notification carried "${wake.value}", not '
          '"${spec.wakeValue}"');
    }

    final read = <String>[];
    for (var n = 0; n < spec.putCount; n++) {
      final key = _sharedKey(spec.recordName(n), spec,
          from: spec.peerAtSign, to: me);
      final value = await client.get(key, getRequestOptions: _remoteRead);
      if (value.value != spec.valueFor(n)) {
        throw StateError('record ${spec.recordName(n)} read '
            '"${value.value}", not "${spec.valueFor(n)}"');
      }
      read.add(spec.recordName(n));
    }

    // After the reads, so a step that fails cannot be mistaken for the data
    // path failing — by here every record this cell announced has been read
    // back and compared.
    final stepResult = step == null ? null : await step(client, spec);

    emit(MatrixVerb.result, {
      'atSign': me,
      'read': read,
      'notification': wake.id,
      if (stepResult != null) ...stepResult,
      // What this build makes of the SENDER's advertisement. On the published
      // arm this is at_client 3.14.0's own verdict, which is the only thing
      // that can say a deployed peer is unaffected by the sender's stage.
      'peerApsk': await readPeerApskAsReleasedReader(
          client, spec.peerAtSign, spec.peerEnrollmentId),
    });
  } finally {
    await subscription.cancel();
  }
}
