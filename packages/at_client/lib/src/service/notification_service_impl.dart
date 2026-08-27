import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart'
    show
        CryptoConfig,
        FiledNskeyPrivate,
        NskeyPrivateUnavailableException,
        SignalsPrivateFiling;
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart'
    show NamespaceKeyUnavailableException;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart'
    show NskeyPrivateFiling;
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/response/at_notification.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show signingAlgoOf;
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/regex_match_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_auth/at_auth.dart' show authenticatorForChops;
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    as at_persistence_secondary_server;
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

class NotificationServiceImpl extends NotificationService {
  final Map<NotificationConfig, StreamController> _streamListeners =
      HashMap(equals: _compareNotificationConfig, hashCode: _generateHashCode);
  final emptyRegex = '';
  static const notificationIdKey = '_latestNotificationIdv2';

  /// [lastReceivedNotificationKey] has been converted to lowercase
  /// from at_client v3.0.59
  static const lastReceivedNotificationKey = 'lastreceivednotification';

  final AtClient atClient;
  late final Monitor monitor;
  late final AtSignLogger logger;
  DateTime? _lastReceipt;

  @visibleForTesting
  AtClientValidation atClientValidation = AtClientValidation();

  @visibleForTesting
  late AtKey lastReceivedNotificationAtKey;

  @override
  Atsign get atSign => atClient.atSign;

  late SecondaryAddressFinder secondaryAddressFinder;

  /// Notifications held back because the nskey private that opens them has not
  /// been filed yet, keyed by the generation they are waiting for.
  ///
  /// A conveyed private is filed asynchronously, so a value sealed to it can
  /// arrive first. Dropping it there is data loss: the record sits on the
  /// atServer for its ttl and the key lands milliseconds later, so nothing
  /// re-delivers what was already discarded.
  ///
  /// **In memory, and lost on restart** — deliberately. A park that outlived
  /// the process would need the notification and its ordering position to be
  /// durable, and a restart re-drives from the watermark anyway.
  final Map<FiledNskeyPrivate, List<_ParkedNotification>> _parked = {};

  /// Bounds the park. A held notification that is never re-driven is the same
  /// data loss with a longer fuse, so the park is not allowed to grow without
  /// limit or to hold anything indefinitely: the oldest entry is dropped —
  /// **at `warning`, naming what was lost** — once either bound is reached.
  @visibleForTesting
  static int maxParked = 64;

  /// How long a notification may sit parked waiting for the key that opens
  /// it.
  ///
  /// ⚠️ **The ordering is the contract, not the number.** This must exceed
  /// [NskeyPrivateFiling.conveyanceWait], the window a pull gives a holder to
  /// answer. Below it, a notification is dropped while the key it is waiting
  /// for is still legitimately in flight, and the drop is attributed to the
  /// sender rather than to this timer. It was two minutes against a five
  /// minute wait, in two files that never mentioned each other, which is why
  /// nothing could go red on the inversion.
  @visibleForTesting
  static Duration parkTtl =
      NskeyPrivateFiling.conveyanceWait + const Duration(minutes: 1);

  StreamSubscription<FiledNskeyPrivate>? _filingSubscription;

  /// Subscribes to the filing signal, if this client's key ring emits one.
  ///
  /// Subscribed at construction rather than when the first notification parks:
  /// the stream is broadcast and therefore not replayed, so a subscription
  /// taken after the read that failed could miss the very filing it needs.
  /// ⚠️ Resolves through [CryptoConfig.forClient], **not**
  /// `getPreferences().crypto`. An app that names no config gets the era
  /// default, whose ring is supplied by the client's PQ bootstrap — the raw
  /// preference carries none, so reading it directly finds null and silently
  /// subscribes to nothing. Measured live: notifications parked correctly and
  /// were never re-driven, because this had never subscribed.
  ///
  /// Idempotent and re-attempted at park time: the bootstrap wires the ring
  /// asynchronously, so a service constructed first would otherwise never
  /// subscribe at all.
  void _listenForFilings() {
    if (_filingSubscription != null) return;
    final ring = CryptoConfig.forClient(atClient).keyRing;
    if (ring is! SignalsPrivateFiling) return;
    _filingSubscription =
        (ring as SignalsPrivateFiling).privatesFiled.listen(_reDriveParked);
  }

  /// How many notifications are held waiting for a key, right now.
  @visibleForTesting
  int get parkedCount =>
      _parked.values.fold<int>(0, (sum, entries) => sum + entries.length);

  /// How many have been parked over this service's life.
  ///
  /// Cumulative because [parkedCount] is zero again as soon as the re-drive
  /// runs, so a test that only checked it could not tell a notification that
  /// was parked and released from one that never needed parking. A live test
  /// of this path is racing a ~100 ms window, and without this it goes green
  /// whenever it loses the race — which is the silent failure to guard.
  @visibleForTesting
  int parkedTotal = 0;

  /// Transforms [n] for one subscriber and delivers it if the regex matches.
  ///
  /// Shared by the arrival path and the re-drive so the two cannot diverge on
  /// the regex rule — a parked notification must reach exactly the subscribers
  /// the live one would have.
  Future<void> _deliver(AtNotification n, NotificationConfig config,
      StreamController controller) async {
    final transformed =
        await NotificationResponseTransformer(atClient).transform(Tuple()
          ..one = n
          ..two = config);
    if (config.regex != emptyRegex && !hasRegexMatch(n.key, config.regex)) {
      return;
    }
    if (!controller.isClosed) controller.add(transformed);
  }

