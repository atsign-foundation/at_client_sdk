import 'package:apkam_example/authorisation/pages/authorisation_home_page.dart';
import 'package:apkam_example/authorisation/widgets/enrollment_request_card.dart';
import 'package:apkam_example/home/pages/home_page_stream.dart';
import 'package:apkam_example/home/pages/otp_page.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

import '../../authorisation/models/models.dart';
import '../../authorisation/services/authorisation_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);

  List<EnrollmentRequest> enrollmentRequests = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await service.isManagerKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AuthorisationHomePage(),
                  ),
                );
              },
              child: const Text('Authorisation Home Page'),
            ),
            // ElevatedButton(
            //   onPressed: () {
            //     Navigator.of(context).push(
            //       MaterialPageRoute(
            //         builder: (context) => const OtpPage(),
            //       ),
            //     );
            //   },
            //   child: const Text('OTP Page'),
            // ),
            // ElevatedButton(
            //   onPressed: () {
            //     Navigator.of(context).push(
            //       MaterialPageRoute(
            //         builder: (context) => const HomePageStream(),
            //       ),
            //     );
            //   },
            //   child: Text('Enrollment Stream'),
            // ),
            // ElevatedButton(
            //   onPressed: () async {
            //     final requests = await service.getAllEnrollmentRequests();
            //     setState(() {
            //       enrollmentRequests = requests;
            //     });
            //   },
            //   child: Text('Get Pending Requests'),
            // ),
            // ...enrollmentRequests.map(
            //   (request) => EnrollmentRequestCard(
            //     request: request,
            //     onApprove: () async {
            //       await service.approve(request);
            //       final requests = await service.getAllEnrollmentRequests();
            //       setState(() {
            //         enrollmentRequests = requests;
            //       });
            //     },
            //     onReject: () async {
            //       await service.deny(request);
            //       final requests = await service.getAllEnrollmentRequests();
            //       setState(() {
            //         enrollmentRequests = requests;
            //       });
            //     },
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
