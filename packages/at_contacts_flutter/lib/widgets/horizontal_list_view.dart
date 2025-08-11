import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_flutter/widgets/circular_contacts.dart';
import 'package:flutter/material.dart';

import 'package:at_common_flutter/services/size_config.dart';

class HorizontalCircularList extends StatelessWidget {
  final List<AtContact>? list;

  const HorizontalCircularList({Key? key, this.list}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var contactService = ContactService();
    return StreamBuilder<List<AtContact?>>(
        initialData: contactService.selectedContacts,
        stream: contactService.selectedContactStream,
        builder: (context, snapshot) {
          var selectedContacts = snapshot.data!;
          return SizedBox(
            height: (selectedContacts.isEmpty) ? 0 : 150.toHeight,
            child: ListView.builder(
              itemCount: selectedContacts.length,
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                return CircularContacts(
                  contact: selectedContacts[index],
                  onCrossPressed: () {
                    contactService
                        .removeSelectedAtSign(selectedContacts[index]);
                  },
                );
              },
            ),
          );
        });
  }
}
