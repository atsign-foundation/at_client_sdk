import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

import '../models/location_share.dart';
import '../services/location_sharing_service.dart';

class LocationHome extends StatefulWidget {
  const LocationHome({super.key});

  @override
  State<LocationHome> createState() => _LocationHomeState();
}

class _LocationHomeState extends State<LocationHome> {
  final TextEditingController _atSignController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController(
    text: '37.7749',
  );
  final TextEditingController _longitudeController = TextEditingController(
    text: '-122.4194',
  );

  late final LocationSharingService _service;
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _service = LocationSharingService(
      atClient: AtClientManager.getInstance().atClient,
      locationProvider: _currentPointFromFields,
    );
    _initFuture = _service.init();
  }

  @override
  void dispose() {
    _atSignController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<LocationPoint?> _currentPointFromFields() async {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) return null;
    return LocationPoint(latitude: latitude, longitude: longitude);
  }

  Future<void> _startSharing() async {
    final atSign = _atSignController.text.trim();
    if (atSign.isEmpty) {
      _showSnack('Enter an atSign to share with.');
      return;
    }
    await _service.startSharingWith(atSign.toAtsign());
    _showSnack('Started sharing with $atSign');
  }

  Future<void> _publishLocation() async {
    final point = await _currentPointFromFields();
    if (point == null) {
      _showSnack('Latitude and longitude must be valid numbers.');
      return;
    }
    await _service.publishCurrentLocation(point);
    _showSnack('Published latest location.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Location sharing')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        return _LocationHomeView(
          service: _service,
          atSignController: _atSignController,
          latitudeController: _latitudeController,
          longitudeController: _longitudeController,
          onStartSharing: _startSharing,
          onPublishLocation: _publishLocation,
        );
      },
    );
  }
}

class _LocationHomeView extends StatelessWidget {
  const _LocationHomeView({
    required this.service,
    required this.atSignController,
    required this.latitudeController,
    required this.longitudeController,
    required this.onStartSharing,
    required this.onPublishLocation,
  });

  final LocationSharingService service;
  final TextEditingController atSignController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final Future<void> Function() onStartSharing;
  final Future<void> Function() onPublishLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Location sharing: ${service.self}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ShareControls(
              atSignController: atSignController,
              latitudeController: latitudeController,
              longitudeController: longitudeController,
              onStartSharing: onStartSharing,
              onPublishLocation: onPublishLocation,
              publishStateStream: service.watchPublishState(),
            ),
            const SizedBox(height: 24),
            Text(
              'Shared with me',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _ShareList(stream: service.watchSharesSharedWithMe()),
            const SizedBox(height: 24),
            Text(
              'Sharing by me',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _ShareList(
              stream: service.watchSharesOwnedByMe(),
              stopSharingWith: service.stopSharingWith,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareControls extends StatelessWidget {
  const _ShareControls({
    required this.atSignController,
    required this.latitudeController,
    required this.longitudeController,
    required this.onStartSharing,
    required this.onPublishLocation,
    required this.publishStateStream,
  });

  final TextEditingController atSignController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final Future<void> Function() onStartSharing;
  final Future<void> Function() onPublishLocation;
  final Stream<bool> publishStateStream;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: atSignController,
          decoration: const InputDecoration(
            labelText: 'Share with atSign',
            hintText: '@alice',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: latitudeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: longitudeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onStartSharing,
                child: const Text('Start sharing'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<bool>(
                stream: publishStateStream,
                initialData: false,
                builder: (context, snapshot) {
                  final isPublishing = snapshot.data ?? false;
                  return FilledButton.tonal(
                    onPressed: isPublishing ? null : onPublishLocation,
                    child: Text(isPublishing ? 'Publishing...' : 'Publish'),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShareList extends StatelessWidget {
  const _ShareList({required this.stream, this.stopSharingWith});

  final Stream<List<CItem<LocationShare>>> stream;
  final Future<void> Function(Atsign atSign)? stopSharingWith;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CItem<LocationShare>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        final shares = snapshot.data ?? const [];
        if (shares.isEmpty) {
          return const Text('No active shares.');
        }
        return Column(
          children: [
            for (final share in shares)
              _ShareTile(
                key: ValueKey('${share.owner}:${share.id}'),
                share: share,
                stopSharingWith: stopSharingWith,
              ),
          ],
        );
      },
    );
  }
}

class _ShareTile extends StatefulWidget {
  const _ShareTile({super.key, required this.share, this.stopSharingWith});

  final CItem<LocationShare> share;
  final Future<void> Function(Atsign atSign)? stopSharingWith;

  @override
  State<_ShareTile> createState() => _ShareTileState();
}

class _ShareTileState extends State<_ShareTile> {
  Timer? _pulseTimer;
  bool _isHighlighted = false;

  @override
  void didUpdateWidget(covariant _ShareTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.share.obj.updatedAt != widget.share.obj.updatedAt) {
      _pulse();
    }
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _pulse() {
    _pulseTimer?.cancel();
    setState(() => _isHighlighted = true);
    _pulseTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _isHighlighted = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.share;
    final point = share.obj.latestPoint;
    final coordinates = point == null
        ? 'No location published yet'
        : '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}';
    final updatedAt = share.obj.updatedAt.toLocal();
    final isRecent = DateTime.now().difference(updatedAt).inSeconds < 15;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: _isHighlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.72)
            : colorScheme.surface,
        child: ListTile(
          title: Row(
            children: [
              Expanded(
                child: Text('${share.owner} -> ${share.sharedWith.join(', ')}'),
              ),
              const SizedBox(width: 8),
              _LiveBadge(isRecent: isRecent),
            ],
          ),
          subtitle: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(
              key: ValueKey(share.obj.updatedAt.toIso8601String()),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  coordinates,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Updated ${_formatClock(updatedAt)} '
                  '(${_formatAge(updatedAt)})',
                ),
              ],
            ),
          ),
          trailing: widget.stopSharingWith == null || share.sharedWith.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  tooltip: 'Stop sharing',
                  onPressed: () =>
                      widget.stopSharingWith!(share.sharedWith.first),
                ),
        ),
      ),
    );
  }

  String _formatClock(DateTime value) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(value.hour)}:'
        '${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}';
  }

  String _formatAge(DateTime value) {
    final age = DateTime.now().difference(value);
    if (age.inSeconds < 5) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.isRecent});

  final bool isRecent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isRecent
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          isRecent ? 'LIVE' : 'IDLE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isRecent
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