  /// Holds [n] until the generation it needs is filed.
  void _park(NskeyPrivateUnavailableException e, AtNotification n,
      NotificationConfig config, StreamController controller) {
    final key = (
      owner: e.owner.toAtsign().toString(),
      namespace: e.namespace,
      nskeyKid: e.nskeyKid
    );
    // The ring may only have been wired after this service was built, and a
    // park with nothing listening for the filing is a notification held until
    // its ttl and then dropped.
    _listenForFilings();
    final entries = _parked.putIfAbsent(key, () => []);
    entries.add(_ParkedNotification(n, config, controller, DateTime.now()));
    parkedTotal++;
    logger.info('Parked notification ${n.key}: waiting for the nskey private '
        'for ${key.owner}:${key.namespace} generation ${key.nskeyKid}');
    _evictParkedOverBounds();
  }

  /// Enforces both park bounds. Anything dropped here is logged at `warning`
  /// naming what was lost — a silently discarded notification is
  /// indistinguishable from one that was never sent.
  void _evictParkedOverBounds() {
    final now = DateTime.now();
    for (final entry in _parked.entries.toList()) {
      entry.value.removeWhere((parked) {
        if (now.difference(parked.parkedAt) < parkTtl) return false;
        logger.warning('Dropping parked notification ${parked.notification.key}'
            ': the nskey private for ${entry.key.namespace} generation '
            '${entry.key.nskeyKid} did not arrive within $parkTtl');
        return true;
      });
      if (entry.value.isEmpty) _parked.remove(entry.key);
    }

    var total = _parked.values.fold<int>(0, (sum, l) => sum + l.length);
    while (total > maxParked) {
      final oldestKey = _parked.entries
          .reduce((a, b) =>
              a.value.first.parkedAt.isBefore(b.value.first.parkedAt) ? a : b)
          .key;
      final dropped = _parked[oldestKey]!.removeAt(0);
      logger.warning('Dropping parked notification ${dropped.notification.key}'
          ': the park is full at $maxParked entries');
      if (_parked[oldestKey]!.isEmpty) _parked.remove(oldestKey);
      total--;
    }
  }

  /// Re-drives everything waiting on the generation just filed.
  Future<void> _reDriveParked(FiledNskeyPrivate filed) async {
    final key = (
      owner: filed.owner.toAtsign().toString(),
      namespace: filed.namespace,
      nskeyKid: filed.nskeyKid
    );
    final waiting = _parked.remove(key);
    if (waiting == null || waiting.isEmpty) return;

    logger.info('The nskey private for ${key.namespace} generation '
        '${key.nskeyKid} was filed; re-driving ${waiting.length} parked '
        'notification(s)');
    for (final parked in waiting) {
      try {
        await _deliver(parked.notification, parked.config, parked.controller);
      } catch (e) {
        // Warning, and it names the notification: this was the retry, so a
        // failure here is the point at which the value is genuinely lost.
        logger.warning('Re-driving parked notification '
            '${parked.notification.key} failed, and nothing retries it '
            'again: $e');
      }
    }
  }

  /// - [monitor] is providable for unit test purposes
  static Future<NotificationService> create(AtClient atClient,
      {Monitor? monitor,
      SecondaryAddressFinder? secondaryAddressFinder}) async {
    return NotificationServiceImpl._(
        atClient: atClient,
        monitor: monitor,
        secondaryAddressFinder: secondaryAddressFinder);
  }

  final String myStatsNotifKey;

  NotificationServiceImpl._(
      {required this.atClient,
      Monitor? monitor,
      SecondaryAddressFinder? secondaryAddressFinder})
      : myStatsNotifKey = 'statsNotification.${atClient.atSign}' {
    logger = AtSignLogger(
        'NotificationServiceImpl (${atClient.getCurrentAtSign()})');

    this.secondaryAddressFinder = secondaryAddressFinder ??
        CacheableSecondaryAddressFinder(atClient.getPreferences()!.rootDomain,
            atClient.getPreferences()!.rootPort);

    final preference = atClient.getPreferences()!;
    final chops = atClient.atChops;
    this.monitor = monitor ??
        Monitor(
          atSign: atSign,
          atClientPreference: preference,
          // A FRESH lookup, so the connection count is unchanged. Passing
          // `atClient.getRemoteSecondary()!.atLookUp` here instead would
          // collapse the two sockets into one - a one-line change, and NOT
          // safe yet: no atServer implements `monitor:multiplexed`, so
          // nothing holds a notification back while a verb response is in
          // flight.
          lookUp: AtLookUp.withSecureSocket(
            atSign: atSign,
            rootDomain:
                AtRootDomain(preference.rootDomain, preference.rootPort),
            transport: secureSocketTransport(SecureSocketConfig()
              ..decryptPackets = preference.decryptPackets
              ..pathToCerts = preference.pathToCerts
              ..tlsKeysSavePath = preference.tlsKeysSavePath),
            // Reproduces exactly what Monitor's own PKAM did: the same
            // AtChops, the same signing and hashing algorithms, the same
            // enrollment id. `null` when there is no signer, which fails the
            // same way the old code did - it threw at connect time rather
            // than authenticating with nothing.
            authenticator: chops == null
                ? null
                : authenticatorForChops(
                    atSign,
                    chops,
                    enrollmentId: atClient.enrollmentId,
                    signingAlgo: signingAlgoOf(atClient),
                    hashingAlgo: preference.hashingAlgoType,
                  ),
            secondaryAddressFinder: this.secondaryAddressFinder,
          ),
          handleNotification: handleNotificationReceipt,
          getLastNotificationTime: getLastNotificationTime,
        );

    lastReceivedNotificationAtKey = AtKey.local(
            lastReceivedNotificationKey, atClient.getCurrentAtSign()!,
            namespace: atClient.getPreferences()!.namespace)
        .build();
    // Here, not at the first park: the filing stream is broadcast and is not
    // replayed, so subscribing only once a notification has already failed to
    // decrypt could miss the very filing that would release it.
    _listenForFilings();
  }

