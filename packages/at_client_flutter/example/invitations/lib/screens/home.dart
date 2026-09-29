import 'dart:async';

import 'package:at_client/at_client_mixins.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

import '../incoming.dart';
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

class _HomeState extends State<Home> {
  Timer? _timer;
  StreamSubscription<CEvent>? _acceptances;
  StreamSubscription<CEvent>? _connections;
  bool _passing = false;

  List<CItem<ReceivedInvitation>> _received = [];
  List<CItem<SentInvitation>> _sent = [];
  List<CItem<InvitationContact>> _contacts = [];

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
    Incoming.instance.removeListener(_openIncoming);
    super.dispose();
  }

  Future<void> _pass() async {
    if (_passing) return;
    _passing = true;
    try {
      await _invitations.processAcceptances();
      final connected = await _invitations.processConnections();
      final me = _invitations.me;
      final received = await (await _invitations.receivedInvitations).getItems(
        owner: me,
      );
      final sent = await (await _invitations.sentInvitations).getItems(
        owner: me,
      );
      final contacts = await (await _invitations.contacts).getItems(owner: me);
      if (!mounted) return;
      setState(() {
        _received = received;
        _sent = sent;
        _contacts = contacts;
      });
      for (final c in connected) {
        _snack('Connected with ${c.obj.inviterName} (${c.obj.inviter})');
      }
    } catch (e) {
      _snack('$e');
    } finally {
      _passing = false;
    }
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
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
              onPressed: () async {
                await Session.instance.signOut();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
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
            children: [
              _list(
                _received.map(
                  (r) => ListTile(
                    title: Text('${r.obj.inviterName} (${r.obj.inviter})'),
                    subtitle: Text(
                      r.obj.plaintext ?? r.obj.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(r.obj.status.name),
                    onTap: r.obj.status == ReceivedInvitationStatus.previewed
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
                    title: Text(_contactName(s.obj.contactId)),
                    subtitle: Text('code ${s.obj.code} · link id ${s.id}'),
                    trailing: Text(
                      s.obj.acceptedBy == null
                          ? s.obj.status.name
                          : '${s.obj.status.name} by ${s.obj.acceptedBy}',
                    ),
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
                    subtitle: Text(c.obj.atSign ?? 'invited, not yet joined'),
                  ),
                ),
                'No contacts yet.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _contactName(String id) =>
      _contacts.where((c) => c.id == id).map((c) => c.obj.name).firstOrNull ??
      'someone';

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
