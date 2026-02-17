import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marine_check/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MarineCheckApp());
    expect(find.text('Select Location'), findsOneWidget);
  });
}