  /// How every write of the last-received-notification watermark is routed.
  ///
  /// The watermark is a `local:` record — never synced, and already encrypted
  /// at rest by the keystore — so there is nothing for value-level encryption
  /// to protect. Saying so explicitly keeps these writes off the shared-data
  /// crypto path, which is where a client that refuses legacy encryption used
  /// to have them refused: every post-quantum provider declines a local key,
  /// and the fallback from that decline is legacy.
  ///
  /// A fresh instance per call: [PutRequestOptions] is mutable and the put
  /// pipeline may rewrite the options it is handed.
  static PutRequestOptions get _watermarkPutOptions =>
      PutRequestOptions()..shouldEncrypt = false;

  /// What gets persisted as the watermark: the notification minus its payload
  /// and its metadata blob.
  ///
  /// Only `epochMillis` is ever read back — see [getLastNotificationTime] —
  /// and the remaining fields are kept because they cost little and make the
  /// record legible to someone working out why a monitor replayed from where
  /// it did. `value` and `metadata` are dropped: `value` is the notification
  /// payload, bounded only by [AtClientPreference.maxDataSize], rewritten on
  /// every notification, and held here without value-level encryption.
  static String _watermarkValue(AtNotification n) => jsonEncode(n.toJson()
    ..remove('value')
    ..remove('metadata'));

  /// Migrate any legacy (non-`local:`) forms of the
  /// last-received-notification key to the canonical
  /// `local:lastreceivednotification.<ns>@<atSign>` form, and delete
  /// every legacy form found so they no longer pollute the local
  /// keystore.
  ///
  /// Fixes the underlying defect behind #1942 — `AtCollection`
  /// regex scans over the local keystore were matching the bare
  /// (non-`local:`) `lastreceivednotification.<ns>@<atSign>` key
  /// because it has the same structural shape as a self-owned
  /// collection item. The canonical key has been `local:`-prefixed
  /// since the move to `AtKey.local`, but clients upgraded from
  /// older builds still carry the bare form on disk.
  ///
  /// Three forms have existed:
  ///   1. `local:lastreceivednotification.<ns>@<atSign>` — canonical
  ///   2. `      lastreceivednotification.<ns>@<atSign>` — intermediate
  ///   3. `      _latestNotificationIdv2.<ns>@<atSign>`  — original
  ///
  /// If the canonical key is missing its value is seeded from the
  /// newest legacy form that has one (preferring the intermediate
  /// over the original — its value is fresher). Every legacy entry
  /// is then deleted. The migration is idempotent: re-running it
  /// after a clean DB is a no-op.
  ///
  /// Deletes are local-only — both legacy name prefixes are
  /// excluded by `SyncUtil.shouldSync`, so the removals do not
  /// propagate to the atServer.
  /// Returns the canonical value after migration. The seeded value
  /// is returned directly (rather than re-read by the caller) so the
  /// `put` we just did doesn't have to round-trip back through a
  /// `get` — useful both for performance and because some mocks /
  /// fakes aren't stateful across the put-then-get.
  @visibleForTesting
  Future<AtValue?> migrateLegacyLastReceivedNotificationKeysForTest() =>
      _migrateLegacyLastReceivedNotificationKeys();

  Future<AtValue?> _migrateLegacyLastReceivedNotificationKeys() async {
    final keyStore = atClient.getLocalSecondary()!.keyStore!;
    final ns = atClient.getPreferences()!.namespace;
    final currentAtSign = atClient.getCurrentAtSign()!;
    final canonicalStr = lastReceivedNotificationAtKey.toString();

    // The canonical key can exist with a null value (e.g. when an
    // earlier `put` seeded a placeholder). Check the actual value,
    // not just existence — otherwise we'd never seed from a legacy
    // form when the canonical row is present-but-empty.
    AtValue? canonicalValue;
    if (await keyStore.exists(canonicalStr)) {
      try {
        canonicalValue = await atClient.get(lastReceivedNotificationAtKey);
        if (canonicalValue.value == null) canonicalValue = null;
      } on Exception {
        // Treat read failures as "needs seeding" — the legacy
        // forms become the source of truth.
      }
    }

    // Newest legacy form first so we prefer fresher values when
    // seeding the canonical key.
    final legacyForms = <String>[
      'lastreceivednotification.$ns$currentAtSign',
      '$notificationIdKey.$ns$currentAtSign',
    ];
    for (final legacyStr in legacyForms) {
      if (!await keyStore.exists(legacyStr)) continue;

      // Seed the canonical key from the first legacy form that has a
      // value — only when the canonical doesn't already carry one.
      if (canonicalValue == null) {
        try {
          final v = await atClient.get(AtKey.fromString(legacyStr));
          if (v.value != null) {
            await atClient.put(lastReceivedNotificationAtKey, v.value,
                putRequestOptions: _watermarkPutOptions);
            canonicalValue = v;
          }
        } on Exception catch (e) {
          logger.warning(
              'Migration: failed to seed canonical key from $legacyStr: $e');
        }
      }

      // Drop the legacy key regardless of whether we seeded from it
      // — older forms are no longer load-bearing once the canonical
      // exists, and pollute the local keystore (#1942).
      try {
        await atClient.delete(AtKey.fromString(legacyStr));
      } on Exception catch (e) {
        logger.warning('Migration: failed to delete legacy key $legacyStr: $e');
      }
    }
    return canonicalValue;
  }

