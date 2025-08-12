import 'package:at_app_flutter/at_app_flutter.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_contacts_flutter/at_contacts_flutter.dart';
import 'package:at_contacts_group_flutter/at_contacts_group_flutter.dart';
import 'package:at_contacts_group_flutter/screens/group_contact_view/group_contact_view.dart';
import 'package:flutter/material.dart';

class SecondScreen extends StatefulWidget {
  const SecondScreen({Key? key}) : super(key: key);

  @override
  State<SecondScreen> createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  /// Get the AtClientManager instance
  var atClientManager = AtClientManager.getInstance();

  String? activeAtSign;
  @override
  void initState() {
    getAtSignAndInitializeContacts();
    super.initState();
  }

  @override
  void dispose() {
    disposeContactsControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Second Screen'),
      ),
      body: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
              child: Text(
                'Welcome $activeAtSign!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // any logic
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (BuildContext context) => ContactsScreen(
                    selectedList: (s) {},
                  ),
                ));
              },
              child: const Text('Show contacts'),
            ),
            ElevatedButton(
              onPressed: () {
                // any logic
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (BuildContext context) => GroupContactView(
                      showContacts: true,
                      showGroups: true,
                      asSelectionScreen: true,
                      selectedList: (List<GroupContactsModel?> s) {}),
                ));
              },
              child: const Text('Show Group view contacts'),
            ),
            ElevatedButton(
              onPressed: () {
                // any logic
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (BuildContext context) => const BlockedScreen(),
                ));
              },
              child: const Text('Show blocked contacts'),
            ),
            ElevatedButton(
              onPressed: () {
                // any logic
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (BuildContext context) => const GroupList(),
                ));
              },
              child: const Text('Show groups screen'),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: always_declare_return_types
  getAtSignAndInitializeContacts() async {
    var currentAtSign = atClientManager.atClient.getCurrentAtSign();
    setState(() {
      activeAtSign = currentAtSign;
    });
    initializeContactsService(rootDomain: AtEnv.rootDomain);
    initializeGroupService(rootDomain: AtEnv.rootDomain);
  }
}
