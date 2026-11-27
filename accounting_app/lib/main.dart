import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'database.dart';
import 'file_io.dart';
import 'ui/home_screen.dart';

late LedgerDb ledger;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ledger = await LedgerDb.open();
  await _firstRunSeed();
  runApp(const AccountsApp());
}

/// On the very first launch, load the bundled workbook (if the build includes
/// one at assets/seed/initial.xlsx) so the app starts with the same balances
/// as the Excel file. The data then lives only in the local database.
Future<void> _firstRunSeed() async {
  if (await ledger.getMeta('seeded') != null) return;
  try {
    final bytes = await rootBundle.load('assets/seed/initial.xlsx');
    final result = importWorkbook(bytes.buffer.asUint8List());
    await ledger.importAll(result.accounts, replace: true);
  } catch (_) {
    // No bundled workbook – start empty; the user can import from the menu.
  }
  await ledger.setMeta('seeded', DateTime.now().toIso8601String());
}

class AccountsApp extends StatelessWidget {
  const AccountsApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1F4E79), brightness: b),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        );
    return MaterialApp(
      title: 'حسابات الرفاعي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
