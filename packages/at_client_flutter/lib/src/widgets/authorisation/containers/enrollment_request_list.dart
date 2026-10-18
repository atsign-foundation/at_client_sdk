import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

/// {@template enrollment_request_list}
/// A "Big Widget" that manages and displays a list of pending enrollment
/// requests. It listens to real-time updates and provides approval/denial
/// functionality, through `client.enrollments` on the client it is given.
/// Below them it lists the approved enrollments, each with whether its keys
/// are anchored to the atSign's signing root.
/// {@endtemplate}
class EnrollmentRequestList extends StatefulWidget {
  const EnrollmentRequestList({
    super.key,
    this.useShrinkWrap = false,
    this.atClient,
    this.anchoring,
  });

  final bool useShrinkWrap;

  /// The client this widget manages enrollments through. Pass an app-owned
  /// client to use this widget without [AtClientManager]; with none it uses
  /// the current-atSign client, as it always has.
  final AtClient? atClient;

  /// Whether an approved enrollment's keys are anchored; with none it asks
  /// `client.enrollments.anchoring`.
  // ignore: experimental_member_use
  final Future<ChainResult> Function(String enrollmentId)? anchoring;

  @override
  State<EnrollmentRequestList> createState() => _EnrollmentRequestListState();
}

class _EnrollmentRequestListState extends State<EnrollmentRequestList> {
  AtClient get _client =>
      widget.atClient ?? AtClientManager.getInstance().atClient;
  final List<Enrollment> _requests = [];
  final List<({Enrollment enrollment, String anchored})> _approved = [];
  final List<Timer> _overlayTimers = [];
  StreamSubscription? _subscription;
  bool _isLoading = false;
  String? _error;

  /// Why the approved enrollments could not be listed, shown in their own
  /// section so it is never read as a failure of the pending list or of an
  /// approval.
  String? _approvedError;

  @override
  void initState() {
    super.initState();
    _fetchAndSubscribe();
  }

  Future<void> _fetchAndSubscribe() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _subscription = _client.enrollments.requests.listen(
        (request) {
          if (mounted) {
            setState(() {
              if (!_requests.any(
                (r) => r.enrollmentId == request.enrollmentId,
              )) {
                _requests.add(request);
              }
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _error = 'Connection lost: $e';
            });
          }
          debugPrint('Error in enrollment stream: $e');
        },
      );

      // Initial fetch of pending requests
      final initialRequests = await _client.enrollments.pending();

      if (mounted) {
        setState(() {
          for (final request in initialRequests) {
            if (!_requests.any((r) => r.enrollmentId == request.enrollmentId)) {
              _requests.add(request);
            }
          }
          _isLoading = false;
        });
      }
      await _loadApproved();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Lists the approved enrollments, each with whether its keys are anchored,
  /// or `?` where that could not be read; a failure to list them is recorded
  /// in [_approvedError] rather than thrown.
  Future<void> _loadApproved() async {
    // ignore: experimental_member_use
    final anchoring = widget.anchoring ?? _client.enrollments.anchoring;
    final List<Enrollment> approved;
    try {
      approved = await _client.enrollments.list(
        statuses: const [EnrollmentStatus.approved],
      );
    } on Exception catch (e) {
      debugPrint('Could not list the approved enrollments: $e');
      if (mounted) {
        setState(() {
          _approved.clear();
          _approvedError = 'Could not list the approved enrollments: $e';
        });
      }
      return;
    }
    final rows = <({Enrollment enrollment, String anchored})>[];
    for (final enrollment in approved) {
      final id = enrollment.enrollmentId;
      if (id == null) continue;
      String anchored;
      try {
        anchored = (await anchoring(id)).summary;
      } on Exception {
        anchored = '?';
      }
      rows.add((enrollment: enrollment, anchored: anchored));
    }
    if (mounted) {
      setState(() {
        _approvedError = null;
        _approved
          ..clear()
          ..addAll(rows);
      });
    }
  }

  Future<void> _handleApprove(Enrollment request) async {
    try {
      await _client.enrollments.approve(request.enrollmentId!);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        _showFeedbackOverlay(request, EnrollmentStatus.approved);
        await _loadApproved();
      }
      // ignore: experimental_member_use
    } on EnrollmentConveyanceException catch (e) {
      // NOTE: the approval itself succeeded and only conveying the secret
      // failed, so the request leaves the list and the message stands as-is.
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        await _loadApproved();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to approve: $e';
        if (e.toString().contains('authorized') ||
            e.toString().contains('manage')) {
          errorMessage =
              'This keysFile/enrollment cannot approve this enrollment as it is not authorized to.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  Future<void> _handleDeny(Enrollment request) async {
    try {
      await _client.enrollments.deny(request.enrollmentId!);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        _showFeedbackOverlay(request, EnrollmentStatus.denied);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to deny: $e';
        if (e.toString().contains('authorized') ||
            e.toString().contains('manage')) {
          errorMessage =
              'This keysFile/enrollment cannot deny this enrollment as it is not authorized to.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  void _showFeedbackOverlay(Enrollment request, EnrollmentStatus status) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      late final OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (context) => Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 50, right: 20),
            child: Material(
              color: Colors.transparent,
              child: AuthorisationFeedbackOverlay(
                request: request,
                newStatus: status,
                onTap: () => overlayEntry.remove(),
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlayEntry);
      final timer = Timer(const Duration(seconds: 3), () {
        try {
          overlayEntry.remove();
        } catch (_) {
          // Already removed
        }
      });
      _overlayTimers.add(timer);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (var timer in _overlayTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchAndSubscribe,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: widget.useShrinkWrap,
      physics: widget.useShrinkWrap
          ? const NeverScrollableScrollPhysics()
          : null,
      children: [
        if (_requests.isEmpty)
          const Center(child: Text('No pending enrollment requests')),
        for (final request in _requests)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: EnrollmentRequestCard(
              request: request,
              onApprove: () => _handleApprove(request),
              onReject: () => _handleDeny(request),
            ),
          ),
        if (_approved.isNotEmpty || _approvedError != null) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16.0),
            child: AuthorisationSectionHeader(
              title: 'Approved enrollments',
              icon: Icons.verified_user,
            ),
          ),
          if (_approvedError != null)
            Text(_approvedError!, style: const TextStyle(color: Colors.red)),
          for (final row in _approved)
            ListTile(
              key: ValueKey('approved-${row.enrollment.enrollmentId}'),
              title: Text(
                '${row.enrollment.appName ?? ''} · '
                '${row.enrollment.deviceName ?? ''}',
              ),
              subtitle: Text(row.enrollment.enrollmentId!),
              trailing: Text(row.anchored),
            ),
        ],
      ],
    );
  }
}
