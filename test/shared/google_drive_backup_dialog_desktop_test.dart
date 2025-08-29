import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/widgets/google_drive_backup_dialog.dart';
import 'package:ai_chan/shared/services/google_appauth_adapter_desktop.dart';

void main() {
  testWidgets('desktop dialog shows copy and sign-in when lastAuthUrl is set before open', (WidgetTester tester) async {
    // Prepare static auth URL as if the adapter already built it
    GoogleAppAuthAdapter.lastAuthUrl = 'https://example.com/auth/prepared';

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GoogleDriveBackupDialog())));
    await tester.pumpAndSettle();

    expect(find.text('Copiar enlace'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('desktop dialog watcher picks up auth url set after open', (WidgetTester tester) async {
    // Ensure no initial URL
    GoogleAppAuthAdapter.lastAuthUrl = null;

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GoogleDriveBackupDialog())));
    await tester.pump();

    expect(find.text('Copiar enlace'), findsNothing);
    expect(find.text('Iniciar sesión'), findsNothing);

    // Simulate adapter setting the URL after the dialog opened
    GoogleAppAuthAdapter.lastAuthUrl = 'https://example.com/auth/later';

    // Advance time to allow the dialog's watcher (300ms periodic) to detect the change
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Copiar enlace'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
