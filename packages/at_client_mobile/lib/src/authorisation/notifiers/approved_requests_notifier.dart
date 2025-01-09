import 'package:at_client/at_client.dart';
import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/authorisation_service.dart';

class ApprovedRequestsNotifier extends ChangeNotifier {
  ApprovedRequestsNotifier(this._service) {
    fetchApprovedRequests();
  }

  final AuthorisationService _service;

  bool _isLoading = false;
  List<ServerEnrollmentRequest> _requests = [];
  String? _error;

  bool get isLoading => _isLoading;
  List<ServerEnrollmentRequest> get requests => _requests;
  String? get error => _error;

  Future<void> fetchApprovedRequests() async {
    try {
      _error = null;
      _isLoading = true;
      notifyListeners();
      final requests = await _service.getEnrollmentRequests(
        statusFilters: [
          EnrollmentStatus.approved,
        ],
      );
      _requests = requests;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> revokeRequest(ServerEnrollmentRequest request) async {
    try {
      _error = null;
      _isLoading = true;
      await _service.revoke(request);
      _requests.remove(request);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
