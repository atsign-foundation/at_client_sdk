import 'dart:async';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/authorisation_service.dart';

class PendingRequestsNotifier extends ChangeNotifier {
  PendingRequestsNotifier(this._service) {
    fetchPendingRequests();
  }

  final AuthorisationService _service;
  StreamSubscription<ServerEnrollmentRequest>? _subscription;

  bool _isLoading = false;
  final List<ServerEnrollmentRequest> _requests = [];
  String? _error;

  bool get isLoading => _isLoading;
  List<ServerEnrollmentRequest> get requests => _requests;
  String? get error => _error;

  Future<void> fetchPendingRequests() async {
    await _pendingRequests();
    _subscription = _service.enrollmentRequests(
      statusFilters: [
        EnrollmentStatus.pending,
      ],
    ).listen(
      (request) {
        _error = null;
        _isLoading = false;
        if (!_requests.contains(request)) {
          _requests.add(request);
        }
        notifyListeners();
      },
      onError: (e) {
        _isLoading = false;
        _error = e.toString();
        notifyListeners();
      },
      onDone: () {
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _pendingRequests() async {
    try {
      _error = null;
      _isLoading = true;
      notifyListeners();
      final requests = await _service.getEnrollmentRequests(
        statusFilters: [
          EnrollmentStatus.pending,
        ],
      );
      for (final request in requests) {
        if (!_requests.contains(request)) {
          _requests.add(request);
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> approveRequest(ServerEnrollmentRequest request) async {
    try {
      _error = null;
      _isLoading = true;
      await _service.approve(request);
      _requests.remove(request);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> denyRequest(ServerEnrollmentRequest request) async {
    try {
      _error = null;
      _isLoading = true;
      await _service.deny(request);
      _requests.remove(request);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
