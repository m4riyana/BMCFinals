import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho_stationery/commerce/commerce_store.dart';
import 'package:ibasho_stationery/commerce/customer_profile.dart';
import 'package:ibasho_stationery/commerce/models.dart';

class SavingStore extends CommerceStore {
  int saves = 0;
  SavingStore() : super.preview(products: [], signedIn: true) {
    profile = const CustomerProfile(username: 'papermuse', name: 'Paper Muse',
      email: 'paper@example.com', contactEmail: 'paper@example.com');
  }
  @override
  Future<CustomerProfile> saveProfile({String? username, String? name,
    String? contactEmail, String? phoneNumber, String? address}) async {
    saves++;
    profile = CustomerProfile(username: username!, name: name!,
      email: 'paper@example.com', contactEmail: contactEmail!,
      phoneNumber: phoneNumber!, address: address!);
    notifyListeners();
    return profile!;
  }
}

void main() {
  testWidgets('Profile dialog can close while a field is focused', (tester) async {
    final store = CommerceStore.preview(products: [], signedIn: true);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CustomerProfileCard(store: store),
    )));
    await tester.tap(find.text('EDIT PROFILE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'papermuse');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Your profile'), findsNothing);
  });
  testWidgets('Save closes safely and Cancel does not autosave edits', (tester) async {
    final store = SavingStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CustomerProfileCard(store: store),
    )));
    await tester.tap(find.text('EDIT PROFILE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Updated Name');
    await tester.tap(find.text('SAVE & DONE'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(store.saves, 1);
    expect(store.profile!.name, 'Updated Name');
    await tester.tap(find.text('EDIT PROFILE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Discarded Name');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(store.saves, 1);
    expect(store.profile!.name, 'Updated Name');
  });
}
