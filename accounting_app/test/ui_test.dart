// Renders the real screens on top of the real database code.
// Optional: SCREENSHOT_DIR=/some/dir saves PNG screenshots (loads system
// fonts so Arabic text is visible), LEDGER_XLSX=/file.xlsx uses a real
// workbook as data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:alrefaei_accounts/database.dart';
import 'package:alrefaei_accounts/file_io.dart';
import 'package:alrefaei_accounts/main.dart';
import 'package:alrefaei_accounts/models.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'ledger_test.dart' show sampleWorkbook;

final _shots = Platform.environment['SCREENSHOT_DIR'];
final _real = Platform.environment['LEDGER_XLSX'];

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (File(f).existsSync()) {
        l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
      }
    }
    await l.load();
  }

  const fonts = '/usr/share/fonts/truetype/dejavu';
  await load('Roboto', ['$fonts/DejaVuSans.ttf', '$fonts/DejaVuSans-Bold.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await load('MaterialIcons',
      ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shots == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('root')));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_shots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  sqfliteFfiInit();

  testWidgets('home, account and entry form render and save', (tester) async {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      if (_shots != null) await _loadFonts();
      ledger = await LedgerDb.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      final real = _real;
      final bytes = real != null ? File(real).readAsBytesSync() : sampleWorkbook();
      await ledger.importAll(importWorkbook(bytes).accounts, replace: true);
    });

    await tester.pumpWidget(const RepaintBoundary(key: Key('root'), child: AccountsApp()));
    await _settle(tester);
    expect(find.text('الأرصدة'), findsOneWidget);
    await _shot(tester, '1_home');

    // Open the first account.
    final firstName = (await tester.runAsync(() => ledger.accounts()))!.first.name;
    await tester.tap(find.text(firstName).first);
    await _settle(tester);
    expect(find.text('الرصيد النهائي'), findsOneWidget);
    await _shot(tester, '2_account');

    // Add an entry: 3450 ÷ 34.5 + 2 commission = 102 لنا.
    await tester.tap(find.text('قيد جديد'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'البيان'), 'تحويل حوالة');
    await tester.enterText(find.widgetWithText(TextFormField, 'المبلغ'), '3450');
    await tester.enterText(find.widgetWithText(TextFormField, 'السعر'), '34.5');
    await tester.enterText(find.widgetWithText(TextFormField, 'العمولة'), '2');
    await tester.pump();
    expect(find.textContaining('102.00'), findsWidgets);
    await _shot(tester, '3_entry_form');

    final before = (await tester.runAsync(() => ledger.balances()))!
        .firstWhere((b) => b.account.name == firstName)
        .net(Currency.usd);
    await tester.ensureVisible(find.text('حفظ'));
    await tester.tap(find.text('حفظ'));
    await _settle(tester);
    final after = (await tester.runAsync(() => ledger.balances()))!
        .firstWhere((b) => b.account.name == firstName)
        .net(Currency.usd);
    expect(after - before, closeTo(102, 1e-9));
    expect(find.text('تحويل حوالة'), findsOneWidget);
    await _shot(tester, '4_account_after');

    await tester.runAsync(() => ledger.close());
  });
}
