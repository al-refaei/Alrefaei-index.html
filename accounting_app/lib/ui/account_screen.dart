import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../models.dart';
import 'common.dart';
import 'entry_form.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.account});
  final Account account;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen>
    with SingleTickerProviderStateMixin {
  late Account _account = widget.account;
  late final TabController _tabs =
      TabController(length: Currency.values.length, vsync: this);
  List<Entry>? _entries;

  Currency get _currency => Currency.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final e = await ledger.entries(_account.id!);
    if (mounted) setState(() => _entries = e);
  }

  SideTotals _totals(Currency c) {
    final t = SideTotals();
    for (final e in _entries ?? const <Entry>[]) {
      if (e.currency == c) t.add(e.side, e.total);
    }
    return t;
  }

  Future<void> _edit(Entry? e) async {
    final changed = await showEntryForm(context,
        account: _account, currency: _currency, entry: e);
    if (changed) await _load();
  }

  Future<void> _rename() async {
    final r = await accountDialog(context,
        name: _account.name, note: _account.note, title: 'تعديل الحساب');
    if (r == null) return;
    final other = await ledger.accountByName(r.$1);
    if (other != null && other.id != _account.id) {
      if (mounted) toast(context, 'يوجد حساب بهذا الاسم');
      return;
    }
    final a = _account.copyWith(name: r.$1, note: r.$2);
    await ledger.updateAccount(a);
    setState(() => _account = a);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'حذف الحساب',
        'سيتم حذف «${_account.name}» وجميع قيوده (${_entries?.length ?? 0} قيد). لا يمكن التراجع.');
    if (!ok) return;
    await ledger.deleteAccount(_account.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _share() async {
    final c = _currency;
    final list = (_entries ?? []).where((e) => e.currency == c).toList();
    final t = _totals(c);
    final b = StringBuffer()
      ..writeln('كشف حساب: ${_account.name}')
      ..writeln('العملة: ${c.arabic} (${c.code})')
      ..writeln('التاريخ: ${dateFmt.format(DateTime.now())}')
      ..writeln('────────────');
    var running = 0.0;
    for (final e in list) {
      running += e.signedTotal;
      b.writeln('${dateFmt.format(e.date)} | ${e.description.isEmpty ? '-' : e.description}'
          ' | ${e.side.arabic} ${money(e.total)} | الرصيد ${netLabel(running)}');
    }
    b
      ..writeln('────────────')
      ..writeln('مجموع لنا: ${money(t.lana)}')
      ..writeln('مجموع علينا: ${money(t.alayna)}')
      ..writeln('الرصيد النهائي: ${netLabel(t.net)} ${c.symbol}');
    await SharePlus.instance.share(ShareParams(text: b.toString(), subject: 'كشف حساب ${_account.name}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_account.name),
        actions: [
          IconButton(
              tooltip: 'مشاركة كشف الحساب',
              onPressed: _entries == null ? null : _share,
              icon: const Icon(Icons.share)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'rename' ? _rename() : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('تعديل الاسم / الملاحظة')),
              PopupMenuItem(value: 'delete', child: Text('حذف الحساب')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            for (final c in Currency.values) Tab(text: '${c.arabic} ${c.symbol}'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('قيد جديد'),
      ),
      body: _entries == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [for (final c in Currency.values) _currencyView(c)],
            ),
    );
  }

  Widget _currencyView(Currency c) {
    final list = _entries!.where((e) => e.currency == c).toList();
    final t = _totals(c);
    final running = <double>[];
    var r = 0.0;
    for (final e in list) {
      r += e.signedTotal;
      running.add(r);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        if (_account.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_account.note, style: Theme.of(context).textTheme.bodySmall),
          ),
        _SummaryCard(totals: t, currency: c),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('لا توجد قيود بهذه العملة')),
          ),
        // Newest first, like a statement read from the top.
        for (var i = list.length - 1; i >= 0; i--)
          _EntryTile(entry: list[i], running: running[i], onTap: () => _edit(list[i])),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals, required this.currency});
  final SideTotals totals;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget cell(String label, double v, Color color) => Expanded(
          child: Column(children: [
            Text(label, style: t.labelMedium),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(money(v),
                  style: t.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            cell('الرصيد لنا', totals.lana, lanaColor),
            cell('الرصيد علينا', totals.alayna, alaynaColor),
          ]),
          const Divider(height: 20),
          Text('الرصيد النهائي', style: t.labelLarge),
          const SizedBox(height: 2),
          Text(
            '${netLabel(totals.net)} ${currency.symbol}',
            style: t.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold, color: netColor(context, totals.net)),
          ),
        ]),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.running, required this.onTap});
  final Entry entry;
  final double running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = sideColor(e.side);
    final t = Theme.of(context).textTheme;
    final details = <String>[
      dateFmt.format(e.date),
      if (e.rate != 1) 'المبلغ ${plain(e.amount)} ÷ ${plain(e.rate)}',
      if (e.commission != 0) 'عمولة ${plain(e.commission)}',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.description.isEmpty ? '—' : e.description,
                    style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(details.join(' • '), style: t.bodySmall),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${e.side.arabic} ${money(e.total)}',
                  style: t.titleSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('الرصيد ${netLabel(running)}',
                  style: t.bodySmall?.copyWith(color: netColor(context, running))),
            ]),
          ]),
        ),
      ),
    );
  }
}
