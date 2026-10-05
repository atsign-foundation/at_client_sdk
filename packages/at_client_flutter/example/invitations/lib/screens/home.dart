import 'dart:async';

import 'package:at_client/at_client_mixins.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

import '../incoming.dart';
import '../models.dart';
import '../session.dart';
import 'enter_invitation.dart';
import 'invite.dart';
import 'received.dart';

/// The signed-in atSign's invitations and contacts.
///
/// While it is open it handles acceptances of this atSign's invitations and
/// completes invitations it accepted, so it does the helper's job whenever
/// the app is running.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Timer? _timer;
  StreamSubscription<CEvent>? _acceptances;
  StreamSubscription<CEvent>? _connections;
  Future<void>? _passing;
  bool _signingOut = false;

  List<CItem<ReceivedInvitation>> _received = [];
  List<CItem<SentInvitation>> _sent = [];
  List<CItem<Contact>> _contacts = [];

  AtClientInvitations get _invitations => Session.instance.invitations!;

  @override
  void initState() {
    super.initState();
    _watch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _pass());
    Incoming.instance.addListener(_openIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIncoming());
    _pass();
  }

  Future<void> _watch() async {
    final acceptances = await _invitations.acceptances;
    final connections = await _invitations.connections;
    if (!mounted) return;
    _acceptances = acceptances.watch().listen((_) => _pass());
    _connections = connections.watch().listen((_) => _pass());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _acceptances?.cancel();
    _connections?.cancel();
    _tabs.dispose();
    Incoming.instance.removeListener(_openIncoming);
    super.dispose();
  }

  /// Runs one pass, or joins the pass already running.
  Future<void> _pass() {
    if (_signingOut) return Future.value();
    return _passing ??= _passOnce().whenComplete(() => _passing = null);
  }

  Future<void> _passOnce() async {
    try {
      final decided = await _invitations.processAcceptances();
      final accepted = [
        for (final d in decided)
          if (d.outcome == InvitationOutcome.accepted) d.acceptance,
      ];
      if (accepted.isNotEmpty) {
        final sent = await (await _invitations.sentInvitations).getItems(
          owner: _invitations.me,
        );
        if (mounted) {
          _tabs.animateTo(1);
          for (final acceptance in accepted) {
            unawaited(_showConfirmed(acceptance, sent));
          }
        }
      }
      final connected = await _invitations.processConnections();
      await Session.instance.linkContacts();
      final me = _invitations.me;
      final received = await (await _invitations.receivedInvitations).getItems(
        owner: me,
      );
      final sent = await (await _invitations.sentInvitations).getItems(
        owner: me,
      );
      final contacts = await (await Session.instance.contacts).getItems(
        owner: me,
      );
      if (!mounted) return;
      setState(() {
        _received = received;
        _sent = sent;
        _contacts = contacts;
      });
      for (final c in connected) {
        final from = '${_inviterName(c.obj)} (${c.obj.inviter})';
        _snack(
          c.obj.content == null
              ? 'Connected with $from'
              : '$from confirmed you, and the key to the private content '
                    'arrived',
        );
      }
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    _timer?.cancel();
    await _passing;
    await Session.instance.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openIncoming() async {
    final link = Incoming.instance.value;
    if (link == null || !mounted) return;
    Incoming.instance.clear();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReceivedScreen(link: link)));
    await _pass();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Tells the inviter that an invitee's code checked out, and what this
  /// app sent them in return.
  Future<void> _showConfirmed(
    CItem<InvitationAcceptance> acceptance,
    List<CItem<SentInvitation>> sent,
  ) {
    final name = AcceptanceDetails.fromJson(acceptance.obj.details).name;
    final who = name.isEmpty ? '${acceptance.owner}' : name;
    final invitation = sent
        .where((s) => s.id == acceptance.obj.invitationId)
        .firstOrNull;
    final sentKey = invitation?.obj.contentKey != null;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.verified_user),
        title: Text('$who accepted'),
        content: Text(
          '${name.isEmpty ? who : '$name (${acceptance.owner})'} sent the '
          'right code, so this app confirmed them'
          '${sentKey ? ' and sent them the key to the private content' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: false, child: _scaffold(context));
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Invitations — ${_invitations.me}'),
        actions: [
          IconButton(
            tooltip: 'Paste an invitation',
            icon: const Icon(Icons.content_paste),
            onPressed: () => enterInvitation(context),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signingOut ? null : _signOut,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Received'),
            Tab(text: 'Sent'),
            Tab(text: 'Contacts'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Invite'),
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const InviteScreen()));
          await _pass();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _pass,
        child: TabBarView(
          controller: _tabs,
          children: [
            _list(
              _received.map(
                (r) => ListTile(
                  key: ValueKey(r.id),
                  title: Text('${_inviterName(r.obj)} (${r.obj.inviter})'),
                  subtitle: _ReceivedSubtitle(invitation: r.obj),
                  trailing: Text(r.obj.status.name),
                  onTap: r.obj.status != ReceivedInvitationStatus.connected
                      ? () => Incoming.instance.value = InvitationLink(
                          inviter: r.obj.inviter,
                          id: r.id,
                        )
                      : null,
                ),
              ),
              'No invitations yet. Open an invitation link, or paste one.',
            ),
            _list(
              _sent.map(
                (s) => ListTile(
                  title: Text(_contactName(s.id)),
                  subtitle: Text('code ${s.obj.code} · link id ${s.id}'),
                  trailing: Text(_sentStatus(s.obj)),
                  onLongPress: s.obj.status == SentInvitationStatus.pending
                      ? () => _revoke(s.id)
                      : null,
                ),
              ),
              'Nothing sent yet.',
            ),
            _list(
              _contacts.map(
                (c) => ListTile(
                  title: Text(c.obj.name),
                  subtitle: Text(c.obj.atSign ?? _invitedNote(c.id)),
                  onLongPress: c.obj.atSign == null ? () => _forget(c) : null,
                ),
              ),
              'No contacts yet.',
            ),
          ],
        ),
      ),
    );
  }

  /// What became of the invitation behind a contact who has not joined.
  String _invitedNote(String id) {
    final sent = _sent.where((s) => s.id == id).firstOrNull?.obj;
    if (sent == null) return 'invited';
    return switch (sent.status) {
      SentInvitationStatus.pending
          when DateTime.now().isAfter(sent.expiresAt) =>
        'invitation expired',
      SentInvitationStatus.pending => 'invited, not yet joined',
      SentInvitationStatus.accepted => 'joined',
      SentInvitationStatus.burned => 'invitation burned by wrong codes',
      SentInvitationStatus.revoked => 'invitation withdrawn',
    };
  }

  /// Forgets a contact who never joined, once the user confirms.
  Future<void> _forget(CItem<Contact> contact) async {
    final forget = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${contact.obj.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (forget != true) return;
    await (await Session.instance.contacts).delete(contact);
    await _pass();
  }

  String _contactName(String id) =>
      _contacts.where((c) => c.id == id).map((c) => c.obj.name).firstOrNull ??
      'someone';

  String _inviterName(ReceivedInvitation r) =>
      InviteDetails.fromJson(r.publicDetails).inviterName;

  /// The status, and once accepted, who by and the name they gave.
  String _sentStatus(SentInvitation s) {
    if (s.acceptedBy == null) return s.status.name;
    final details = s.acceptanceDetails;
    final name = details == null
        ? ''
        : AcceptanceDetails.fromJson(details).name;
    return '${s.status.name} by ${s.acceptedBy}'
        '${name.isEmpty ? '' : ' ($name)'}';
  }

  Future<void> _revoke(String id) async {
    final revoked = await _invitations.revoke(id);
    _snack(revoked ? 'Revoked' : 'Already decided');
    await _pass();
  }

  Widget _list(Iterable<Widget> tiles, String empty) {
    final children = tiles.toList();
    return ListView(
      children: children.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(empty, textAlign: TextAlign.center),
              ),
            ]
          : children,
    );
  }
}

