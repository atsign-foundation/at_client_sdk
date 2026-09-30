import 'package:at_commons/at_commons.dart' show Atsign, AtsignString;
import 'package:meta/meta.dart' show experimental;

/// What an invitation link carries: who sent it, and which invitation.
///
/// The link is `https://<host>/i#@alice/<id>`. The invitation sits in the URL
/// fragment, which browsers never send to the host, so the landing page's
/// server does not learn it. The code never appears in the link.
@experimental
class InvitationLink {
  final Atsign inviter;
  final String id;

  const InvitationLink({required this.inviter, required this.id});

  /// Parses a full link, or the bare `@alice/<id>` its fragment holds.
  ///
  /// Throws a [FormatException] for anything that is not a whole invitation.
  factory InvitationLink.parse(String text) {
    final trimmed = text.trim();
    final hash = trimmed.indexOf('#');
    try {
      final fragment = Uri.decodeComponent(
        hash >= 0 ? trimmed.substring(hash + 1) : trimmed,
      );
      final match = RegExp(r'^(@[^/\s]+)/([0-9a-f]{32})$').firstMatch(fragment);
      if (match == null) throw FormatException('not an invitation link', text);
      return InvitationLink(inviter: match[1]!.toAtsign(), id: match[2]!);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('not an invitation link: $e', text);
    }
  }

  /// The link to send, for a landing page at [linkBase] (e.g.
  /// `https://invite.example.com`).
  String toUrl(String linkBase) => '$linkBase/i#$this';

  @override
  String toString() => '$inviter/$id';
}
