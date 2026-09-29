import 'package:at_commons/at_commons.dart' show Atsign, AtsignString;
import 'package:meta/meta.dart' show experimental;

/// Someone this atSign knows, with or without an atSign of their own yet.
@experimental
class InvitationContact {
  final String name;
  final Atsign? atSign;

  const InvitationContact({required this.name, this.atSign});

  factory InvitationContact.fromJson(Map<String, dynamic> json) =>
      InvitationContact(
        name: json['name'],
        atSign: (json['atSign'] as String?)?.toAtsign(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (atSign != null) 'atSign': atSign.toString(),
      };

  InvitationContact withAtSign(Atsign atSign) =>
      InvitationContact(name: name, atSign: atSign);
}

/// Where a sent invitation has got to.
///
/// Every value but [pending] is final, and is decided by the invitation's
/// outcome record rather than by this field, which only caches it.
@experimental
enum SentInvitationStatus { pending, accepted, burned, revoked }

/// An invitation this atSign sent. Only this atSign reads it.
@experimental
class SentInvitation {
  final String contactId;
  final String code;
  final DateTime expiresAt;
  final String inviterName;
  final String message;

  /// The content key, base64, when the invitation carries content.
  final String? contentKey;
  final SentInvitationStatus status;
  final Atsign? acceptedBy;

  const SentInvitation({
    required this.contactId,
    required this.code,
    required this.expiresAt,
    required this.inviterName,
    required this.message,
    this.contentKey,
    this.status = SentInvitationStatus.pending,
    this.acceptedBy,
  });

  factory SentInvitation.fromJson(Map<String, dynamic> json) => SentInvitation(
        contactId: json['contactId'],
        code: json['code'],
        expiresAt: DateTime.parse(json['expiresAt']),
        inviterName: json['inviterName'],
        message: json['message'],
        contentKey: json['contentKey'],
        status: SentInvitationStatus.values.byName(json['status']),
        acceptedBy: (json['acceptedBy'] as String?)?.toAtsign(),
      );

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'code': code,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'inviterName': inviterName,
        'message': message,
        if (contentKey != null) 'contentKey': contentKey,
        'status': status.name,
        if (acceptedBy != null) 'acceptedBy': acceptedBy.toString(),
      };

  SentInvitation withStatus(SentInvitationStatus status,
          {Atsign? acceptedBy}) =>
      SentInvitation(
        contactId: contactId,
        code: code,
        expiresAt: expiresAt,
        inviterName: inviterName,
        message: message,
        contentKey: contentKey,
        status: status,
        acceptedBy: acceptedBy ?? this.acceptedBy,
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

  final String inviterName;
  final String message;
  final DateTime expiresAt;

  /// The content, when it travels in the preview rather than out of band.
  final SealedInvitationContent? content;

  const InvitationPreview({
    required this.inviterName,
    required this.message,
    required this.expiresAt,
    this.content,
  });

  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    if (json['v'] != version) {
      throw FormatException(
          'unsupported invitation preview version ${json['v']}');
    }
    return InvitationPreview(
      inviterName: json['inviterName'],
      message: json['message'],
      expiresAt: DateTime.parse(json['expiresAt']),
      content: json['content'] == null
          ? null
          : SealedInvitationContent.fromJson(json['content']),
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'inviterName': inviterName,
        'message': message,
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
  final String inviterName;
  final String message;
  final DateTime expiresAt;
  final SealedInvitationContent? content;
  final ReceivedInvitationStatus status;

  /// The decrypted content, once the inviter has released its key.
  final String? plaintext;

  const ReceivedInvitation({
    required this.inviter,
    required this.inviterName,
    required this.message,
    required this.expiresAt,
    this.content,
    this.status = ReceivedInvitationStatus.previewed,
    this.plaintext,
  });

  factory ReceivedInvitation.fromJson(Map<String, dynamic> json) =>
      ReceivedInvitation(
        inviter: (json['inviter'] as String).toAtsign(),
        inviterName: json['inviterName'],
        message: json['message'],
        expiresAt: DateTime.parse(json['expiresAt']),
        content: json['content'] == null
            ? null
            : SealedInvitationContent.fromJson(json['content']),
        status: ReceivedInvitationStatus.values.byName(json['status']),
        plaintext: json['plaintext'],
      );

  Map<String, dynamic> toJson() => {
        'inviter': inviter.toString(),
        'inviterName': inviterName,
        'message': message,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (content != null) 'content': content!.toJson(),
        'status': status.name,
        if (plaintext != null) 'plaintext': plaintext,
      };

  ReceivedInvitation withContent(SealedInvitationContent content) =>
      ReceivedInvitation(
        inviter: inviter,
        inviterName: inviterName,
        message: message,
        expiresAt: expiresAt,
        content: content,
        status: status,
        plaintext: plaintext,
      );

  ReceivedInvitation withStatus(ReceivedInvitationStatus status,
          {String? plaintext}) =>
      ReceivedInvitation(
        inviter: inviter,
        inviterName: inviterName,
        message: message,
        expiresAt: expiresAt,
        content: content,
        status: status,
        plaintext: plaintext ?? this.plaintext,
      );
}

/// An invitee's answer to an invitation, shared with the inviter.
@experimental
class InvitationAcceptance {
  final String invitationId;
  final String code;

  const InvitationAcceptance({required this.invitationId, required this.code});

  factory InvitationAcceptance.fromJson(Map<String, dynamic> json) =>
      InvitationAcceptance(
          invitationId: json['invitationId'], code: json['code']);

  Map<String, dynamic> toJson() => {'invitationId': invitationId, 'code': code};
}

/// The inviter's confirmation of an accepted invitation, shared with the
/// invitee, carrying the content key when there is content.
@experimental
class InvitationConnection {
  final String invitationId;
  final String inviterName;
  final String? contentKey;

  const InvitationConnection({
    required this.invitationId,
    required this.inviterName,
    this.contentKey,
  });

  factory InvitationConnection.fromJson(Map<String, dynamic> json) =>
      InvitationConnection(
        invitationId: json['invitationId'],
        inviterName: json['inviterName'],
        contentKey: json['contentKey'],
      );

  Map<String, dynamic> toJson() => {
        'invitationId': invitationId,
        'inviterName': inviterName,
        if (contentKey != null) 'contentKey': contentKey,
      };
}
