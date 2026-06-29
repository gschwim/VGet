import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vget/main.dart';

void main() {
  testWidgets('VGet home renders URL field and Download button',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const VGetApp());
    await tester.pump();

    expect(find.text('Paste a link, get the media'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
  });
}
