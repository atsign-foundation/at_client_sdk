import 'package:at_commons/at_commons.dart' show Atsign, AtsignString;
import 'package:meta/meta.dart' show experimental;

/// Where a sent invitation has got to.
///
/// Every value but [pending] is final, and is decided by the invitation's
/// outcome record rather than by this field, which only caches it.
@experimental
enum SentInvitationStatus { pending, accepted, burned, revoked }

/// An invitation this atSign sent. Only this atSign reads it.
@experimental
class SentInvitation {
  final String code;
  final DateTime expiresAt;

  /// The app's details, as published in the preview for anyone holding the
  /// link.
  final Map<String, dynamic> publicDetails;

  /// The content key, base64, when the invitation carries content.
  final String? contentKey;
  final SentInvitationStatus status;
  final Atsign? acceptedBy;

  /// The details the invitee sent with the acceptance that was accepted.
  final Map<String, dynamic>? acceptanceDetails;

  const SentInvitation({
    required this.code,
    required this.expiresAt,
    required this.publicDetails,
    this.contentKey,
    this.status = SentInvitationStatus.pending,
    this.acceptedBy,
    this.acceptanceDetails,
  });

  factory SentInvitation.fromJson(Map<String, dynamic> json) => SentInvitation(
        code: json['code'],
        expiresAt: DateTime.parse(json['expiresAt']),
        publicDetails: _map(json['publicDetails'])!,
        contentKey: json['contentKey'],
        status: SentInvitationStatus.values.byName(json['status']),
        acceptedBy: (json['acceptedBy'] as String?)?.toAtsign(),
        acceptanceDetails: _map(json['acceptanceDetails']),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'publicDetails': publicDetails,
        if (contentKey != null) 'contentKey': contentKey,
        'status': status.name,
        if (acceptedBy != null) 'acceptedBy': acceptedBy.toString(),
        if (acceptanceDetails != null) 'acceptanceDetails': acceptanceDetails,
      };

  SentInvitation withStatus(
    SentInvitationStatus status, {
    Atsign? acceptedBy,
    Map<String, dynamic>? acceptanceDetails,
  }) =>
      SentInvitation(
        code: code,
        expiresAt: expiresAt,
        publicDetails: publicDetails,
        contentKey: contentKey,
        status: status,
        acceptedBy: acceptedBy ?? this.acceptedBy,
        acceptanceDetails: acceptanceDetails ?? this.acceptanceDetails,
      );
}

/// Content encrypted under an invitation's content key.
@experimental
class SealedInvitationContent {
  /// The AES-GCM nonce, base64.
  final String nonce;

  /// The ciphertext and its tag, base64.
  final String ciphertext;

  const SealedInvitationContent(
      {required this.nonce, required this.ciphertext});

  factory SealedInvitationContent.fromJson(Map<String, dynamic> json) =>
      SealedInvitationContent(
          nonce: json['nonce'], ciphertext: json['ciphertext']);

  Map<String, dynamic> toJson() => {'nonce': nonce, 'ciphertext': ciphertext};
}

/// What an invitation's public preview record holds.
///
/// Anyone holding the invitation link can read it.
@experimental
class InvitationPreview {
  static const int version = 1;

  final Map<String, dynamic> publicDetails;
  final DateTime expiresAt;

  /// The content, when it travels in the preview rather than out of band.
  final SealedInvitationContent? content;

  const InvitationPreview({
    required this.publicDetails,
    required this.expiresAt,
    this.content,
  });

  /// Reads a preview, throwing a [FormatException] for one this version
  /// cannot read.
  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    if (json['v'] != version) {
      throw FormatException(
          'unsupported invitation preview version ${json['v']}');
    }
    try {
      return InvitationPreview(
        publicDetails: _map(json['publicDetails'])!,
        expiresAt: DateTime.parse(json['expiresAt']),
        content: json['content'] == null
            ? null
            : SealedInvitationContent.fromJson(json['content']),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('malformed invitation preview: $e');
    }
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'publicDetails': publicDetails,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (content != null) 'content': content!.toJson(),
      };
}

