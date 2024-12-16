import 'package:apkam_example/authorisation/services/authorisation_service.dart' as authorisation_service;
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  List<authorisation_service.EnrollmentRequest> enrollmentRequests = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final requests = await authorisation_service.AuthorisationService().getAllEnrollmentRequests(
                AtClientManager.getInstance().atClient,
              );
              setState(() {
                enrollmentRequests = requests;
              });
            },
            child: Text('Get Pending Requests'),
          ),
          ...enrollmentRequests.map(
            (request) => ListTile(
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
                        onPressed: () async {
                          final _ = await authorisation_service.AuthorisationService().approve(
                            request,
                            AtClientManager.getInstance().atClient,
                          );
                          final requests = await authorisation_service.AuthorisationService().getAllEnrollmentRequests(
                            AtClientManager.getInstance().atClient,
                          );
                          setState(() {
                            enrollmentRequests = requests;
                          });
                        },
                        child: Text('Approve'),
                      ),
                      ElevatedButton(
                        onPressed: () async {},
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
            ),
          ),
        ],
      ),
    );
  }
}

extension on authorisation_service.NamespacePermission {
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
