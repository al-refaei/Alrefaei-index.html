import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../models.dart';
import 'account_screen.dart';
import 'common.dart';
import 'data_actions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AccountBalance>? _balances;
  String _query = '';
  bool _onlyWithBalance = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await ledger.balances();
    if (mounted) setState(() => _balances = b);
  }

  Future<void> _addAccount() async {
    final r = await accountDialog(context);
    if (r == null) return;
    if (await ledger.accountByName(r.$1) != null) {
      if (mounted) toast(context, 'يوجد حساب بهذا الاسم');
      return;
    }
    await ledger.addAccount(r.$1, note: r.$2);
    await _load();
  }

  Future<void> _open(AccountBalance b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountScreen(account: b.account)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final balances = _balances;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأرصدة'),
        actions: [
          DataMenu(onChanged: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('حساب جديد'),
      ),
      body: balances == null
          ? const Center(child: CircularProgressIndicator())
          : balances.isEmpty
              ? _EmptyState(onChanged: _load, onAdd: _addAccount)
              : RefreshIndicator(onRefresh: _load, child: _list(balances)),
    );
  }

  Widget _list(List<AccountBalance> balances) {
    final totals = grandTotals(balances);
    final q = _query.trim();
    final shown = balances
        .where((b) => q.isEmpty || b.account.name.contains(q))
        .where((b) => !_onlyWithBalance || b.hasBalance)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Row(children: [
          for (final c in Currency.values)
            Expanded(child: _TotalCard(currency: c, total: totals[c]!)),
        ]),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'بحث عن حساب',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('ذات الرصيد فقط'),
              selected: _onlyWithBalance,
              onSelected: (v) => setState(() => _onlyWithBalance = v),
            ),
            Text('${shown.length} حساب',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        for (final b in shown) _AccountTile(balance: b, onTap: () => _open(b)),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.currency, required this.total});
  final Currency currency;
  final GrandTotal total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(children: [
          Text('${currency.arabic} ${currency.symbol}', style: t.labelLarge),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              money(total.net),
              style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: netColor(context, total.net)),
            ),
          ),
          const Divider(height: 12),
          FittedBox(
            child: Text('لنا ${money(total.receivable)}',
                style: t.bodySmall?.copyWith(color: lanaColor)),
          ),
          FittedBox(
            child: Text('علينا ${money(total.payable)}',
                style: t.bodySmall?.copyWith(color: alaynaColor)),
          ),
        ]),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.balance, required this.onTap});
  final AccountBalance balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = balance.account;
    final nonZero =
        Currency.values.where((c) => !isZero(balance.net(c))).toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              child: Text(a.name.isEmpty ? '؟' : a.name.characters.first),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (nonZero.isEmpty)
                    Text('لا يوجد رصيد',
                        style: Theme.of(context).textTheme.bodySmall)
                  else
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final c in nonZero)
                        BalanceChip(currency: c, value: balance.net(c)),
                    ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_left),
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onChanged, required this.onAdd});
  final Future<void> Function() onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('لا توجد حسابات بعد', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'استورد ملف Excel بنفس تنسيق دفتر الأرصدة، أو أضف حساباً جديداً.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await importExcelFlow(context);
              await onChanged();
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('استيراد من Excel'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('حساب جديد'),
          ),
        ]),
      ),
    );
  }
}
