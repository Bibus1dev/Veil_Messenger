import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_messenger/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VeilMessengerApp());
    expect(find.byType(VeilMessengerApp), findsOneWidget);
  });
}