import 'dart:convert';

import 'package:excel/excel.dart' as xl;

import 'database.dart';
import 'models.dart';

/// Column offsets of the six blocks in an account sheet of the original
/// workbook: USD لنا (A), USD علينا (I), TRY لنا (Q), TRY علينا (Y),
/// EUR لنا (AG), EUR علينا (AO). Inside a block:
/// +0 م, +1 البيان, +2 المبلغ, +3 السعر, +4 القيمة, +5 العمولة, +6 الرصيد.
const _blocks = <(Currency, Side, int)>[
  (Currency.usd, Side.lana, 0),
  (Currency.usd, Side.alayna, 8),
  (Currency.tryL, Side.lana, 16),
  (Currency.tryL, Side.alayna, 24),
  (Currency.eur, Side.lana, 32),
  (Currency.eur, Side.alayna, 40),
];
const _firstDataRow = 3; // row 4 in Excel
const summarySheetName = 'الأرصدة';

class ImportResult {
  ImportResult(this.accounts, this.warnings);
  final List<AccountData> accounts;
  final List<String> warnings;
  int get entryCount => accounts.fold(0, (s, a) => s + a.entries.length);
}

// ------------------------------------------------------------------ import

double? _num(xl.CellValue? v) => switch (v) {
      xl.IntCellValue(:final value) => value.toDouble(),
      xl.DoubleCellValue(:final value) => value,
      xl.TextCellValue() => parseNumber(v.toString()),
      _ => null,
    };

String _text(xl.CellValue? v) => switch (v) {
      null => '',
      xl.FormulaCellValue() => '',
      xl.DoubleCellValue(:final value) =>
        value == value.roundToDouble() ? value.toInt().toString() : '$value',
      _ => v.toString().trim(),
    };

/// Reads a workbook in the same layout as the original file
/// ("الأرصدة" + one sheet per account). The rules reproduce the sheet
/// formulas exactly: القيمة = IFERROR(المبلغ/السعر,""),
/// الرصيد = IFERROR(القيمة+العمولة,""), and SUM ignores the blanks.
ImportResult importWorkbook(List<int> bytes) {
  final book = xl.Excel.decodeBytes(bytes);
  final accounts = <AccountData>[];
  final warnings = <String>[];
  final importTime = DateTime.now();

  for (final name in book.tables.keys) {
    final sheet = book.tables[name]!;
    final rows = sheet.rows;
    xl.CellValue? at(int r, int c) =>
        r < rows.length && c < rows[r].length ? rows[r][c]?.value : null;

    // Account sheets have "البيان" in B3; the summary sheet does not.
    if (_text(at(2, 1)) != 'البيان') continue;

    final entries = <Entry>[];
    for (final (cur, side, col) in _blocks) {
      for (var r = _firstDataRow; r < rows.length; r++) {
        final descCell = at(r, col + 1);
        final amountCell = at(r, col + 2);
        final amount = _num(amountCell);
        final rate = _num(at(r, col + 3));
        final valueCell = at(r, col + 4);
        final commission = _num(at(r, col + 5)) ?? 0;
        var desc = _text(descCell);

        double? amt;
        double rt = 1;
        if (valueCell != null &&
            valueCell is! xl.FormulaCellValue &&
            _num(valueCell) != null &&
            (amount == null || rate == null || rate == 0)) {
          // القيمة typed by hand instead of the formula.
          amt = _num(valueCell);
          if (desc.isEmpty && amount == null) desc = _text(amountCell);
        } else if (amountCell == null || (amount == null && _text(amountCell).isEmpty)) {
          // Blank amount: Excel computes 0 / rate = 0, so only the commission
          // counts – and only when the rate is a non-zero number.
          if (rate != null && rate != 0 && commission != 0) {
            amt = 0;
            rt = rate;
          }
        } else if (amount != null && rate != null && rate != 0) {
          amt = amount;
          rt = rate;
        } else {
          warnings.add(
              '$name – ${cur.arabic}/${side.arabic} سطر ${r + 1}: تم تجاهله لأن المبلغ أو السعر غير صالح (كما في Excel)');
        }
        if (amt == null) continue;
        if (amt == 0 && commission == 0) continue;
        entries.add(Entry(
          accountId: 0,
          currency: cur,
          side: side,
          description: desc,
          amount: amt,
          rate: rt,
          commission: commission,
          date: importTime,
        ));
      }
    }
    accounts.add(AccountData(name.trim(), entries));
  }
  return ImportResult(accounts, warnings);
}

// ------------------------------------------------------------------ export

String _sheetName(String name, Set<String> used) {
  var s = name.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), '-').trim();
  if (s.isEmpty) s = 'حساب';
  if (s.length > 31) s = s.substring(0, 31);
  var candidate = s;
  var i = 2;
  while (used.contains(candidate) || candidate == summarySheetName) {
    final suffix = ' ($i)';
    candidate = (s.length + suffix.length > 31
            ? s.substring(0, 31 - suffix.length)
            : s) +
        suffix;
    i++;
  }
  used.add(candidate);
  return candidate;
}

xl.CellIndex _ix(int col, int row) =>
    xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Writes a workbook in the original layout: a "الأرصدة" sheet followed by
