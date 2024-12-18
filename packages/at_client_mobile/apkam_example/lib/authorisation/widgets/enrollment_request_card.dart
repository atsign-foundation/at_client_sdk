import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:flutter/material.dart';

class EnrollmentRequestCard extends StatelessWidget {
  const EnrollmentRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final EnrollmentRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(request.appName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(request.deviceName),
          Text(request.namespacePermissions.map((permission) => permission.prettyPrint()).join(', ')),
        ],
      ),
      trailing: switch (request.status) {
        EnrollmentStatus.pending => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: onApprove,
                child: Text('Approve'),
              ),
              ElevatedButton(
                onPressed: onReject,
                child: Text('Reject'),
              ),
            ],
          ),
        EnrollmentStatus.approved => RawChip(
            label: Text('Approved'),
            color: WidgetStateProperty.all<Color>(Colors.green),
          ),
        EnrollmentStatus.denied => RawChip(
            label: Text('Denied'),
            color: WidgetStateProperty.all<Color>(Colors.red),
          ),
        EnrollmentStatus.revoked => RawChip(
            label: Text('Revoked'),
            color: WidgetStateProperty.all<Color>(Colors.orange),
          ),
        EnrollmentStatus.expired => RawChip(
            label: Text('Expired'),
            color: WidgetStateProperty.all<Color>(Colors.grey),
          ),
      },
    );
  }
}

extension on NamespacePermission {
  String prettyPrint() {
    final buffer = StringBuffer();
    buffer.append(namespace);
    if (read) {
      buffer.append(' (read)');
    }
    if (write) {
      buffer.append(' (write)');
    }
    return buffer.getData()!;
  }
}
