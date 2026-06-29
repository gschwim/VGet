import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vget/main.dart';

void main() {
  testWidgets('VGet home renders URL field and Download button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const VGetApp());

    expect(find.text('Paste a link, get the media'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
  });
}
