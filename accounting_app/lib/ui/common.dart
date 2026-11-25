import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _plain = NumberFormat('#,##0.####', 'en');
final dateFmt = DateFormat('yyyy/MM/dd', 'en');

/// 1,234.50
String money(double v) => _money.format(isZero(v) ? 0 : v);

/// Shows up to 4 decimals without trailing zeros (for amounts and rates).
String plain(double v) => _plain.format(v);

const lanaColor = Color(0xFF2E7D32);
const alaynaColor = Color(0xFFC62828);

Color sideColor(Side s) => s == Side.lana ? lanaColor : alaynaColor;

/// Colour for a net balance: positive = لنا (green), negative = علينا (red).
Color netColor(BuildContext context, double v) => isZero(v)
    ? Theme.of(context).colorScheme.outline
    : (v > 0 ? lanaColor : alaynaColor);

/// "703.06 لنا" / "2,217.63 علينا" / "0.00"
String netLabel(double v) {
  if (isZero(v)) return '0.00';
  return '${money(v.abs())} ${v > 0 ? Side.lana.arabic : Side.alayna.arabic}';
}

class BalanceChip extends StatelessWidget {
  const BalanceChip({super.key, required this.currency, required this.value});
  final Currency currency;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = netColor(context, value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${currency.symbol} ${netLabel(value)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body,
    {String ok = 'حذف'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: alaynaColor),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Dialog for creating / editing an account. Returns (name, note) or null.
Future<(String, String)?> accountDialog(BuildContext context,
    {String name = '', String note = '', String title = 'حساب جديد'}) {
  final nameCtl = TextEditingController(text: name);
  final noteCtl = TextEditingController(text: note);
  final formKey = GlobalKey<FormState>();
  return showDialog<(String, String)>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: nameCtl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'اسم الحساب'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: noteCtl,
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(c, (nameCtl.text.trim(), noteCtl.text.trim()));
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}
