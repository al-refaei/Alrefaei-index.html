import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../file_io.dart';
import '../main.dart';
import 'common.dart';

String _stamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}_${two(n.hour)}${two(n.minute)}';
}

Future<void> _shareFile(String name, List<int> bytes, String mime) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: mime)],
    subject: name,
  ));
}

Future<void> exportExcelFlow(BuildContext context) async {
  final data = await ledger.exportAll();
  final bytes = exportWorkbook(data);
  await _shareFile('الأرصدة_${_stamp()}.xlsx', bytes,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}

Future<void> backupFlow(BuildContext context) async {
  final data = await ledger.exportAll();
  await _shareFile('نسخة_احتياطية_${_stamp()}.json',
      utf8.encode(encodeBackup(data)), 'application/json');
}

/// Asks whether to replace everything or merge. Returns null when cancelled.
Future<bool?> _askReplace(BuildContext context, String summary) =>
    showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الاستيراد'),
        content: Text('$summary\n\n'
            '«استبدال الكل» يحذف البيانات الحالية ويضع بيانات الملف مكانها.\n'
            '«دمج» يضيف القيود إلى الحسابات (ويجمع الحسابات ذات الاسم نفسه).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('دمج')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استبدال الكل')),
        ],
      ),
    );

Future<List<int>?> _pick(List<String> ext) async {
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ext);
  if (f == null) return null;
  return f.readAsBytes();
}

Future<void> importExcelFlow(BuildContext context) async {
  try {
    final bytes = await _pick(['xlsx']);
    if (bytes == null || !context.mounted) return;
    final result = importWorkbook(bytes);
    if (result.accounts.isEmpty) {
      toast(context, 'لم يتم العثور على أوراق حسابات بالتنسيق المعروف');
      return;
    }
    final replace = await _askReplace(context,
        'تم العثور على ${result.accounts.length} حساب و ${result.entryCount} قيد.');
    if (replace == null) return;
    await ledger.importAll(result.accounts, replace: replace);
    if (!context.mounted) return;
    if (result.warnings.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('ملاحظات الاستيراد'),
          content: SingleChildScrollView(child: Text(result.warnings.join('\n'))),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
        ),
      );
    } else {
      toast(context, 'تم الاستيراد بنجاح');
    }
  } catch (e) {
    if (context.mounted) toast(context, 'تعذر قراءة الملف: $e');
  }
}

Future<void> restoreFlow(BuildContext context) async {
  try {
    final bytes = await _pick(['json']);
    if (bytes == null || !context.mounted) return;
    final data = decodeBackup(utf8.decode(bytes));
    final n = data.fold<int>(0, (s, a) => s + a.entries.length);
    final replace = await _askReplace(
        context, 'النسخة تحتوي ${data.length} حساب و $n قيد.');
    if (replace == null) return;
    await ledger.importAll(data, replace: replace);
    if (context.mounted) toast(context, 'تمت الاستعادة بنجاح');
  } catch (e) {
    if (context.mounted) toast(context, 'تعذرت الاستعادة: $e');
  }
}

class DataMenu extends StatelessWidget {
  const DataMenu({super.key, required this.onChanged});
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'export':
            await exportExcelFlow(context);
          case 'import':
            await importExcelFlow(context);
          case 'backup':
            await backupFlow(context);
          case 'restore':
            await restoreFlow(context);
        }
        await onChanged();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: 'export',
            child: ListTile(leading: Icon(Icons.grid_on), title: Text('تصدير إلى Excel'))),
        PopupMenuItem(
            value: 'import',
            child: ListTile(leading: Icon(Icons.upload_file), title: Text('استيراد من Excel'))),
        PopupMenuDivider(),
        PopupMenuItem(
            value: 'backup',
            child: ListTile(leading: Icon(Icons.backup_outlined), title: Text('نسخة احتياطية'))),
        PopupMenuItem(
            value: 'restore',
            child: ListTile(leading: Icon(Icons.restore), title: Text('استعادة نسخة'))),
      ],
    );
  }
}