  /// Return the last received notification DateTime in epochMillis when
  /// [AtClientPreference.fetchOfflineNotifications] is set true.
  ///
  /// Returns null when the key which holds the lastNotificationReceived
  /// does not exist.
  @visibleForTesting
  Future<int?> getLastNotificationTime() async {
    if (atClient.getPreferences()!.fetchOfflineNotifications == false) {
      // fetchOfflineNotifications == false means issue `monitor` command without a lastNotificationTime
      // which will result in the server not sending any previously received notifications
      return null;
    }

    // Migration runs first and returns the canonical key's value
    // (either the pre-existing value or one freshly seeded from a
    // legacy form). Use that directly instead of re-reading the
    // canonical key — the migration has already done that work.
    AtValue? atValue = await _migrateLegacyLastReceivedNotificationKeys();
    if (atValue?.value != null) {
      logger.finer('json from hive: ${atValue?.value}');
      return jsonDecode(atValue?.value)['epochMillis'];
    }

    // First-call branch: no last-received-notification record exists.
    // Set the record to "now" so that subsequent calls (after a
    // restart, say) will return a value, but return null for THIS
    // call to keep first-run semantics ("don't replay history I never
    // saw"). Without this seed, a short-lived first session followed
    // by a longer second session would silently miss any notifications
    // that arrived in between.
    AtNotification n = AtNotification(
      'abcd-123456-wxyz',
      '@bob:notification.foo.bar.baz@alice',
      '@alice',
      '@bob',
      DateTime.now().millisecondsSinceEpoch,
      MessageTypeEnum.key.toString(),
      false,
      value: 'placeholder',
      metadata: Metadata(),
    );
    // Best-effort, like the other two writes of this key. The watermark is an
    // optimisation — it exists so a restart does not replay history — so
    // failing to seed it costs one replayed window. Letting the failure out of
    // here would reach `Monitor.stayConnected`, which treats anything thrown
    // during its connect sequence as a failed connection and retries forever.
    try {
      await atClient.put(lastReceivedNotificationAtKey, _watermarkValue(n),
          putRequestOptions: _watermarkPutOptions);
    } catch (e) {
      logger.warning('Failed to seed the last-received-notification '
          'watermark; the next monitor connect will seed it again: $e');
    }

    return null;
  }

  @visibleForTesting
  bool isStopped = false;

  Future<void> stop() async {
    stopAllSubscriptions();
  }

  @override
  void stopAllSubscriptions({bool stopNotificationsListener = true}) {
    if (isStopped) {
      logger.info(
          'stopAllSubscriptions() called, but service is already stopped. Ignoring.');
      return;
    }
    isStopped = true;

    if (stopNotificationsListener) {
      stopListening();
    }

    unawaited(_filingSubscription?.cancel());
    _filingSubscription = null;
    // Anything still parked is now unreachable: its subscriber's controller is
    // about to close. Say what is being lost rather than letting it vanish with
    // the object.
    final stranded = _parked.values.fold<int>(0, (sum, l) => sum + l.length);
    if (stranded > 0) {
      logger.warning('Discarding $stranded parked notification(s) on shutdown: '
          'the nskey privates they were waiting for never arrived');
    }
    _parked.clear();

    _streamListeners.forEach((regex, streamController) {
      if (!streamController.isClosed) {
        streamController.close();
      }
    });
    _streamListeners.clear();
  }

  final notificationParser = NotificationResponseParser();

