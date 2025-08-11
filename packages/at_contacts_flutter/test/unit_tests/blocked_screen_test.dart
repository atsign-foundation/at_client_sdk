import 'dart:developer';

import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBlockedContactService extends Mock implements ContactService {}

void main() {
  ContactService mockBlockedContactService = MockBlockedContactService();
  group('Blocked Contact Screen test', () {
    setUp(() {
      reset(mockBlockedContactService);
    });
    test('Blocked Contacts fetched form contacts service', () {
      when(() =>
          mockBlockedContactService.fetchBlockContactList().then((_) async {
            log('Blocked Contacts fetched successfully');
          }));
    });
  });
}