/// Where a received invitation has got to.
@experimental
enum ReceivedInvitationStatus { previewed, accepted, connected }

/// An invitation this atSign received. Only this atSign reads it.
@experimental
class ReceivedInvitation {
  final Atsign inviter;

  /// The inviter's details, from the preview. The inviter's app wrote them,
  /// so they say what it chose to say, verified by nothing.
  final Map<String, dynamic> publicDetails;
  final DateTime expiresAt;

  /// The content, still encrypted, when the invitation carries any.
  final SealedInvitationContent? sealedContent;
  final ReceivedInvitationStatus status;

  /// The content, decrypted, once the inviter has released its key.
  final Map<String, dynamic>? content;

  const ReceivedInvitation({
    required this.inviter,
    required this.publicDetails,
    required this.expiresAt,
    this.sealedContent,
    this.status = ReceivedInvitationStatus.previewed,
    this.content,
  });

  factory ReceivedInvitation.fromJson(Map<String, dynamic> json) =>
      ReceivedInvitation(
        inviter: (json['inviter'] as String).toAtsign(),
        publicDetails: _map(json['publicDetails'])!,
        expiresAt: DateTime.parse(json['expiresAt']),
        sealedContent: json['sealedContent'] == null
            ? null
            : SealedInvitationContent.fromJson(json['sealedContent']),
        status: ReceivedInvitationStatus.values.byName(json['status']),
        content: _map(json['content']),
      );

  Map<String, dynamic> toJson() => {
        'inviter': inviter.toString(),
        'publicDetails': publicDetails,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (sealedContent != null) 'sealedContent': sealedContent!.toJson(),
        'status': status.name,
        if (content != null) 'content': content,
      };

  ReceivedInvitation withSealedContent(SealedInvitationContent sealed) =>
      ReceivedInvitation(
        inviter: inviter,
        publicDetails: publicDetails,
        expiresAt: expiresAt,
        sealedContent: sealed,
        status: status,
        content: content,
      );

  ReceivedInvitation withStatus(
    ReceivedInvitationStatus status, {
    Map<String, dynamic>? content,
  }) =>
      ReceivedInvitation(
        inviter: inviter,
        publicDetails: publicDetails,
        expiresAt: expiresAt,
        sealedContent: sealedContent,
        status: status,
        content: content ?? this.content,
      );
}

/// An invitee's answer to an invitation, shared with the inviter.
///
/// [details] are unverified, since anyone holding the link can send an
/// acceptance. [SentInvitation.acceptanceDetails] holds them once the
/// inviter has checked the code.
@experimental
class InvitationAcceptance {
  final String invitationId;
  final String code;
  final Map<String, dynamic> details;

  const InvitationAcceptance({
    required this.invitationId,
    required this.code,
    this.details = const {},
  });

  factory InvitationAcceptance.fromJson(Map<String, dynamic> json) =>
      InvitationAcceptance(
        invitationId: json['invitationId'],
        code: json['code'],
        details: _map(json['details']) ?? const {},
      );

  Map<String, dynamic> toJson() =>
      {'invitationId': invitationId, 'code': code, 'details': details};
}

/// The inviter's confirmation of an accepted invitation, shared with the
/// invitee, carrying the content key when there is content.
@experimental
class InvitationConnection {
  final String invitationId;
  final String? contentKey;

  const InvitationConnection({required this.invitationId, this.contentKey});

  factory InvitationConnection.fromJson(Map<String, dynamic> json) =>
      InvitationConnection(
        invitationId: json['invitationId'],
        contentKey: json['contentKey'],
      );

  Map<String, dynamic> toJson() => {
        'invitationId': invitationId,
        if (contentKey != null) 'contentKey': contentKey,
      };
}

Map<String, dynamic>? _map(Object? json) =>
    json == null ? null : Map<String, dynamic>.from(json as Map);
