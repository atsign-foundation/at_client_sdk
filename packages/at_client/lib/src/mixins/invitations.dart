import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show DeleteRequestOptions, GetRequestOptions, PutRequestOptions;
import 'package:at_client/src/collections/collections.dart'
    show AtCollection, CItem;
import 'package:at_client/src/invitations/invitation_key.dart';
import 'package:at_client/src/invitations/invitation_link.dart';
import 'package:at_client/src/invitations/models.dart';
import 'package:at_commons/at_commons.dart'
    show AtKey, AtKeyNotFoundException, Atsign, AtsignString, StoppedException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:crypto/crypto.dart' show sha256;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// What [Invitations.invite] hands back for the inviter to send, out of band.
@experimental
class CreatedInvitation {
  final InvitationLink link;

  /// The short code, to send separately from the link.
  final String code;

  /// The encrypted content, when it travels out of band rather than in the
  /// preview record, e.g. as the body of an email.
  final SealedInvitationContent? outOfBandContent;

  const CreatedInvitation({
    required this.link,
    required this.code,
    this.outOfBandContent,
  });
}

/// What happened to one acceptance in an [Invitations.processAcceptances]
/// pass.
///
/// [handledElsewhere] means an earlier pass, on this client or another of
/// this atSign's, already handled it. [alreadyDecided] means the invitation
/// was decided some other way.
@experimental
enum InvitationOutcome {
  accepted,
  wrongCode,
  burned,
  expired,
  alreadyDecided,
  handledElsewhere,
}

/// Where [inviter] publishes the preview of invitation [id]:
/// `public:_<id>.invitations.<namespace><inviter>`.
///
/// A `public:_…` record is never listed by a scan, so only someone holding
/// the invitation id can read it.
@visibleForTesting
AtKey invitationPreviewKey(Atsign inviter, String id, String namespace) =>
    AtKey.public('_$id', namespace: 'invitations.$namespace', sharedBy: inviter)
        .build();

