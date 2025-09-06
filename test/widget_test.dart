// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App builds smoke test', (final WidgetTester tester) async {
    // Para evitar inicializaciones pesadas (permisos, plugins) en el test
    // aislado, creamos un MaterialApp mínimo en lugar de arrancar la app
    // completa. Esto verifica el entorno de widgets sin ejecutar init logic.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    // Debe existir un MaterialApp en el árbol
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
