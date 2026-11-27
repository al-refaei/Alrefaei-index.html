# حسابات الرفاعي – Alrefaei Accounts

A Flutter mobile app (Android / iOS) that replaces the Excel ledger
`دفتر الأرصدة` used by the exchange office. It works **fully offline**: all
data is stored in a local SQLite database on the phone.

## How it maps to the workbook

| Workbook | App |
|---|---|
| Sheet **الأرصدة** (balance per account in USD / TRY / EUR + totals) | Home screen: three total cards (net, plus total لنا / علينا) and the account list with balances |
| One sheet per account | Account screen with a tab per currency |
| Blocks **لنا** / **علينا** | Each entry has a side: لنا (owed to us) or علينا (owed by us) |
| البيان، المبلغ، السعر، العمولة | Entry form fields |
| القيمة = `IFERROR(المبلغ/السعر,"")` | `value = amount / rate` (0 if rate = 0) |
| الرصيد = `IFERROR(القيمة+العمولة,"")` | `total = value + commission` |
| `K1 = Σلنا − Σعلينا` | Account net balance; positive = لنا, negative = علينا |

Extras the workbook does not have: entry dates, running balance per line,
search, a counter‑entry option (post the same value on the opposite side of
another account, e.g. customer ↔ agent), sharing a text statement
(WhatsApp etc.), Excel export in the original layout, Excel import of the
original layout, and JSON backup / restore.

### Import rules
Import follows the sheet formulas exactly, so the balances match Excel:

* a line counts only when `المبلغ ÷ السعر` is computable (an amount without a
  rate is skipped, as Excel's `IFERROR` does – the app lists these lines);
* a blank amount with a rate counts its commission only;
* a hand‑typed القيمة (no formula) is used as is.

Importing the original workbook reproduces the الأرصدة sheet totals exactly.

## Build & run

```bash
flutter pub get
flutter test                       # unit + database tests
LEDGER_XLSX=/path/to/file.xlsx LEDGER_TOTALS=usd,try,eur flutter test   # checks a real workbook against its الأرصدة totals
flutter run                        # on a connected phone / emulator
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
```

To ship the app pre‑loaded with your balances, copy your workbook to
`assets/seed/initial.xlsx` before building. It is imported once on first
launch. That path is git‑ignored so financial data never enters the repo.
Without it the app starts empty and offers **استيراد من Excel**.

## Code layout

```
lib/
  models.dart        accounting model and formulas
  database.dart      local SQLite storage (sqflite)
  file_io.dart       Excel import/export (original layout) and JSON backup
  main.dart          app setup (Arabic, RTL), first-run seed
  ui/home_screen.dart     الأرصدة – totals and accounts
  ui/account_screen.dart  account statement per currency
  ui/entry_form.dart      add / edit / delete an entry
  ui/data_actions.dart    import / export / backup menu
test/ledger_test.dart
```