/// one sheet per account with the six currency/side blocks.
List<int> exportWorkbook(List<AccountData> data) {
  final book = xl.Excel.createExcel();
  final defaultSheet = book.getDefaultSheet()!;
  book.rename(defaultSheet, summarySheetName);
  final summary = book[summarySheetName];
  summary.isRTL = true;

  final bold = xl.CellStyle(bold: true, horizontalAlign: xl.HorizontalAlign.Center);
  final title = xl.CellStyle(
      bold: true,
      fontSize: 13,
      horizontalAlign: xl.HorizontalAlign.Center,
      backgroundColorHex: xl.ExcelColor.fromHexString('#FFD9E1F2'));

  void put(xl.Sheet s, int col, int row, Object? v, [xl.CellStyle? style]) {
    final xl.CellValue? cv = switch (v) {
      null => null,
      final String t => xl.TextCellValue(t),
      final int n => xl.IntCellValue(n),
      final double d => xl.DoubleCellValue(_r2(d)),
      _ => xl.TextCellValue(v.toString()),
    };
    s.updateCell(_ix(col, row), cv, cellStyle: style);
  }

  // Summary header
  final summaryCols = {Currency.usd: 1, Currency.tryL: 5, Currency.eur: 9};
  const currencyTitles = {
    Currency.usd: 'الدولار',
    Currency.tryL: 'التركي',
    Currency.eur: 'اليورو',
  };
  final used = <String>{};
  final sheetNames = [for (final a in data) _sheetName(a.name, used)];

  for (final c in Currency.values) {
    final col = summaryCols[c]!;
    put(summary, col, 0, currencyTitles[c], title);
    summary.merge(_ix(col, 0), _ix(col + 2, 0));
    put(summary, col, 1, 'الرصيد النهائي', bold);
    put(summary, col, 2, 'م', bold);
    put(summary, col + 1, 2, 'الحساب', bold);
    put(summary, col + 2, 2, 'الرصيد', bold);
    summary.setColumnWidth(col + 1, 22);
    summary.setColumnWidth(col + 2, 14);
  }
  final grand = {for (final c in Currency.values) c: 0.0};

  for (var i = 0; i < data.length; i++) {
    final a = data[i];
    final s = book[sheetNames[i]];
    s.isRTL = true;
    final totals = {
      for (final c in Currency.values) c: {Side.lana: 0.0, Side.alayna: 0.0},
    };
    final byBlock = {
      for (final b in _blocks)
        (b.$1, b.$2): a.entries
            .where((e) => e.currency == b.$1 && e.side == b.$2)
            .toList()
          ..sort((x, y) => x.date.compareTo(y.date)),
    };

    for (final (cur, side, col) in _blocks) {
      final list = byBlock[(cur, side)]!;
      // Row 3 headers
      const headers = ['م', 'البيان', 'المبلغ', 'السعر', 'القيمة', 'العمولة', 'الرصيد'];
      for (var h = 0; h < headers.length; h++) {
        put(s, col + h, 2, headers[h], bold);
      }
      s.setColumnWidth(col + 1, 24);
      for (var k = 0; k < list.length; k++) {
        final e = list[k];
        final row = _firstDataRow + k;
        put(s, col, row, k + 1);
        put(s, col + 1, row, e.description);
        put(s, col + 2, row, e.amount);
        put(s, col + 3, row, e.rate);
        put(s, col + 4, row, e.value);
        if (e.commission != 0) put(s, col + 5, row, e.commission);
        put(s, col + 6, row, e.total);
        totals[cur]![side] = totals[cur]![side]! + e.total;
      }
      // Row 2: الرصيد لنا / الرصيد علينا
      put(s, col, 1, side == Side.lana ? 'الرصيد لنا' : 'الرصيد علينا', bold);
      s.merge(_ix(col, 1), _ix(col + 4, 1));
      put(s, col + 5, 1, totals[cur]![side]!, bold);
      s.merge(_ix(col + 5, 1), _ix(col + 6, 1));
    }
    // Row 1 per currency: "<name> / دولار" and the net balance.
    for (final (c, titleCol, netCol) in [
      (Currency.usd, 4, 10),
      (Currency.tryL, 20, 26),
      (Currency.eur, 36, 42),
    ]) {
      put(s, titleCol, 0, '${a.name} / ${c.arabic}', title);
      s.merge(_ix(titleCol, 0), _ix(titleCol + 5, 0));
      final net = totals[c]![Side.lana]! - totals[c]![Side.alayna]!;
      put(s, netCol, 0, net, title);
      s.merge(_ix(netCol, 0), _ix(netCol + 1, 0));

      final sc = summaryCols[c]!;
      put(summary, sc, 3 + i, i + 1);
      put(summary, sc + 1, 3 + i, a.name);
      put(summary, sc + 2, 3 + i, net);
      grand[c] = grand[c]! + net;
    }
  }
  for (final c in Currency.values) {
    final col = summaryCols[c]!;
    put(summary, col + 2, 1, grand[c]!, bold);
  }
  return book.encode()!;
}

// ------------------------------------------------------------ JSON backup

String encodeBackup(List<AccountData> data) => const JsonEncoder.withIndent(' ')
    .convert({
  'app': 'alrefaei_accounts',
  'version': 1,
  'exported_at': DateTime.now().toIso8601String(),
  'accounts': [
    for (final a in data)
      {
        'name': a.name,
        'note': a.note,
        'entries': [
          for (final e in a.entries) e.toMap()..remove('id')..remove('account_id'),
        ],
      },
  ],
});

List<AccountData> decodeBackup(String json) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  if (m['app'] != 'alrefaei_accounts') {
    throw const FormatException('ليس ملف نسخة احتياطية لهذا التطبيق');
  }
  return [
    for (final a in (m['accounts'] as List).cast<Map<String, dynamic>>())
      AccountData(
        a['name'] as String,
        [
          for (final e in (a['entries'] as List).cast<Map<String, dynamic>>())
            Entry.fromMap({...e, 'account_id': 0}),
        ],
        note: (a['note'] as String?) ?? '',
      ),
  ];
}
