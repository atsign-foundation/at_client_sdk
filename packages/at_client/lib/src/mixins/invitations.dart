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
    show AtKey, AtKeyNotFoundException, Atsign, AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
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
/// [handledElsewhere] means another of this atSign's clients claimed it
/// first, on this pass or an earlier one.
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
/// - a **claim** per acceptance, so exactly one client handles it;
/// - an **attempt slot** per wrong code, so the count cannot lose an update;
/// - an **outcome** per invitation — accepted, burned or revoked — so an
///   invitation is decided once, whichever of those gets there first.
///
/// Content can be attached when the invitation is created. It is encrypted
/// under a fresh content key, the invitee holds the ciphertext before
/// accepting, and the key is shared with them only once the inviter has
/// verified their acceptance.
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
///     contactName: 'Bob', inviterName: 'Alice', content: 'the recipe');
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

  static const Duration _contactLifetime = Duration(days: 3650);

  /// How long an invitation's records outlive its expiry, so that its fate
  /// stays visible for a while.
  static const Duration _afterExpiry = Duration(days: 30);

  Atsign get me => atClient.getCurrentAtSign()!.toAtsign();

  /// The people invited, and those who invited this atSign, once connected.
  Future<AtCollection<InvitationContact>> get contacts =>
      _collection('contacts', InvitationContact.fromJson, 'InvitationContact');

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

  /// Creates an invitation for [contactName], and a contact to link the
  /// invitee's atSign to once they accept.
  ///
  /// [content] is fixed here. With [contentOutOfBand] it is returned for the
  /// app to send alongside the link rather than published in the preview.
  Future<CreatedInvitation> invite({
    required String contactName,
    required String inviterName,
    String message = '',
    String? content,
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
      sealed = await contentKey.seal(content, inviter: me, invitationId: id);
    }

    final contact = await (await contacts).create(
      obj: InvitationContact(name: contactName),
      expiresAt: DateTime.now().add(_contactLifetime),
    );
    await (await sentInvitations).create(
      id: id,
      obj: SentInvitation(
        contactId: contact.id,
        code: code,
        expiresAt: expiresAt,
        inviterName: inviterName,
        message: message,
        contentKey: contentKey?.base64,
      ),
      expiresAt: expiresAt.add(_afterExpiry),
    );

    final preview = InvitationPreview(
      inviterName: inviterName,
      message: message,
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
    if (!await _createOnce(_outcomeKey(id), 'revoked')) return false;
    await _deletePreview(id);
    await (await sentInvitations).update(
        _withObj(item, item.obj.withStatus(SentInvitationStatus.revoked)));
    return true;
  }

  /// Handles every acceptance of this atSign's invitations that no client has
  /// handled yet, and finishes any accepted invitation a client decided but
  /// did not finish. Reports every acceptance it looked at.
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
    for (final acceptance in await (await acceptances).getItems()) {
      if (acceptance.owner == me) continue;
      final outcome = await _process(acceptance);
      if (outcome != null) {
        results.add((acceptance: acceptance, outcome: outcome));
      }
    }
    await _finishDecided();
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
    if (!await _createOnce(_claimKey(acceptance), 'claimed')) {
      return InvitationOutcome.handledElsewhere;
    }

    if (DateTime.now().toUtc().isAfter(invitation.obj.expiresAt)) {
      return InvitationOutcome.expired;
    }
    if (!_sameCode(acceptance.obj.code, invitation.obj.code)) {
      return _countWrongCode(invitation);
    }
    final decided = await _createOnce(
      _outcomeKey(id),
      'accepted:${acceptance.owner}',
    );
    if (!decided) return InvitationOutcome.alreadyDecided;
    await _finishAccepted(invitation, acceptance.owner);
    return InvitationOutcome.accepted;
  }

  Future<InvitationOutcome> _countWrongCode(
    CItem<SentInvitation> invitation,
  ) async {
    for (var slot = 1; slot <= attemptLimit; slot++) {
      if (!await _createOnce(_attemptKey(invitation.id, slot), 'wrong')) {
        continue;
      }
      if (slot < attemptLimit) return InvitationOutcome.wrongCode;
      if (await _createOnce(_outcomeKey(invitation.id), 'burned')) {
        await _deletePreview(invitation.id);
        await (await sentInvitations).update(
          _withObj(invitation,
              invitation.obj.withStatus(SentInvitationStatus.burned)),
        );
      }
      return InvitationOutcome.burned;
    }
    return InvitationOutcome.alreadyDecided;
  }

  /// Finishes invitations whose outcome is recorded as accepted but whose
  /// record still says pending: the client that decided them stopped part way.
  Future<void> _finishDecided() async {
    for (final invitation
        in await (await sentInvitations).getItems(owner: me)) {
      if (invitation.obj.status != SentInvitationStatus.pending) continue;
      final outcome = await _readOutcome(invitation.id);
      if (outcome == null || !outcome.startsWith('accepted:')) continue;
      await _finishAccepted(
        invitation,
        outcome.substring('accepted:'.length).toAtsign(),
      );
    }
  }

  // NOTE: every step is idempotent, so a second client finishing the same
  // invitation writes the same values again.
  Future<void> _finishAccepted(
    CItem<SentInvitation> invitation,
    Atsign invitee,
  ) async {
    await (await connections).upsert(
      id: invitation.id,
      obj: InvitationConnection(
        invitationId: invitation.id,
        inviterName: invitation.obj.inviterName,
        contentKey: invitation.obj.contentKey,
      ),
      sharedWith: {invitee},
      expiresAt: DateTime.now().add(_afterExpiry),
    );
    final contact =
        await (await contacts).getOrNull(invitation.obj.contactId, me);
    if (contact != null) {
      await (await contacts)
          .update(_withObj(contact, contact.obj.withAtSign(invitee)));
    }
    await _deletePreview(invitation.id);
    await (await sentInvitations).update(
      _withObj(
        invitation,
        invitation.obj
            .withStatus(SentInvitationStatus.accepted, acceptedBy: invitee),
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
      if (existing.obj.content != null || outOfBandContent == null) {
        return existing;
      }
      final withContent = _withObj(
        existing,
        existing.obj.withContent(outOfBandContent),
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
        inviterName: preview.inviterName,
        message: preview.message,
        expiresAt: preview.expiresAt,
        content: preview.content ?? outOfBandContent,
      ),
      expiresAt: preview.expiresAt.add(_afterExpiry),
    );
  }

  /// Accepts an invitation with the [code] its inviter sent separately.
  ///
  /// The inviter decides; [processConnections] reports the connection once
  /// they have.
  Future<void> accept(
    InvitationLink link,
    String code, {
    SealedInvitationContent? outOfBandContent,
  }) async {
    final invitation = await preview(link, outOfBandContent: outOfBandContent);
    await (await acceptances).create(
      obj: InvitationAcceptance(invitationId: link.id, code: code),
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
    if (invitation != null)
      await (await receivedInvitations).delete(invitation);
  }

  /// Completes every accepted invitation whose inviter has confirmed it:
  /// adds the inviter as a contact and decrypts any content.
  Future<List<CItem<ReceivedInvitation>>> processConnections() async {
    final connected = <CItem<ReceivedInvitation>>[];
    for (final connection in await (await connections).getItems()) {
      if (connection.owner == me) continue;
      final invitation =
          await (await receivedInvitations).getOrNull(connection.id, me);
      if (invitation == null ||
          invitation.obj.inviter != connection.owner ||
          invitation.obj.status == ReceivedInvitationStatus.connected) {
        continue;
      }
      String? plaintext;
      final sealed = invitation.obj.content;
      final key = connection.obj.contentKey;
      if (sealed != null && key != null) {
        plaintext = await InvitationKey.fromBase64(key).open(
          sealed,
          inviter: connection.owner,
          invitationId: connection.id,
        );
      }
      await (await contacts).create(
        obj: InvitationContact(
          name: invitation.obj.inviterName,
          atSign: connection.owner,
        ),
        expiresAt: DateTime.now().add(_contactLifetime),
      );
      final done = _withObj(
        invitation,
        invitation.obj.withStatus(
          ReceivedInvitationStatus.connected,
          plaintext: plaintext,
        ),
      );
      await (await receivedInvitations).update(done);
      connected.add(done);
    }
    return connected;
  }

  // ---------------------------------------------------------------------------
  // Records outside the collections

  AtKey _previewKey(Atsign inviter, String id) =>
      invitationPreviewKey(inviter, id, invitationsNamespace);

  AtKey _claimKey(CItem<InvitationAcceptance> acceptance) => _lockKey(
        'claim.${acceptance.owner.withoutAt()}.${acceptance.id}.'
        '${acceptance.obj.invitationId}',
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
  Future<bool> _createOnce(AtKey key, String value) async {
    key.metadata.immutable = true;
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
