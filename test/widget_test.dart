// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_chan/main.dart';
import 'test_setup.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await initializeTestEnvironment();

    // Construir la app raíz (incluye MaterialApp y Providers)
    await tester.pumpWidget(const RootApp());
    // Dejar pasar el delay de initState (500ms) y tareas asíncronas mínimas
    await tester.pump(const Duration(milliseconds: 700));

    // Debe existir un MaterialApp en el árbol
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