/// A received invitation's message and, when it carries private content,
/// that content: sealed until the inviter confirms, then opened in place.
class _ReceivedSubtitle extends StatelessWidget {
  final ReceivedInvitation invitation;

  const _ReceivedSubtitle({required this.invitation});

  @override
  Widget build(BuildContext context) {
    final details = InviteDetails.fromJson(invitation.publicDetails);
    final content = invitation.content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (details.message.isNotEmpty) Text(details.message),
        if (invitation.sealedContent != null) ...[
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1200),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: content == null
                ? _ContentBox(
                    key: const ValueKey('sealed'),
                    icon: Icons.lock,
                    text:
                        'Encrypted: you can read it once '
                        '${details.inviterName} confirms you',
                    sealed: true,
                  )
                : _ContentBox(
                    key: const ValueKey('open'),
                    icon: Icons.lock_open,
                    text: PrivateContent.fromJson(content).text,
                    sealed: false,
                  ),
          ),
        ],
      ],
    );
  }
}

class _ContentBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool sealed;

  const _ContentBox({
    super.key,
    required this.icon,
    required this.text,
    required this.sealed,
  });

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: sealed
            ? colours.surfaceContainerHighest
            : colours.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: sealed
                  ? const TextStyle(fontStyle: FontStyle.italic)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