/// Invitations between atSigns, including to someone who has no atSign yet.
///
/// The inviter creates an invitation, sends its link and its code out of
/// band, and the invitee accepts once they have an atSign. Any of the
/// inviter's clients can then process the acceptance, and every decision two
/// clients could race on is an immutable create on the inviter's atServer,
/// which refuses the second writer:
///
/// - an **outcome** per invitation — accepted, burned or revoked — so an
///   invitation is decided once, whichever of those gets there first;
/// - an **attempt slot** per wrong code, so the count cannot lose an update;
///   the wrong code after the last slot is the burn itself;
/// - a **claim** per acceptance that cannot decide the invitation, a wrong
///   code or one that arrived after expiry, so it is counted once.
///
/// Each of these lives as long as the invitation's own record. The content
/// key goes only to an atSign whose acceptance carries the code, whatever
/// the outcome record says.
///
/// The app's own data travels as JSON: public details in the preview, the
/// invitee's details in the acceptance, and private content encrypted under
/// a fresh content key. The invitee holds the ciphertext before accepting,
/// and the key is shared with them only once the inviter has verified their
/// acceptance. Everything else the app keeps, contacts included, lives in
/// the app's own collections, keyed by the invitation id.
///
/// Nothing here needs Flutter. An app or a CLI uses it through
/// [AtClientInvitations], and an always-on process, such as a CLI helper
/// enrolled for the namespace, handles acceptances by calling
/// [processAcceptances] on a timer or on [acceptances] events:
///
/// ```dart
/// final invitations =
///     AtClientInvitations(atClient, invitationsNamespace: 'my_app');
/// final created = await invitations.invite(
///     publicDetails: {'from': 'Alice'}, content: {'recipe': 'lemon cake'});
/// // Send created.link and created.code separately.
/// ```
@experimental
mixin Invitations {
  AtClient get atClient;

  AtSignLogger get logger;

  /// The app namespace the invitation records live under.
  String get invitationsNamespace;

  /// Wrong codes allowed before an invitation is burned.
  static const int attemptLimit = 5;

  /// How long an invitation's records outlive its expiry, so that its fate
  /// stays visible for a while.
  static const Duration _afterExpiry = Duration(days: 30);

  Atsign get me => atClient.getCurrentAtSign()!.toAtsign();

  /// Invitations this atSign sent. Only this atSign reads them.
  Future<AtCollection<SentInvitation>> get sentInvitations => _collection(
      'sent.invitations', SentInvitation.fromJson, 'SentInvitation');

  /// Invitations this atSign received. Only this atSign reads them.
  Future<AtCollection<ReceivedInvitation>> get receivedInvitations =>
      _collection('received.invitations', ReceivedInvitation.fromJson,
          'ReceivedInvitation');

  /// Acceptances, each shared by an invitee with its inviter.
  Future<AtCollection<InvitationAcceptance>> get acceptances => _collection(
      'acceptances.invitations',
      InvitationAcceptance.fromJson,
      'InvitationAcceptance');

  /// Confirmations, each shared by an inviter with the invitee it accepted.
  Future<AtCollection<InvitationConnection>> get connections => _collection(
      'connections.invitations',
      InvitationConnection.fromJson,
      'InvitationConnection');

  // NOTE: AtClient.collection caches one instance per namespace, so these
  // are opened once however often they are asked for.
  Future<AtCollection<T>> _collection<T>(String name,
          T Function(Map<String, dynamic>) fromJson, String typeTag) =>
      atClient.collection<T>(
        '$name.$invitationsNamespace',
        const Duration(days: 30),
        fromJson: fromJson,
        typeTag: typeTag,
      );

  // ---------------------------------------------------------------------------
  // The inviter

  /// Creates an invitation. The app links its own records, such as a
  /// contact, to it by the id in the returned link.
  ///
  /// [publicDetails] travel in the preview, so anyone holding the link reads
  /// them; anything private belongs in [content], which is encrypted and
  /// fixed here. With [contentOutOfBand] the encrypted content is returned
  /// for the app to send alongside the link rather than published in the
  /// preview.
  Future<CreatedInvitation> invite({
    Map<String, dynamic> publicDetails = const {},
    Map<String, dynamic>? content,
    bool contentOutOfBand = false,
    Duration expiresIn = const Duration(days: 7),
  }) async {
    final id = _randomHex(16);
    final code = _randomCode();
    final expiresAt = DateTime.now().toUtc().add(expiresIn);

    InvitationKey? contentKey;
    SealedInvitationContent? sealed;
    if (content != null) {
      contentKey = InvitationKey.mint();
      sealed = await contentKey.seal(jsonEncode(content),
          inviter: me, invitationId: id);
    }

    await (await sentInvitations).create(
      id: id,
      obj: SentInvitation(
        code: code,
        expiresAt: expiresAt,
        publicDetails: publicDetails,
        contentKey: contentKey?.base64,
      ),
      expiresAt: expiresAt.add(_afterExpiry),
    );

    final preview = InvitationPreview(
      publicDetails: publicDetails,
      expiresAt: expiresAt,
      content: contentOutOfBand ? null : sealed,
    );
    final previewKey = _previewKey(me, id);
    previewKey.metadata.ttl = expiresIn.inMilliseconds;
    await atClient.put(
      previewKey,
      jsonEncode(preview.toJson()),
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );

    return CreatedInvitation(
      link: InvitationLink(inviter: me, id: id),
      code: code,
      outOfBandContent: contentOutOfBand ? sealed : null,
    );
  }

  /// Cancels a pending invitation. Returns false when it had already been
  /// decided — accepted, burned or revoked.
  Future<bool> revoke(String id) async {
    final item = await (await sentInvitations).get(id, me);
    if (!await _createOnce(_outcomeKey(id), 'revoked', item)) return false;
    await _finishDecision(item, SentInvitationStatus.revoked);
    return true;
  }

  /// Handles every acceptance of this atSign's pending invitations, and
  /// finishes any invitation a client decided but did not finish. Reports
  /// each acceptance it handled; one of an invitation already decided is not
  /// reported again.
  ///
  /// A record it cannot read, or an acceptance it cannot handle, is logged
  /// and skipped, so it cannot hold up the others.
  Future<
      List<
          ({
            CItem<InvitationAcceptance> acceptance,
            InvitationOutcome outcome
          })>> processAcceptances() async {
    final results = <({
      CItem<InvitationAcceptance> acceptance,
      InvitationOutcome outcome
    })>[];
    final received = [
      for (final a in await _readable(await acceptances))
        if (a.owner != me) a
    ];
    for (final acceptance in received) {
      try {
        final outcome = await _process(acceptance);
        if (outcome != null) {
          results.add((acceptance: acceptance, outcome: outcome));
        }
      } on StoppedException {
        rethrow;
      } catch (e) {
        logger.warning(
          'Could not handle the acceptance ${acceptance.id} from '
          '${acceptance.owner}: $e',
        );
      }
    }
    await _finishDecided(received);
    return results;
  }

  Future<InvitationOutcome?> _process(
      CItem<InvitationAcceptance> acceptance) async {
    final id = acceptance.obj.invitationId;
    final invitation = await (await sentInvitations).getOrNull(id, me);
    if (invitation == null) {
      logger.warning(
        'Ignoring an acceptance from ${acceptance.owner} of $id, which is '
        'not an invitation $me sent',
      );
      return null;
    }
    if (invitation.obj.status != SentInvitationStatus.pending) return null;

    final expired = DateTime.now().toUtc().isAfter(invitation.obj.expiresAt);
    if (!expired && _sameCode(acceptance.obj.code, invitation.obj.code)) {
      return _decideAccepted(invitation, acceptance);
    }
    // NOTE: only an acceptance that cannot decide the invitation takes a
    // claim. A claim taken before a decision would strand the acceptance if
    // the decision then failed.
    if (!await _createOnce(_claimKey(acceptance), 'claimed', invitation)) {
      return InvitationOutcome.handledElsewhere;
    }
    return expired ? InvitationOutcome.expired : _countWrongCode(invitation);
  }

  Future<InvitationOutcome> _decideAccepted(
    CItem<SentInvitation> invitation,
    CItem<InvitationAcceptance> acceptance,
  ) async {
    final outcome = 'accepted:${acceptance.owner}';
    if (!await _createOnce(_outcomeKey(invitation.id), outcome, invitation)) {
      return await _readOutcome(invitation.id) == outcome
          ? InvitationOutcome.handledElsewhere
          : InvitationOutcome.alreadyDecided;
    }
    await _finishAccepted(invitation, acceptance.owner, acceptance.obj.details);
    return InvitationOutcome.accepted;
  }

  Future<InvitationOutcome> _countWrongCode(
    CItem<SentInvitation> invitation,
  ) async {
    for (var slot = 1; slot < attemptLimit; slot++) {
      if (await _createOnce(
          _attemptKey(invitation.id, slot), 'wrong', invitation)) {
        return InvitationOutcome.wrongCode;
      }
    }
    if (!await _createOnce(_outcomeKey(invitation.id), 'burned', invitation)) {
      return InvitationOutcome.alreadyDecided;
    }
    await _finishDecision(invitation, SentInvitationStatus.burned);
    return InvitationOutcome.burned;
  }

  /// Finishes invitations whose outcome is recorded but whose record still
  /// says pending: the client that decided them stopped part way, or this
  /// client has not caught up yet.
  Future<void> _finishDecided(
    List<CItem<InvitationAcceptance>> received,
  ) async {
    for (final invitation
        in await _readable(await sentInvitations, owner: me)) {
      if (invitation.obj.status != SentInvitationStatus.pending) continue;
      try {
        await _finishRecorded(invitation, received);
      } on StoppedException {
        rethrow;
      } catch (e) {
        logger.warning('Could not finish the invitation ${invitation.id}: $e');
      }
    }
  }

  Future<void> _finishRecorded(
    CItem<SentInvitation> invitation,
    List<CItem<InvitationAcceptance>> received,
  ) async {
    final outcome = await _readOutcome(invitation.id);
    if (outcome == null) return;
    if (outcome == 'revoked') {
      return _finishDecision(invitation, SentInvitationStatus.revoked);
    }
    if (outcome == 'burned') {
      return _finishDecision(invitation, SentInvitationStatus.burned);
    }
    if (!outcome.startsWith('accepted:')) {
      logger.warning(
          'Invitation ${invitation.id} has an unknown outcome: $outcome');
      return;
    }
    final invitee = outcome.substring('accepted:'.length).toAtsign();
    final accepted = received
        .where((a) =>
            a.owner == invitee &&
            a.obj.invitationId == invitation.id &&
            _sameCode(a.obj.code, invitation.obj.code))
        .firstOrNull;
    if (accepted == null) {
      logger.warning(
        'Invitation ${invitation.id} is recorded as accepted by $invitee, '
        'but no acceptance from $invitee with its code is here; not '
        'finishing it',
      );
      return;
    }
    await _finishAccepted(invitation, invitee, accepted.obj.details);
  }

  Future<void> _finishDecision(
    CItem<SentInvitation> invitation,
    SentInvitationStatus status,
  ) async {
    await _deletePreview(invitation.id);
    await (await sentInvitations)
        .update(_withObj(invitation, invitation.obj.withStatus(status)));
  }

  // NOTE: every step is idempotent, so a second client finishing the same
  // invitation writes the same values again.
  Future<void> _finishAccepted(
    CItem<SentInvitation> invitation,
    Atsign invitee,
    Map<String, dynamic>? acceptanceDetails,
  ) async {
    await (await connections).upsert(
      id: invitation.id,
      obj: InvitationConnection(
        invitationId: invitation.id,
        contentKey: invitation.obj.contentKey,
      ),
      sharedWith: {invitee},
      expiresAt: DateTime.now().add(_afterExpiry),
    );
    await _deletePreview(invitation.id);
    await (await sentInvitations).update(
      _withObj(
        invitation,
        invitation.obj.withStatus(
          SentInvitationStatus.accepted,
          acceptedBy: invitee,
          acceptanceDetails: acceptanceDetails,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The invitee

  /// Fetches an invitation's preview and keeps it, with its content when the
  /// content travels in the preview. [outOfBandContent] is content that
  /// travelled some other way, e.g. in an email.
  Future<CItem<ReceivedInvitation>> preview(
    InvitationLink link, {
    SealedInvitationContent? outOfBandContent,
  }) async {
    final existing = await (await receivedInvitations).getOrNull(link.id, me);
    if (existing != null && existing.obj.inviter == link.inviter) {
      if (existing.obj.sealedContent != null || outOfBandContent == null) {
        return existing;
      }
      final withContent = _withObj(
        existing,
        existing.obj.withSealedContent(outOfBandContent),
      );
      await (await receivedInvitations).update(withContent);
      return withContent;
    }
    final value = await atClient.get(
      _previewKey(link.inviter, link.id),
      getRequestOptions: GetRequestOptions()..bypassCache = true,
    );
    final preview = InvitationPreview.fromJson(jsonDecode(value.value));
    return (await receivedInvitations).upsert(
      id: link.id,
      obj: ReceivedInvitation(
        inviter: link.inviter,
        publicDetails: preview.publicDetails,
        expiresAt: preview.expiresAt,
        sealedContent: preview.content ?? outOfBandContent,
      ),
      expiresAt: preview.expiresAt.add(_afterExpiry),
    );
  }

  /// Accepts an invitation with the [code] its inviter sent separately,
  /// sending the inviter [details] of this atSign's choosing.
  ///
  /// The inviter decides; [processConnections] reports the connection once
  /// they have.
  Future<void> accept(
    InvitationLink link,
    String code, {
    Map<String, dynamic> details = const {},
    SealedInvitationContent? outOfBandContent,
  }) async {
    final invitation = await preview(link, outOfBandContent: outOfBandContent);
    await (await acceptances).create(
      obj: InvitationAcceptance(
          invitationId: link.id, code: code, details: details),
      sharedWith: {link.inviter},
      expiresAt: invitation.obj.expiresAt.add(_afterExpiry),
    );
    await (await receivedInvitations).update(
      _withObj(invitation,
          invitation.obj.withStatus(ReceivedInvitationStatus.accepted)),
    );
  }

  /// Forgets an invitation. The inviter is not told, so they never learn
  /// this atSign.
  Future<void> decline(String id) async {
    final invitation = await (await receivedInvitations).getOrNull(id, me);
    if (invitation != null) {
      await (await receivedInvitations).delete(invitation);
    }
  }

  /// Completes every invitation this atSign accepted whose inviter has
  /// confirmed it, decrypting any content, and returns those it completed.
  /// The app adds the inviter to its own contacts from these, or from any
  /// received invitation whose status is connected.
  ///
  /// A record it cannot read, or a confirmation it cannot complete, is logged
  /// and skipped, so it cannot hold up the others.
  Future<List<CItem<ReceivedInvitation>>> processConnections() async {
    final connected = <CItem<ReceivedInvitation>>[];
    for (final connection in await _readable(await connections)) {
      if (connection.owner == me) continue;
      try {
        final done = await _connect(connection);
        if (done != null) connected.add(done);
      } on StoppedException {
        rethrow;
      } catch (e) {
        logger.warning(
          'Could not complete the invitation ${connection.id} from '
          '${connection.owner}: $e',
        );
      }
    }
    return connected;
  }

  Future<CItem<ReceivedInvitation>?> _connect(
      CItem<InvitationConnection> connection) async {
    final invitation =
        await (await receivedInvitations).getOrNull(connection.id, me);
    if (invitation == null ||
        invitation.obj.inviter != connection.owner ||
        invitation.obj.status != ReceivedInvitationStatus.accepted) {
      return null;
    }
    Map<String, dynamic>? content;
    final sealed = invitation.obj.sealedContent;
    final key = connection.obj.contentKey;
    if (sealed != null && key != null) {
      content = jsonDecode(await InvitationKey.fromBase64(key).open(
        sealed,
        inviter: connection.owner,
        invitationId: connection.id,
      )) as Map<String, dynamic>;
    }
    final done = _withObj(
      invitation,
      invitation.obj.withStatus(
        ReceivedInvitationStatus.connected,
        content: content,
      ),
    );
    await (await receivedInvitations).update(done);
    return done;
  }

  // ---------------------------------------------------------------------------
  // Records outside the collections

  AtKey _previewKey(Atsign inviter, String id) =>
      invitationPreviewKey(inviter, id, invitationsNamespace);

  // NOTE: hashed because the invitee chooses the acceptance id, and a name
  // built from it could pass the atServer's key-length limit.
  AtKey _claimKey(CItem<InvitationAcceptance> acceptance) => _lockKey(
        'claim.${sha256.convert(utf8.encode(jsonEncode([
              acceptance.owner.toString(),
              acceptance.id,
              acceptance.obj.invitationId,
            ])))}',
      );

  AtKey _attemptKey(String id, int slot) => _lockKey('attempt$slot.$id');

  AtKey _outcomeKey(String id) => _lockKey('outcome.$id');

  AtKey _lockKey(String name) => AtKey.self(
        name,
        namespace: 'locks.invitations.$invitationsNamespace',
        sharedBy: me,
      ).build();

  /// Creates [key] unless it already exists, and says whether this call
  /// created it. The atServer refuses a second write to an immutable record,
  /// so across every client of this atSign exactly one call returns true.
  ///
  /// The record expires with [invitation]'s own record, so it stands for as
  /// long as anything could act on the invitation.
  Future<bool> _createOnce(
    AtKey key,
    String value,
    CItem<SentInvitation> invitation,
  ) async {
    // NOTE: a ttl of 0 would never expire.
    key.metadata
      ..immutable = true
      ..ttl = max(
          invitation.expiresAt.difference(DateTime.now()).inMilliseconds, 1);
    try {
      await atClient.put(
        key,
        value,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
      );
      return true;
    } catch (e) {
      if (e.toString().toLowerCase().contains('immutable')) return false;
      rethrow;
    }
  }

  Future<String?> _readOutcome(String id) async {
    try {
      final value = await atClient.get(
        _outcomeKey(id),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      return value.value as String?;
    } on AtKeyNotFoundException {
      return null;
    }
  }

  Future<List<CItem<T>>> _readable<T>(AtCollection<T> collection,
          {Atsign? owner}) =>
      collection
          .getItemsAsStream(owner: owner)
          .handleError(
            (Object e) => logger.warning(
              'Skipping a record in ${collection.namespace} that cannot be '
              'read: ${'$e'.split('\n').first}',
            ),
            test: (e) => e is! StoppedException,
          )
          .toList();

  Future<void> _deletePreview(String id) async {
    await atClient.delete(
      _previewKey(me, id),
      deleteRequestOptions: DeleteRequestOptions()..useRemoteAtServer = true,
    );
  }

  static CItem<T> _withObj<T>(CItem<T> item, T obj) => item.collection.draft(
        obj: obj,
        id: item.id,
        sharedWith: item.sharedWith,
        expiresAt: item.expiresAt,
        availableAt: item.availableAt,
      );

  static final _random = Random.secure();

  static String _randomHex(int bytes) => List.generate(
        bytes,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  static String _randomCode() =>
      _random.nextInt(1000000).toString().padLeft(6, '0');

  static bool _sameCode(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// [Invitations] for one client: the way an app or a CLI uses them.
@experimental
class AtClientInvitations with Invitations {
  @override
  final AtClient atClient;

  @override
  final String invitationsNamespace;

  @override
  final AtSignLogger logger = AtSignLogger('Invitations');

  AtClientInvitations(this.atClient, {required this.invitationsNamespace});
}
