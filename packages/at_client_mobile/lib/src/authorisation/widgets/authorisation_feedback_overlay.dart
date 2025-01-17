import 'package:flutter/material.dart';

import '../models/models.dart';

class AuthorisationFeedbackOverlay extends StatelessWidget {
  const AuthorisationFeedbackOverlay({
    required this.request,
    required this.onTap,
    super.key,
  });

  final ServerEnrollmentRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Info here!'),
        ),
      ),
    );
  }
}
