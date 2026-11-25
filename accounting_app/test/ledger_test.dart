import 'dart:io';

import 'package:alrefaei_accounts/database.dart';
import 'package:alrefaei_accounts/file_io.dart';
import 'package:alrefaei_accounts/models.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

xl.CellIndex ix(String a) => xl.CellIndex.indexByString(a);

/// Builds a small workbook in the original layout, including the odd cases
/// found in the real file.
List<int> sampleWorkbook() {
  final book = xl.Excel.createExcel();
  book.rename(book.getDefaultSheet()!, 'الأرصدة');
  final s = book['حساب أ'];
  void t(String c, String v) => s.updateCell(ix(c), xl.TextCellValue(v));
  void n(String c, num v) => s.updateCell(
      ix(c), v is int ? xl.IntCellValue(v) : xl.DoubleCellValue(v.toDouble()));
  void f(String c, String v) => s.updateCell(ix(c), xl.FormulaCellValue(v));
  t('B3', 'البيان');
  // USD لنا: normal line + converted line with commission.
  t('B4', 'رصيد افتتاحي'); n('C4', 703.06); n('D4', 1); f('E4', 'IFERROR(C4/D4,"")');
  t('B5', 'تحويل'); n('C5', 3450); n('D5', 34.5); n('F5', 2); f('E5', 'IFERROR(C5/D5,"")');
  // USD علينا: commission only, no amount and no rate -> ignored by Excel.
  n('N4', 1); f('M4', 'IFERROR(K4/L4,"")');
  // USD علينا: commission with rate but blank amount -> counts.
  n('L5', 1); n('N5', 3);
  // TRY علينا
  t('Z4', 'رصيد افتتاحي'); n('AA4', 2217.63); n('AB4', 1);
  // EUR لنا: text typed in the amount cell and a hand-typed value of 1.
  s.updateCell(ix('AI4'), xl.TextCellValue('رصيد افتتاحي'));
  n('AJ4', 0.75); n('AK4', 1);
  // EUR علينا: amount without rate -> ignored (with a warning).
  t('AP4', 'خطأ'); n('AQ4', 50);
  return book.encode()!;
}

Map<Currency, double> nets(List<AccountData> data) {
  final out = {for (final c in Currency.values) c: 0.0};
  for (final a in data) {
    for (final e in a.entries) {
      out[e.currency] = out[e.currency]! + e.signedTotal;
    }
  }
  return out;
}

void main() {
  sqfliteFfiInit();

  group('models', () {
    test('value and total follow the sheet formulas', () {
      final e = Entry(
          accountId: 1, currency: Currency.usd, side: Side.alayna,
          amount: 3450, rate: 34.5, commission: 2);
      expect(e.value, 100);
      expect(e.total, 102);
      expect(e.signedTotal, -102);
      expect(Entry(accountId: 1, currency: Currency.usd, side: Side.lana,
              amount: 5, rate: 0).value, 0);
    });

    test('parseNumber accepts Arabic digits and separators', () {
      expect(parseNumber('١٢٣٫٥'), 123.5);
      expect(parseNumber('1,234.75'), 1234.75);
      expect(parseNumber(''), isNull);
      expect(parseNumber('abc'), isNull);
    });
  });

  group('excel', () {
    test('import reproduces Excel results', () {
      final r = importWorkbook(sampleWorkbook());
      expect(r.accounts.map((a) => a.name), ['حساب أ']);
      final n = nets(r.accounts);
      // 703.06 + 100 + 2 - 3 (commission-only line)
      expect(n[Currency.usd], closeTo(802.06, 1e-9));
      expect(n[Currency.tryL], closeTo(-2217.63, 1e-9));
      expect(n[Currency.eur], closeTo(1, 1e-9));
      expect(r.warnings, hasLength(1));
      final eur = r.accounts.single.entries.firstWhere((e) => e.currency == Currency.eur);
      expect(eur.description, 'رصيد افتتاحي');
    });

    test('export then import round-trips balances', () {
      final first = importWorkbook(sampleWorkbook()).accounts;
      final again = importWorkbook(exportWorkbook(first)).accounts;
      final a = nets(first), b = nets(again);
      for (final c in Currency.values) {
        expect(b[c], closeTo(a[c]!, 0.01));
      }
      expect(again.single.entries.length, first.single.entries.length);
    });

    test('JSON backup round-trips', () {
      final data = importWorkbook(sampleWorkbook()).accounts;
      final back = decodeBackup(encodeBackup(data));
      expect(back.single.name, data.single.name);
      expect(nets(back), nets(data));
    });

    // Run with: LEDGER_XLSX=/path/file.xlsx LEDGER_TOTALS=usd,try,eur flutter test
    // (the expected totals from the workbook's الأرصدة sheet; kept out of
    // the repository because they are private financial data).
    final real = Platform.environment['LEDGER_XLSX'];
    final expected = Platform.environment['LEDGER_TOTALS'];
    test('real workbook matches the "الأرصدة" sheet totals', () {
      final want = expected!.split(',').map(double.parse).toList();
      final r = importWorkbook(File(real!).readAsBytesSync());
      final n = nets(r.accounts);
      expect(n[Currency.usd], closeTo(want[0], 0.005));
      expect(n[Currency.tryL], closeTo(want[1], 0.005));
      expect(n[Currency.eur], closeTo(want[2], 0.005));
    }, skip: real == null || expected == null
        ? 'set LEDGER_XLSX and LEDGER_TOTALS to run'
        : false);
  });

  group('database', () {
    late LedgerDb db;
    setUp(() async {
      db = await LedgerDb.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    });
    tearDown(() => db.close());

    test('balances = Σلنا − Σعلينا per currency', () async {
      final a = await db.addAccount('كاش');
      await db.addEntry(Entry(accountId: a.id!, currency: Currency.usd, side: Side.lana, amount: 535));
      await db.addEntry(Entry(accountId: a.id!, currency: Currency.usd, side: Side.alayna,
          amount: 3450, rate: 34.5, commission: 1));
      final b = (await db.balances()).single;
      expect(b.net(Currency.usd), closeTo(434, 1e-9));
      expect(b.totals[Currency.usd]!.alayna, closeTo(101, 1e-9));
      expect(b.net(Currency.eur), 0);
    });

    test('import replace / merge and cascade delete', () async {
      final data = importWorkbook(sampleWorkbook()).accounts;
      await db.importAll(data, replace: true);
      await db.importAll(data, replace: false); // merge doubles entries
      final b = (await db.balances()).single;
      expect(b.net(Currency.tryL), closeTo(-2 * 2217.63, 1e-6));
      await db.importAll(data, replace: true);
      expect((await db.balances()).single.net(Currency.tryL), closeTo(-2217.63, 1e-6));
      await db.deleteAccount((await db.accounts()).single.id!);
      expect(await db.accounts(), isEmpty);
      expect((await db.db.query('entries')), isEmpty);
    });
  });
}
