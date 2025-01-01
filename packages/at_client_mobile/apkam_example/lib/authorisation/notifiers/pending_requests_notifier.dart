import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/authorisation_service.dart';

class PendingRequestsNotifier extends ChangeNotifier {
  PendingRequestsNotifier(this._service) {
    fetchPendingRequests();
  }

  final AuthorisationService _service;

  bool _isLoading = false;
  List<EnrollmentRequest> _requests = [];
  String? _error;

  bool get isLoading => _isLoading;
  List<EnrollmentRequest> get requests => _requests;
  String? get error => _error;

  Future<void> fetchPendingRequests() async {
    try {
      _error = null;
      _isLoading = true;
      notifyListeners();
      final requests = await _service.getAllEnrollmentRequests();
      _requests = requests;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
