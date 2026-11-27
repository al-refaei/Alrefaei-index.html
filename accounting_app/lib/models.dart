/// Core accounting model, mirroring the original workbook:
///
/// * Every account (ورقة) holds three currencies: USD, TRY, EUR.
/// * Each currency has two sides: "لنا" (owed to us / debit) and
///   "علينا" (owed by us / credit).
/// * A line: البيان, المبلغ, السعر, القيمة = المبلغ ÷ السعر,
///   العمولة, الرصيد = القيمة + العمولة.
/// * Account balance per currency = Σ لنا − Σ علينا.
library;

enum Currency {
  usd('USD', 'دولار', r'$'),
  tryL('TRY', 'تركي', '₺'),
  eur('EUR', 'يورو', '€');

  const Currency(this.code, this.arabic, this.symbol);
  final String code;
  final String arabic;
  final String symbol;

  static Currency fromCode(String code) =>
      Currency.values.firstWhere((c) => c.code == code);
}

enum Side {
  /// لنا – the account owes us (debit, increases balance).
  lana('IN', 'لنا'),

  /// علينا – we owe the account (credit, decreases balance).
  alayna('OUT', 'علينا');

  const Side(this.code, this.arabic);
  final String code;
  final String arabic;

  Side get opposite => this == Side.lana ? Side.alayna : Side.lana;

  static Side fromCode(String code) =>
      Side.values.firstWhere((s) => s.code == code);
}

class Account {
  Account({this.id, required this.name, this.note = '', DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String name;
  final String note;
  final DateTime createdAt;

  Account copyWith({int? id, String? name, String? note}) => Account(
        id: id ?? this.id,
        name: name ?? this.name,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        note: (m['note'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (m['created_at'] as int?) ?? 0),
      );
}

class Entry {
  Entry({
    this.id,
    required this.accountId,
    required this.currency,
    required this.side,
    this.description = '',
    required this.amount,
    this.rate = 1,
    this.commission = 0,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  final int? id;
  final int accountId;
  final Currency currency;
  final Side side;
  final String description;

  /// المبلغ
  final double amount;

  /// السعر – the amount is divided by this to obtain the value.
  final double rate;

  /// العمولة – added to the value on the same side.
  final double commission;
  final DateTime date;

  /// القيمة = المبلغ ÷ السعر (0 when the rate is 0, like IFERROR in Excel).
  double get value => rate == 0 ? 0 : amount / rate;

  /// الرصيد = القيمة + العمولة
  double get total => value + commission;

  /// Signed effect on the account balance.
  double get signedTotal => side == Side.lana ? total : -total;

  Entry copyWith({
    int? id,
    int? accountId,
    Currency? currency,
    Side? side,
    String? description,
    double? amount,
    double? rate,
    double? commission,
    DateTime? date,
  }) =>
      Entry(
        id: id ?? this.id,
        accountId: accountId ?? this.accountId,
        currency: currency ?? this.currency,
        side: side ?? this.side,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        rate: rate ?? this.rate,
        commission: commission ?? this.commission,
        date: date ?? this.date,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'currency': currency.code,
        'side': side.code,
        'description': description,
        'amount': amount,
        'rate': rate,
        'commission': commission,
        'date': date.millisecondsSinceEpoch,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        accountId: m['account_id'] as int,
        currency: Currency.fromCode(m['currency'] as String),
        side: Side.fromCode(m['side'] as String),
        description: (m['description'] as String?) ?? '',
        amount: (m['amount'] as num).toDouble(),
        rate: (m['rate'] as num).toDouble(),
        commission: (m['commission'] as num).toDouble(),
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
      );
}

/// Totals of one currency of one account (or of everything).
class SideTotals {
  double lana = 0;
  double alayna = 0;
  double get net => lana - alayna;

  void add(Side side, double total) {
    if (side == Side.lana) {
      lana += total;
    } else {
      alayna += total;
    }
  }
}

/// Balances of one account in all currencies.
class AccountBalance {
  AccountBalance(this.account);
  final Account account;
  final Map<Currency, SideTotals> totals = {
    for (final c in Currency.values) c: SideTotals(),
  };

  double net(Currency c) => totals[c]!.net;
  bool get hasBalance =>
      Currency.values.any((c) => !isZero(net(c)));
}

bool isZero(double v) => v.abs() < 0.005;

/// Grand totals as in the "الأرصدة" sheet, plus receivables/payables split.
class GrandTotal {
  double net = 0;

  /// Sum of positive account balances (receivables – لنا).
  double receivable = 0;

  /// Sum of negative account balances, as a positive number (payables – علينا).
  double payable = 0;
}

Map<Currency, GrandTotal> grandTotals(Iterable<AccountBalance> balances) {
  final out = {for (final c in Currency.values) c: GrandTotal()};
  for (final b in balances) {
    for (final c in Currency.values) {
      final n = b.net(c);
      out[c]!.net += n;
      if (n > 0) out[c]!.receivable += n;
      if (n < 0) out[c]!.payable += -n;
    }
  }
  return out;
}

/// Parses user-typed numbers, accepting Arabic-Indic digits and separators.
double? parseNumber(String? input) {
  if (input == null) return null;
  var s = input.trim();
  if (s.isEmpty) return null;
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final a = arabic.indexOf(ch);
    final p = persian.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (p >= 0) {
      b.write(p);
    } else if (ch == '٫') {
      b.write('.');
    } else if (ch == '٬' || ch == ',' || ch == ' ') {
      // thousands separators – ignore
    } else {
      b.write(ch);
    }
  }
  return double.tryParse(b.toString());
}
