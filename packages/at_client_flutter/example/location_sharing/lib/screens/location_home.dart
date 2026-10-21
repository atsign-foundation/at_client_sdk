import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

import '../models/location_share.dart';
import '../services/location_provider.dart';
import '../services/location_sharing_service.dart';

/// Home screen for a logged-in atSign: lets the user start sharing their
/// (simulated) location with another atSign, and shows every share that's
/// currently active in either direction, updating live as the underlying
/// [AtCollection] emits events.
class LocationHome extends StatefulWidget {
  const LocationHome({super.key, required this.atClient});

  final AtClient atClient;

  @override
  State<LocationHome> createState() => _LocationHomeState();
}

class _LocationHomeState extends State<LocationHome> {
  LocationSharingService? _service;
  final _locationProvider = SimulatedLocationProvider();
  final _recipientController = TextEditingController();
  Timer? _publishTimer;

  @override
  void initState() {
    super.initState();
    LocationSharingService.openCollection(widget.atClient).then((shares) {
      if (!mounted) return;
      setState(() => _service = LocationSharingService(shares: shares));
    });
  }

  @override
  void dispose() {
    _publishTimer?.cancel();
    _recipientController.dispose();
    widget.atClient.stop();
    super.dispose();
  }

  Future<void> _startSharing() async {
    final service = _service;
    final input = _recipientController.text.trim();
    if (service == null || input.isEmpty) return;
    final Atsign recipient;
    try {
      recipient = input.toAtsign();
    } on InvalidAtSignException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    final point = await _locationProvider();
    await service.startSharingWith(recipient, point: point);
    _recipientController.clear();

    _publishTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      final next = await _locationProvider();
      if (next != null) await service.publishCurrentLocation(next);
    });
  }

  Future<void> _stopSharing(Atsign atSign) async {
    await _service?.stopSharingWith(atSign);
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Signed in as ${service.self}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _recipientController,
                  decoration: const InputDecoration(
                    labelText: 'Share with atSign',
                    hintText: '@bob',
                  ),
                  onSubmitted: (_) => _startSharing(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startSharing,
                child: const Text('Share'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Sharing with',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _OwnedSharesList(
            stream: service.watchSharesOwnedByMe(),
            onStop: _stopSharing,
          ),
          const SizedBox(height: 24),
          const Text(
            'Shared with me',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _ReceivedSharesList(stream: service.watchSharesSharedWithMe()),
        ],
      ),
    );
  }
}

class _OwnedSharesList extends StatelessWidget {
  const _OwnedSharesList({required this.stream, required this.onStop});

  final Stream<List<CItem<LocationShare>>> stream;
  final Future<void> Function(Atsign atSign) onStop;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CItem<LocationShare>>>(
      stream: stream,
      builder: (context, snapshot) {
        final shares = snapshot.data ?? const [];
        if (shares.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Not sharing with anyone yet.'),
          );
        }
        return Column(
          children: [
            for (final share in shares)
              for (final recipient in share.sharedWith)
                ListTile(
                  title: Text('$recipient'),
                  subtitle: Text(_pointLabel(share.obj.latestPoint)),
                  trailing: IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: () => onStop(recipient),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _ReceivedSharesList extends StatelessWidget {
  const _ReceivedSharesList({required this.stream});

  final Stream<List<CItem<LocationShare>>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CItem<LocationShare>>>(
      stream: stream,
      builder: (context, snapshot) {
        final shares = snapshot.data ?? const [];
        if (shares.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No one is sharing their location with you yet.'),
          );
        }
        return Column(
          children: [
            for (final share in shares)
              ListTile(
                title: Text('${share.owner}'),
                subtitle: Text(_pointLabel(share.obj.latestPoint)),
              ),
          ],
        );
      },
    );
  }
}

String _pointLabel(LocationPoint? point) {
  if (point == null) return 'No position yet';
  return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
}
