import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

/// {@template enrollment_request_list}
/// A "Big Widget" that manages and displays a list of pending enrollment requests.
/// It listens to real-time updates and provides approval/denial functionality.
/// {@endtemplate}
class EnrollmentRequestList extends StatefulWidget {
  const EnrollmentRequestList({super.key, this.useShrinkWrap = false});

  final bool useShrinkWrap;

  @override
  State<EnrollmentRequestList> createState() => _EnrollmentRequestListState();
}

class _EnrollmentRequestListState extends State<EnrollmentRequestList> {
  final FlutterEnrollmentService _service = FlutterEnrollmentService();
  final List<ServerEnrollmentRequest> _requests = [];
  final List<Timer> _overlayTimers = [];
  StreamSubscription? _subscription;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.init();
    _fetchAndSubscribe();
  }

  Future<void> _fetchAndSubscribe() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 2. Subscribe to real-time updates FIRST to avoid race conditions
      _subscription = _service
          .enrollmentRequests(statusFilters: [EnrollmentStatus.pending]).listen(
        (request) {
          if (mounted) {
            setState(() {
              if (!_requests
                  .any((r) => r.enrollmentId == request.enrollmentId)) {
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


      // 1. Initial fetch of pending requests
      final initialRequests = await _service.getEnrollmentRequests(
        statusFilters: [EnrollmentStatus.pending],
      );
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleApprove(ServerEnrollmentRequest request) async {
    try {
      await _service.approve(request);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        _showFeedbackOverlay(request, EnrollmentStatus.approved);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to approve: $e';
        if (e.toString().contains('authorized') || e.toString().contains('manage')) {
          errorMessage = 'This keysFile/enrollment cannot approve this enrollment as it is not authorized to.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  Future<void> _handleDeny(ServerEnrollmentRequest request) async {
    try {
      await _service.deny(request);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        _showFeedbackOverlay(request, EnrollmentStatus.denied);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to deny: $e';
        if (e.toString().contains('authorized') || e.toString().contains('manage')) {
          errorMessage = 'This keysFile/enrollment cannot deny this enrollment as it is not authorized to.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  void _showFeedbackOverlay(
      ServerEnrollmentRequest request, EnrollmentStatus status) {
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
        // Use a try-catch as a safer alternative to 'mounted' for OverlayEntry
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
    _service.dispose();
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

    if (_requests.isEmpty) {
      return const Center(
        child: Text('No pending enrollment requests'),
      );
    }

    return ListView.builder(
      shrinkWrap: widget.useShrinkWrap,
      physics: widget.useShrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: EnrollmentRequestCard(
            request: request,
            onApprove: () => _handleApprove(request),
            onReject: () => _handleDeny(request),
          ),
        );
      },
    );
  }
}