  @visibleForTesting
  Future<void> handleNotificationReceipt(String notificationJSON) async {
    try {
      logger.finest('DEBUG: $notificationJSON');
      if (isStopped) return;

      final notifs = notificationParser
          .getAtNotifications(notificationParser.parse(notificationJSON));
      _lastReceipt = DateTime.now().toUtc();
      for (var n in notifs) {
        if (n.key == myStatsNotifKey) {
          logger.finer('Received ${n.key} (serverCommitId) ${n.value}');
        } else {
          logger.info('Received ${n.key}');
        }
        // Saves latest notification id to the keys if its not a stats notification.
        if (n.id != '-1') {
          try {
            await atClient.put(
                lastReceivedNotificationAtKey, _watermarkValue(n),
                putRequestOptions: _watermarkPutOptions);
          } catch (e) {
            logger.warning('Failed to save last received notification ID: $e');
          }
        }
        // ⚠️ A `for` loop, not `_streamListeners.forEach`. `Map.forEach` takes
        // a **void** callback and discards the Future an `async` one returns,
        // so every `await` below ran detached: transforms for successive
        // notifications interleaved and the enclosing `for (var n in notifs)`
        // ran ahead of them.
        //
        // What awaiting buys is ORDERED delivery, which the values depend on:
        // a content key is conveyed before the value citing it, and a
        // subscriber that processes them out of order sees a value it cannot
        // open. It also means a transform whose Future is abandoned can no
        // longer produce no delivery, no drop and no log line at once.
        //
        // No test demonstrates the old behaviour losing a notification. It was
        // changed because the discarded Future is a defect on its face, and
        // because a live failure that looked like it (a self notification the
        // monitor received and the subscriber never saw) sent three
        // investigations here. That failure turned out to be something else
        // entirely, and this change did not fix it.
        //
        // `.toList()` because the map may now be mutated while this awaits —
        // a subscriber registering or cancelling mid-notification would
        // otherwise throw ConcurrentModificationError.
        for (final entry in _streamListeners.entries.toList()) {
          final notificationConfig = entry.key;
          final streamController = entry.value;
          try {
            await _deliver(n, notificationConfig, streamController);
          } on NskeyPrivateUnavailableException catch (e) {
            // Not a failure: the private is conveyed at approval and filed
            // asynchronously, so this value is openable as soon as it lands.
            // Dropping it here loses a message whose key arrives moments later.
            _park(e, n, notificationConfig, streamController);
          } catch (e) {
            // Warning, not finer. A notification that cannot be transformed is
            // dropped here and never retried — nothing re-delivers it when the
            // missing piece arrives. At finer the subscriber saw an absence
            // indistinguishable from one that was never sent, which is how a
            // conveyance racing its own announcement stayed invisible through
            // a green unit suite and a green e2e suite alike.
            logger.warning('Dropping notification ${n.key} for subscriber '
                '(regex "${notificationConfig.regex}"): $e');
          }
        }
      }
    } catch (e) {
      logger.severe('unexpected error:${e.toString()}'
          ' while processing notificationJson: $notificationJSON');
    }
  }

