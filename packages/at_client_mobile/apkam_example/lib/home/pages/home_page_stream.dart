import 'package:apkam_example/authorisation/services/authorisation_service.dart' as authorisation_service;
import 'package:apkam_example/authorisation/widgets/enrollment_request_card.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

class HomePageStream extends StatefulWidget {
  const HomePageStream({super.key});

  @override
  HomePageStreamState createState() => HomePageStreamState();
}

class HomePageStreamState extends State<HomePageStream> {
  late final service = authorisation_service.AuthorisationService(AtClientManager.getInstance().atClient);

  List<authorisation_service.EnrollmentRequest> enrollmentRequests = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page Stream'),
      ),
      body: FutureBuilder(
        future: service.init(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          return StreamBuilder(
            stream: service.enrollmentRequests,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                // Add the new object to the list
                if (!enrollmentRequests.contains(snapshot.data!)) {
                  enrollmentRequests.add(snapshot.data!);
                }
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              return ListView.builder(
                itemCount: enrollmentRequests.length,
                itemBuilder: (context, index) {
                  return EnrollmentRequestCard(
                    request: enrollmentRequests[index],
                    onApprove: () {},
                    onReject: () {},
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
