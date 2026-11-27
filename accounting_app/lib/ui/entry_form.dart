import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../models.dart';
import 'common.dart';

/// Opens the add/edit form. Returns true when something was saved or deleted.
Future<bool> showEntryForm(BuildContext context,
    {required Account account, required Currency currency, Entry? entry}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => EntryForm(account: account, currency: currency, entry: entry),
  );
  return r ?? false;
}

class EntryForm extends StatefulWidget {
  const EntryForm({super.key, required this.account, required this.currency, this.entry});
  final Account account;
  final Currency currency;
  final Entry? entry;

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final _form = GlobalKey<FormState>();
  late Side _side = widget.entry?.side ?? Side.lana;
  late Currency _currency = widget.entry?.currency ?? widget.currency;
  late DateTime _date = widget.entry?.date ?? DateTime.now();
  late final _desc = TextEditingController(text: widget.entry?.description ?? '');
  late final _amount = TextEditingController(
      text: widget.entry == null ? '' : plain(widget.entry!.amount).replaceAll(',', ''));
  late final _rate = TextEditingController(
      text: plain(widget.entry?.rate ?? 1).replaceAll(',', ''));
  late final _comm = TextEditingController(
      text: widget.entry == null || widget.entry!.commission == 0
          ? ''
          : plain(widget.entry!.commission).replaceAll(',', ''));
  List<Account> _others = [];
  int? _counterId;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    for (final c in [_amount, _rate, _comm]) {
      c.addListener(() => setState(() {}));
    }
    if (_isNew) {
      ledger.accounts().then((a) {
        if (mounted) {
          setState(() => _others = a.where((x) => x.id != widget.account.id).toList());
        }
      });
    }
  }

  Entry? _build() {
    final amount = parseNumber(_amount.text);
    final rate = parseNumber(_rate.text) ?? 1;
    final comm = parseNumber(_comm.text) ?? 0;
    if (amount == null) return null;
    return Entry(
      id: widget.entry?.id,
      accountId: widget.account.id!,
      currency: _currency,
      side: _side,
      description: _desc.text.trim(),
      amount: amount,
      rate: rate,
      commission: comm,
      date: _date,
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final e = _build()!;
    if (_isNew) {
      await ledger.addEntry(e);
      if (_counterId != null) {
        // Same value on the opposite side of the counter account.
        await ledger.addEntry(e.copyWith(
          accountId: _counterId,
          side: _side.opposite,
          description: e.description.isEmpty
              ? 'مقابل ${widget.account.name}'
              : '${e.description} (مقابل ${widget.account.name})',
        ));
      }
    } else {
      await ledger.updateEntry(e);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'حذف القيد', 'هل تريد حذف هذا القيد؟')) return;
    await ledger.deleteEntry(widget.entry!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  String? _numValidator(String? v, {bool required = false, bool nonZero = false}) {
    if (v == null || v.trim().isEmpty) return required ? 'مطلوب' : null;
    final n = parseNumber(v);
    if (n == null) return 'رقم غير صالح';
    if (nonZero && n == 0) return 'لا يمكن أن يكون صفراً';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _build();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_isNew ? 'قيد جديد – ${widget.account.name}' : 'تعديل قيد – ${widget.account.name}',
                style: t.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<Side>(
              segments: [
                for (final s in Side.values)
                  ButtonSegment<Side>(
                    value: s,
                    label: Text(s.arabic),
                    icon: Icon(s == Side.lana ? Icons.south_west : Icons.north_east),
                  ),
              ],
              selected: {_side},
              onSelectionChanged: (v) => setState(() => _side = v.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: sideColor(_side).withValues(alpha: 0.15),
                selectedForegroundColor: sideColor(_side),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<Currency>(
              segments: [
                for (final c in Currency.values)
                  ButtonSegment(value: c, label: Text('${c.arabic} ${c.symbol}')),
              ],
              selected: {_currency},
              onSelectionChanged: (v) => setState(() => _currency = v.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'البيان'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _amount,
                  autofocus: _isNew,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  validator: (v) => _numValidator(v, required: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _rate,
                  decoration: const InputDecoration(labelText: 'السعر', helperText: 'القيمة = المبلغ ÷ السعر'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => _numValidator(v, nonZero: true),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _comm,
              decoration: const InputDecoration(labelText: 'العمولة'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: _numValidator,
            ),
            const SizedBox(height: 12),
            Card(
              color: sideColor(_side).withValues(alpha: 0.07),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                  Text('القيمة: ${preview == null ? '—' : money(preview.value)}'),
                  Text(
                    'الرصيد: ${preview == null ? '—' : money(preview.total)} ${_currency.symbol}',
                    style: TextStyle(color: sideColor(_side), fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('التاريخ: ${dateFmt.format(_date)}'),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) {
                  setState(() => _date = DateTime(d.year, d.month, d.day,
                      _date.hour, _date.minute, _date.second));
                }
              },
            ),
            if (_isNew && _others.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: _counterId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'قيد مقابل في حساب آخر (اختياري)',
                  helperText: 'يُسجَّل نفس الرصيد في الجهة المعاكسة بالحساب المختار',
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('بدون')),
                  for (final a in _others)
                    DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _counterId = v),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            Row(children: [
              if (!_isNew)
                IconButton.outlined(
                  tooltip: 'حذف',
                  color: alaynaColor,
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
              if (!_isNew) const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('حفظ'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
