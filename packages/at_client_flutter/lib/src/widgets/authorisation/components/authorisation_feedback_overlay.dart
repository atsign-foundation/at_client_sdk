import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:flutter/material.dart';

class AuthorisationFeedbackOverlay extends StatelessWidget {
  const AuthorisationFeedbackOverlay({
    required this.request,
    required this.newStatus,
    required this.onTap,
    super.key,
  });

  final ServerEnrollmentRequest request;
  final EnrollmentStatus newStatus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String statusText;
    switch (newStatus) {
      case EnrollmentStatus.pending:
        icon = Icons.pending_actions_outlined;
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        statusText = 'Pending';
        break;
      case EnrollmentStatus.approved:
        icon = Icons.check_circle_outline;
        color = Colors.green;
        statusText = 'Approved';
        break;
      case EnrollmentStatus.denied:
        icon = Icons.close_outlined;
        color = Colors.red;
        statusText = 'Denied';
        break;
      case EnrollmentStatus.revoked:
        icon = Icons.close_outlined;
        color = Colors.red;
        statusText = 'Revoked';
        break;
      case EnrollmentStatus.expired:
        icon = Icons.close_outlined;
        color = Colors.red;
        statusText = 'Expired';
        break;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shadowColor: Color(0xFFCFCFCF),
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 16),
              Icon(icon, size: 32, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        text: request.appName,
                        children: [
                          TextSpan(
                            text: ' | ',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          TextSpan(
                            text: request.deviceName,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      statusText,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              IconButton(icon: const Icon(Icons.close), onPressed: onTap),
            ],
          ),
        ),
      ),
    );
  }
}