  /// The record's name below the owner, from whichever parameter carried it.
  ///
  /// Rejects a name with no interior dot rather than letting it through. Such a
  /// name has no namespace, so no post-quantum scheme can serve it and the
  /// write falls back to legacy — which a client that refuses legacy then
  /// declines, three layers below the call, in a message about encryption
  /// rather than about the argument. An id in no namespace is not something
  /// this method can send, and saying so here is the only place a caller can
  /// act on it.
  static String _requireOneName(String? idAndNamespace, String? namespace) {
    final name = idAndNamespace ?? namespace;
    if (idAndNamespace != null && namespace != null) {
      throw ArgumentError(
          'Supply idAndNamespace or namespace, not both — they name the same '
          'value and namespace is the deprecated spelling.');
    }
    if (name == null || name.isEmpty) {
      throw ArgumentError('You must supply idAndNamespace.');
    }
    final dot = name.indexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      throw ArgumentError(
          'idAndNamespace must be an id and a namespace joined by a dot, with '
          'both non-empty — for example "order42.orders.my_app". Got "$name". '
          'The part after the first dot is the namespace, and it is what the '
          'notification is encrypted under.');
    }
    return name;
  }

  @override
  Future<String> send({
    required Atsign to,
    String? idAndNamespace,
    @Deprecated('Renamed to idAndNamespace') String? namespace,
    String body = '',
    bool shouldEncrypt = true,
    Duration expiration = NotificationService.defaultExpiration,
    bool cacheAtRecipient = false,
    String? cryptoProviderId,
    DateTime? recipientCacheExpiration,
  }) async {
    if (cacheAtRecipient && recipientCacheExpiration == null) {
      throw ArgumentError(
          'You must supply recipientCacheExpiration when cacheAtRecipient is true');
    }
    // ignore: deprecated_member_use_from_same_package
    final String name = _requireOneName(idAndNamespace, namespace);
    final String key = '$to:$name$atSign';
    final AtKey atKey = AtKey.fromString(key);
    atKey.metadata.namespaceAware = false;
    // The name is an id and a namespace joined by a dot, so the split is at the
    // FIRST dot — everything after it is the namespace, and the namespace is
    // what scopes the encryption key.
    //
    // `AtKey.fromString` cannot be left to do this: it cuts at the LAST dot, so
    // it hands back `a.b` + `c` where the caller said `a` + `b.c`, and for a
    // two-segment name it leaves no namespace at all — which every
    // post-quantum provider declines, sending the write to legacy.
    //
    // Overwriting the two fields does not disturb the ciphertext binding: it is
    // computed over the name and namespace rejoined, precisely because writer
    // and reader split it differently, so both sides still derive
    // `$name`.
    final int dot = name.indexOf('.');
    atKey
      ..key = name.substring(0, dot)
      ..namespace = name.substring(dot + 1);
    final String notifPayload;
    body = body.trim();
    if (body.isNotEmpty && shouldEncrypt) {
      // Same fallback as the put pre-pass and as notify(NotificationParams):
      // an app that opted into reaching a recipient under legacy meant its
      // data, not one verb. Stamped only once the routing is settled.
      String providerId;
      try {
        providerId = await CryptoRuntime(atClient).prepareWrite(atKey,
            requestedProviderId: cryptoProviderId,
            useRemoteAtServer: true,
            stampProviderId: false);
      } on NamespaceKeyUnavailableException catch (e) {
        if (!CryptoRuntime.mayFallBackToLegacy(atClient.getPreferences())) {
          rethrow;
        }
        logger.warning('falling back to legacy encryption for the '
            'notification of $name: ${e.message}');
        providerId = await CryptoRuntime(atClient).prepareWrite(atKey,
            requestedProviderId: CryptoRuntime.legacyProviderId,
            useRemoteAtServer: true,
            stampProviderId: false);
      }
      atKey.metadata.appMetadata ??= AppMetadata(providerId: providerId);
      notifPayload =
          await CryptoRuntime(atClient).encryptForNotification(atKey, body);
      atKey.metadata.isEncrypted = true;
    } else {
      notifPayload = body;
      atKey.metadata.isEncrypted = false;
    }

    if (cacheAtRecipient) {
      atKey.metadata.ttr = -1;
      int ttl = recipientCacheExpiration!.millisecondsSinceEpoch -
          DateTime.now().millisecondsSinceEpoch;
      if (ttl < 0) {
        ttl = 1;
      }
      atKey.metadata.ttl = ttl;
    }

    // The same builder every other notification path goes through. This method
    // used to compose the command itself, which is how it came to resolve its
    // own namespace and get it wrong.
    //
    // [NotifyVerbBuilder.useAtKeyToString] is required, not incidental: the
    // field-by-field form writes `:${atKey.key}`, and the name here is split
    // across `key` and `namespace`, so it would put only the id on the wire.
    final builder = NotifyVerbBuilder()
      ..atKey = atKey
      ..ttln = expiration.inMilliseconds
      ..value = notifPayload.isEmpty ? null : notifPayload
      ..useAtKeyToString = true;

    logger.info('SENDING: $key');

    await atClient
        .getRemoteSecondary()
        ?.executeCommand(builder.buildCommand(), auth: true);

    return builder.id;
  }

  @override
  Stream<AtNotification> subscribeFiltered({
    Set<Atsign>? acceptedSenders,
    required String namespace,
  }) {
    String r = '^$atSign:([^.]+\\.)?$namespace@';
    // Single-subscription controller. Its onPause/onResume hooks are
    // deliberately NOT wired to pause the upstream subscription:
    // [subscribe] returns a broadcast stream, and broadcast
    // subscriptions DO NOT buffer events emitted during pause()
    // (events are delivered to other live subscribers and dropped
    // for the paused one). When the downstream consumer pauses
    // [sc.stream], the single-sub controller buffers incoming
    // notifications internally; we keep accepting from upstream
    // and adding to the controller, and the controller delivers
    // the buffered notifications when the consumer resumes.
    StreamController<AtNotification> sc = StreamController<AtNotification>();
    StreamSubscription<AtNotification>? notifStreamSubscription;
    sc.onListen = () {
      Stream<AtNotification> notifStream = subscribe(
        regex: r,
        shouldDecrypt: true,
      );
      notifStreamSubscription = notifStream.listen((AtNotification n) async {
        if (acceptedSenders == null || acceptedSenders.contains(n.from)) {
          sc.add(n);
        } else {
          logger.warning('Ignored notification ${n.key}');
        }
      });
    };
    sc.onCancel = () {
      notifStreamSubscription?.cancel();
    };
    return sc.stream;
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus = true,
      bool checkForFinalDeliveryStatus = true,
      bool encryptValue = true,
      Function(NotificationResult)? onSuccess,
      Function(NotificationResult)? onError,
      Function(NotificationResult)? onSentToSecondary}) async {
    var notificationResult = NotificationResult()
      ..notificationID = notificationParams.id
      ..atKey = notificationParams.atKey;

    notificationParams.atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();

    try {
      notificationParams.atKey.metadata.isEncrypted = encryptValue;
      // If sharedBy atSign is null, default to current atSign.
      if (notificationParams.atKey.sharedBy.isNull) {
        notificationParams.atKey.sharedBy = atClient.getCurrentAtSign();
      }
      // Prepend '@' if not already set.
      notificationParams.atKey.sharedBy =
          AtUtils.fixAtSign(notificationParams.atKey.sharedBy!);
      // validate notification request
      await atClientValidation.validateNotificationRequest(
          secondaryAddressFinder,
          notificationParams,
          atClient.getPreferences()!,
          atClient.getCurrentAtSign()!);
      // Get the NotifyVerbBuilder from NotificationParams
      var builder = await NotificationRequestTransformer(atClient)
          .transform(notificationParams);

      notificationValueValidation(notificationParams, builder);
      // Run the notify verb on the remote secondary instance.
      await atClient.getRemoteSecondary()?.executeVerb(builder);
      if (onSentToSecondary != null) {
        onSentToSecondary(notificationResult);
      }
    } on AtException catch (e) {
      // Setting notificationStatusEnum to errored
      notificationResult.notificationStatusEnum =
          NotificationStatusEnum.undelivered;
      notificationResult.atClientException =
          AtExceptionManager.createException(e);
      // Invoke onErrorCallback
      if (onError != null) {
        onError(notificationResult);
      }
    }
    if (!checkForFinalDeliveryStatus) {
      // don't do polling if we don't need to
      return notificationResult;
    } else {
      if (waitForFinalDeliveryStatus) {
        await _waitForAndHandleFinalNotificationSendStatus(
            notificationParams, notificationResult, onSuccess, onError);
        return notificationResult;
      } else {
        // no wait? no await
        unawaited(_waitForAndHandleFinalNotificationSendStatus(
            notificationParams, notificationResult, onSuccess, onError));
        return notificationResult;
      }
    }
  }

  /// Checks the size the notification value. If the size exceeds the [AtClientPreference.maxDataSize]
  /// [BufferOverFlowException] is thrown.
  ///
  @visibleForTesting
  void notificationValueValidation(
      NotificationParams notificationParams, NotifyVerbBuilder builder) {
    // ignore: deprecated_member_use_from_same_package
    switch (notificationParams.messageType) {
      case MessageTypeEnum.key:
        // Since value is not mandatory in AtNotification, perform validation only if
        // value is not null.
        if (builder.value != null &&
            builder.value.length > atClient.getPreferences()!.maxDataSize) {
          throw BufferOverFlowException(
              'The length of value exceeds the maximum allowed length. Maximum buffer size is ${atClient.getPreferences()!.maxDataSize} bytes. Found ${builder.value.toString().length} bytes');
        }
        break;

      // ignore: deprecated_member_use
      case MessageTypeEnum.text:
        // When messageType is text, the "text" to notify is added to the key. Hence validating
        // the key length
        if (builder.atKey.key.length > atClient.getPreferences()!.maxDataSize) {
          throw BufferOverFlowException(
              'The length of value exceeds the maximum allowed length. Maximum buffer size is ${atClient.getPreferences()!.maxDataSize} bytes. Found ${builder.value.toString().length} bytes');
        }
        break;
    }
  }

  Future<void> _waitForAndHandleFinalNotificationSendStatus(
      NotificationParams notificationParams,
      NotificationResult notificationResult,
      Function? onSuccess,
      Function? onError) async {
    var notificationParser = NotificationResponseParser();
    // Gets the notification status and parse the response.
    var notificationStatus = notificationParser
        .parse(await _getFinalNotificationStatus(notificationParams.id));
    switch (notificationStatus.response) {
      case 'delivered':
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.delivered;
        // If onSuccess callback is registered, invoke callback method.
        if (onSuccess != null) {
          onSuccess(notificationResult);
        }
        break;
      case 'undelivered':
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.undelivered;
        notificationResult.atClientException = AtClientException(
            error_codes['AtClientException'],
            'Unable to connect to secondary server');
        // If onError callback is registered, invoke callback method.
        if (onError != null) {
          onError(notificationResult);
        }
        break;
    }
  }

  /// Queries the status of the notification
  /// Takes the notificationId as input as returns the status of the notification
  Future<String> _getFinalNotificationStatus(String notificationId) async {
    String status = '';
    bool firstCheck = true;
    // For every 2 seconds, queries the status of the notification
    while (status.isEmpty || status == 'data:queued') {
      if (firstCheck) {
        await Future.delayed(Duration(milliseconds: 500));
        firstCheck = false;
      } else {
        await Future.delayed(Duration(seconds: 2));
      }
      status = await atClient.notifyStatus(notificationId);
    }
    return status;
  }

  @visibleForTesting
  Timer? delayedStartListeningTimer;

  @visibleForTesting
  Duration? delayedStartListeningTimerDuration;

  @override
  Stream<AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    logger.finer('subscribe(regex: $regex, shouldDecrypt: $shouldDecrypt');
    regex ??= emptyRegex;
    var notificationConfig = NotificationConfig()
      ..regex = regex
      ..shouldDecrypt = shouldDecrypt;
    var atNotificationStream = _streamListeners.putIfAbsent(
        notificationConfig, () => StreamController<AtNotification>.broadcast());

    // Temporary fix for https://github.com/atsign-foundation/at_client_sdk/issues/770
    //     (Temporary because it's a bit of a kludge, but the proper fix requires the implementation
    //      of enhancements to the monitor verb which allow for multiple subscriptions, and changes
    //      to this service and to the Monitor to make use of that enhancement.)
    // Previously we were initializing the notification service
    // before there were any 'real' subscriptions
    // and because the notification service currently starts the monitor
    // without any regex, the monitor immediately starts to stream all notifications
    //
    // As a result, if there is even a very short delay between when the notification service
    // is created and when the app calls 'subscribe', then the app will 'miss'
    // those notifications.
    //
    // So - for now, if the subscription is 'statsNotification', then we will delay
    // initialization of the service until when the app does a real 'subscribe' call.
    //
    // Normally, the app code will call subscribe which will
    // start the monitor, and SyncService will start receiving statsNotifications.
    // However, if the app isn't explicitly calling 'sync', and hasn't called subscribe(),
    // then there will be a delay of 30 seconds before the monitor is started, the first
    // statsNotification message is received, and a sync request is queued.
    // In order to compensate for that, the SyncServiceImpl itself now queues a sync request
    // when it is initialized.
    //
    // Additionally, in order to give application code full control over the
    // lifecycle of the notifications listener, we will only start the monitor
    // for subscriptions when AtClientPreference.monitorAutoStart is true,
    // which it is by default (legacy behaviour). This gives application code
    // much better clear control over the notification listening lifecycle.
    if (atClient.getPreferences()?.monitorAutoStart == true) {
      if (regex == 'statsNotification') {
        delayedStartListeningTimerDuration ??= Duration(seconds: 30);
        delayedStartListeningTimer =
            Timer(delayedStartListeningTimerDuration!, startListening);
      } else {
        startListening();
      }
    }
    return atNotificationStream.stream as Stream<AtNotification>;
  }

  /// Ensures that distinct [NotificationConfig.regex] exists in the key
  /// Compares the [NotificationConfig] object with [NotificationConfig.regex]
  /// If regex's are equals, returns true; else false.
  static bool _compareNotificationConfig(NotificationConfig notificationConfig1,
      NotificationConfig notificationConfig2) {
    if (notificationConfig1.regex == notificationConfig2.regex) {
      return true;
    }
    return false;
  }

  /// Returns the hashcode for the [NotificationConfig.regex]
  static int _generateHashCode(NotificationConfig notificationConfig) {
    return notificationConfig.regex.hashCode;
  }

  @override
  Future<NotificationResult> getStatus(String notificationId) async {
    var status = await atClient.notifyStatus(notificationId);
    var atResponse = DefaultResponseParser().parse(status);
    NotificationResult notificationResult;
    // If the Notification Response is error, set the notification status to undelivered
    if (atResponse.isError) {
      return NotificationResult()
        ..notificationID = notificationId
        ..notificationStatusEnum = NotificationStatusEnum.undelivered
        ..atClientException = AtClientException(
            atResponse.errorCode, atResponse.errorDescription);
    }

    notificationResult = NotificationResult()
      ..notificationID = notificationId
      ..notificationStatusEnum =
          _getNotificationStatusEnum(atResponse.response);
    return notificationResult;
  }

  /// Returns the NotificationStatusEnum for the given string of notificationStatus
  NotificationStatusEnum _getNotificationStatusEnum(String notificationStatus) {
    switch (notificationStatus.toLowerCase()) {
      case 'delivered':
        return NotificationStatusEnum.delivered;
      case 'undelivered':
        return NotificationStatusEnum.undelivered;
      default:
        return NotificationStatusEnum.undelivered;
    }
  }

  ///Not a part of API. Exposed for unit test
  @visibleForTesting
  int getStreamListenersCount() {
    return _streamListeners.length;
  }

  @override
  Future<AtNotification> fetch(String notificationId) async {
    var notifyFetchVerbBuilder = NotifyFetchVerbBuilder()
      ..notificationId = notificationId;
    String? atNotificationStr;
    try {
      atNotificationStr = await atClient
          .getRemoteSecondary()
          ?.executeVerb(notifyFetchVerbBuilder);
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
    if (atNotificationStr == null) {
      throw AtClientException.message('Failed to fetch the notification id',
          intent: Intent.remoteVerbExecution,
          exceptionScenario: ExceptionScenario.remoteVerbExecutionFailed);
    }
    AtResponse atResponse = DefaultResponseParser().parse(atNotificationStr);
    var atNotificationMap = jsonDecode(atResponse.response);
    if (atNotificationMap['notificationStatus'] ==
        at_persistence_secondary_server.NotificationStatus.expired.toString()) {
      return AtNotification.empty()
        ..id = atNotificationMap['id']
        ..status = atNotificationMap['notificationStatus'];
    }
    return AtNotification.empty()
      ..id = atNotificationMap['id']
      ..key = atNotificationMap['notification']
      ..from = atNotificationMap['fromAtSign']
      ..to = atNotificationMap['toAtSign']
      ..epochMillis = DateTime.parse(atNotificationMap['notificationDateTime'])
          .millisecondsSinceEpoch
      ..status = atNotificationMap['notificationStatus']
      ..value = atNotificationMap['atValue']
      ..operation = atNotificationMap['opType']
      ..messageType = atNotificationMap['messageType']
      ..expiresAtInEpochMillis =
          DateTime.parse(atNotificationMap['expiresAt']).millisecondsSinceEpoch;
  }

  @override
  void startListening() {
    if (monitor.targetState == NotificationListenerState.listening) {
      logger.info('startListening() called, but already targeting listening');
      return;
    }
    logger.info('startListening(): starting notification listener');
    monitor.start();
  }

  @override
  void stopListening() {
    if (delayedStartListeningTimer != null) {
      delayedStartListeningTimer!.cancel();
      delayedStartListeningTimer = null;
    }
    if (monitor.targetState == NotificationListenerState.notConnected) {
      logger.info('stopListening() called, but'
          ' target state is already ${monitor.targetState}');
      return;
    }

    logger.info('stopListening() called: stopping notification listener');
    monitor.stop();
  }

  @override
  NotificationListenerState get currentListenerState => monitor.currentState;

  @override
  NotificationListenerState get targetListenerState => monitor.targetState;

  @override
  DateTime? get lastReceipt => _lastReceipt;

  @override
  Stream<NotificationListenerState> get currentListenerStateStream =>
      monitor.currentStateStream;
}

/// One notification held back, with everything needed to deliver it later.
///
/// Holds the subscriber's [StreamController] rather than looking it up at
/// re-drive time: a subscriber that cancelled while its notification was parked
/// must not have someone else's controller handed its value.
class _ParkedNotification {
  final AtNotification notification;
  final NotificationConfig config;
  final StreamController controller;
  final DateTime parkedAt;

  _ParkedNotification(
      this.notification, this.config, this.controller, this.parkedAt);
}
