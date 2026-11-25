import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Account data as read from or written to a file (Excel / JSON backup).
class AccountData {
  AccountData(this.name, this.entries, {this.note = ''});
  final String name;
  final String note;

  /// Entries without ids; their accountId is ignored.
  final List<Entry> entries;
}

/// All data is kept on the device in a local SQLite file – no network needed.
class LedgerDb {
  LedgerDb._(this.db);
  final Database db;

  static Future<LedgerDb> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'ledger.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE accounts(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              note TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE entries(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
              currency TEXT NOT NULL,
              side TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              amount REAL NOT NULL,
              rate REAL NOT NULL DEFAULT 1,
              commission REAL NOT NULL DEFAULT 0,
              date INTEGER NOT NULL
            )''');
          await db.execute(
              'CREATE INDEX idx_entries_account ON entries(account_id, currency)');
          await db.execute('''
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)''');
        },
      ),
    );
    return LedgerDb._(db);
  }

  Future<void> close() => db.close();

  // ---------------------------------------------------------------- meta
  Future<String?> getMeta(String key) async {
    final r = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) => db.insert(
      'meta', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ------------------------------------------------------------ accounts
  Future<List<Account>> accounts() async {
    final rows = await db.query('accounts', orderBy: 'id');
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> accountByName(String name) async {
    final r = await db.query('accounts',
        where: 'name = ?', whereArgs: [name.trim()]);
    return r.isEmpty ? null : Account.fromMap(r.first);
  }

  Future<Account> addAccount(String name, {String note = ''}) async {
    final a = Account(name: name.trim(), note: note);
    final id = await db.insert('accounts', a.toMap()..remove('id'));
    return a.copyWith(id: id);
  }

  Future<void> updateAccount(Account a) => db.update(
      'accounts', {'name': a.name.trim(), 'note': a.note},
      where: 'id = ?', whereArgs: [a.id]);

  Future<void> deleteAccount(int id) =>
      db.delete('accounts', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- entries
  Future<List<Entry>> entries(int accountId, {Currency? currency}) async {
    final rows = await db.query(
      'entries',
      where: currency == null
          ? 'account_id = ?'
          : 'account_id = ? AND currency = ?',
      whereArgs: currency == null ? [accountId] : [accountId, currency.code],
      orderBy: 'date, id',
    );
    return rows.map(Entry.fromMap).toList();
  }

  Future<int> addEntry(Entry e) => db.insert('entries', e.toMap()..remove('id'));

  Future<void> updateEntry(Entry e) => db.update(
      'entries', e.toMap()..remove('id'),
      where: 'id = ?', whereArgs: [e.id]);

  Future<void> deleteEntry(int id) =>
      db.delete('entries', where: 'id = ?', whereArgs: [id]);

  /// Balances of every account – the equivalent of the "الأرصدة" sheet.
  Future<List<AccountBalance>> balances() async {
    final accs = await accounts();
    final map = {for (final a in accs) a.id!: AccountBalance(a)};
    final rows = await db.rawQuery('''
      SELECT account_id, currency, side,
             SUM(CASE WHEN rate = 0 THEN 0 ELSE amount / rate END + commission) AS total
      FROM entries GROUP BY account_id, currency, side''');
    for (final r in rows) {
      final b = map[r['account_id'] as int];
      if (b == null) continue;
      b.totals[Currency.fromCode(r['currency'] as String)]!.add(
          Side.fromCode(r['side'] as String), (r['total'] as num).toDouble());
    }
    return map.values.toList();
  }

  // ------------------------------------------------------- bulk import
  /// Loads accounts from a file. When [replace] is true all existing data is
  /// removed first; otherwise entries are appended and accounts with the same
  /// name are merged.
  Future<void> importAll(List<AccountData> data, {required bool replace}) async {
    await db.transaction((txn) async {
      if (replace) {
        await txn.delete('entries');
        await txn.delete('accounts');
      }
      for (final a in data) {
        final existing = await txn.query('accounts',
            where: 'name = ?', whereArgs: [a.name.trim()]);
        final int id;
        if (existing.isNotEmpty) {
          id = existing.first['id'] as int;
        } else {
          id = await txn.insert('accounts', {
            'name': a.name.trim(),
            'note': a.note,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
        final batch = txn.batch();
        for (final e in a.entries) {
          batch.insert('entries', e.copyWith(accountId: id).toMap()..remove('id'));
        }
        await batch.commit(noResult: true);
      }
    });
  }

  /// Full snapshot for Excel export / JSON backup.
  Future<List<AccountData>> exportAll() async {
    final out = <AccountData>[];
    for (final a in await accounts()) {
      out.add(AccountData(a.name, await entries(a.id!), note: a.note));
    }
    return out;
  }
}
