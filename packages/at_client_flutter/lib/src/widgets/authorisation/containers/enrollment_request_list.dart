import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show EnrollmentRequestDecision, ServerEnrollmentRequest;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

/// {@template enrollment_request_list}
/// A "Big Widget" that manages and displays a list of pending enrollment requests.
/// It listens to real-time updates and provides approval/denial functionality.
/// {@endtemplate}
class EnrollmentRequestList extends StatefulWidget {
  const EnrollmentRequestList({
    super.key,
    this.useShrinkWrap = false,
    this.enrollmentService,
  });

  final bool useShrinkWrap;

  /// Injection seam for tests; defaults to a real [FlutterEnrollmentService].
  final FlutterEnrollmentService? enrollmentService;

  @override
  State<EnrollmentRequestList> createState() => _EnrollmentRequestListState();
}

class _EnrollmentRequestListState extends State<EnrollmentRequestList> {
  late final FlutterEnrollmentService _service;

  /// Whether this widget made [_service], and may therefore close it.
  ///
  /// An injected one belongs to the caller, who may share it across routes:
  /// [FlutterEnrollmentService.dispose] closes the request stream and drops
  /// the controller, so disposing someone else's service makes every later
  /// use of it throw on a null controller.
  late final bool _ownsService;
  final List<ServerEnrollmentRequest> _requests = [];
  final List<Timer> _overlayTimers = [];
  StreamSubscription? _subscription;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.enrollmentService == null;
    _service = widget.enrollmentService ?? FlutterEnrollmentService();
    _fetchAndSubscribe();
  }

  Future<void> _fetchAndSubscribe() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _subscription = _service
          .getEnrollments(statusFilters: [EnrollmentStatus.pending])
          .listen(
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
      final atLookUp = _service.atClient.getRemoteSecondary()!.atLookUp;
      final initialRequests = await _service.list([
        EnrollmentStatus.pending,
      ], atLookUp);

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
      // Through the service's own client seam, so the whole flow is
      // testable by injecting one service; in production it is the same
      // AtClientManager-resolved instance either way.
      final atSign = _service.atClient.getCurrentAtSign()!;
      final atLookUp = _service.atClient.getRemoteSecondary()!.atLookUp;
      await _service.approve(
        EnrollmentRequestDecision.approved(
          enrollmentId: request.enrollmentId,
          // Absent on a pq-mode request: the enrollee wrapped no key and the
          // approver mints one, so empty — not a crash — is the signal the
          // approve path expects.
          apkamSymmetricKey: AtBytes.fromString(
            request.encryptedAPKAMSymmetricKey ?? '',
          ),
          atSign: atSign,
        ),
        atLookUp,
      );
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        _showFeedbackOverlay(request, EnrollmentStatus.approved);
      }
      // ignore: experimental_member_use
    } on EnrollmentConveyanceException catch (e) {
      // The server-side approval succeeded — only the secret conveyance was
      // refused, so the request is no longer pending and leaves the list,
      // and the message (approved, cannot decrypt, consider revoking) is
      // shown as-is rather than wrapped in a failure claim.
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r.enrollmentId == request.enrollmentId);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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

  Future<void> _handleDeny(ServerEnrollmentRequest request) async {
    try {
      final atSign = _service.atClient.getCurrentAtSign()!;
      final atLookUp = _service.atClient.getRemoteSecondary()!.atLookUp;
      await _service.deny(
        EnrollmentRequestDecision.denied(request.enrollmentId, atSign),
        atLookUp,
      );
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

  void _showFeedbackOverlay(
    ServerEnrollmentRequest request,
    EnrollmentStatus status,
  ) {
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
    if (_ownsService) {
      _service.dispose();
    }
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
      return const Center(child: Text('No pending enrollment requests'));
    }

    return ListView.builder(
      shrinkWrap: widget.useShrinkWrap,
      physics: widget.useShrinkWrap
          ? const NeverScrollableScrollPhysics()
          : null,
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
