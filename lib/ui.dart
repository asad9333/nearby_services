import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'db.dart';
import 'i18n.dart';
import 'state.dart';

/// Translate and rebuild when the language changes (use inside build()).
String tr(BuildContext c, String k) {
  c.watch<AppState>();
  return trs(k);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B7A75)),
    appBarTheme: const AppBarTheme(centerTitle: true),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

void showMsg(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

Future<bool> confirm(BuildContext c, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(trs('no'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(trs('yes'))),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext c, String title,
    {String initial = '', bool number = false, int lines = 1}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : TextInputType.text,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(trs('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: Text(trs('ok'))),
      ],
    ),
  );
  if (r == null || r.isEmpty) return null;
  return r;
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String catLabel(Rec c) =>
    (curLang == 'ur' ? c['name_ur'] : c['name_en']) as String? ?? '';

String bookingCat(Rec b) =>
    (curLang == 'ur' ? b['cat_ur'] : b['cat_en']) as String? ?? '';

List<Rec> skillsOf(Rec w) => ((w['skills'] as List?) ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

double numOf(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

Future<String?> pickImage(BuildContext context) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: Text(trs('camera')),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: Text(trs('gallery')),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1000, imageQuality: 70);
    if (x == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/img_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(x.path).copy(dest);
    return dest;
  } catch (e) {
    return null;
  }
}

Future<void> callPhone(String p) async {
  try {
    await launchUrl(Uri(scheme: 'tel', path: p));
  } catch (_) {}
}

Future<void> openWhatsApp(String p) async {
  try {
    await launchUrl(Uri.parse('https://wa.me/${Db.waNumber(p)}'),
        mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> openNav(double lat, double lng) async {
  try {
    await launchUrl(
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
        mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Widget fileImg(String? path, {double? w, double? h, BoxFit fit = BoxFit.cover}) {
  if (path == null || path.isEmpty || !File(path).existsSync()) {
    return Container(
      width: w,
      height: h,
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }
  return Image.file(File(path), width: w, height: h, fit: fit);
}

class Avatar extends StatelessWidget {
  final String? path;
  final String name;
  final double r;
  const Avatar({super.key, this.path, required this.name, this.r = 24});

  @override
  Widget build(BuildContext context) {
    final has = path != null && path!.isNotEmpty && File(path!).existsSync();
    return CircleAvatar(
      radius: r,
      backgroundImage: has ? FileImage(File(path!)) : null,
      child: has
          ? null
          : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: r * 0.8)),
    );
  }
}

class Stars extends StatelessWidget {
  final double rating;
  final double size;
  const Stars(this.rating, {super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final icons = <Widget>[];
    for (var i = 1; i <= 5; i++) {
      IconData ic;
      if (rating >= i - 0.25) {
        ic = Icons.star;
      } else if (rating >= i - 0.75) {
        ic = Icons.star_half;
      } else {
        ic = Icons.star_border;
      }
      icons.add(Icon(ic, size: size, color: Colors.amber.shade700));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: icons);
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'completed':
        c = Colors.green;
        break;
      case 'cancelled':
      case 'rejected':
        c = Colors.red;
        break;
      case 'requested':
        c = Colors.orange;
        break;
      default:
        c = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withAlpha(120)),
      ),
      child: Text(trs('st_$status'),
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(color: Colors.black54))),
        Expanded(child: Text(v)),
      ]),
    );

class Section extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const Section({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title!,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ...children,
        ]),
      ),
    );
  }
}

Widget emptyState(String msg, {IconData icon = Icons.inbox}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Colors.grey),
          const SizedBox(height: 10),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ]),
      ),
    );

String geoErrorText(String? e) {
  switch (e) {
    case 'gps_off':
      return trs('gps_off');
    case 'perm_denied':
      return trs('perm_denied');
    case 'perm_forever':
      return trs('perm_forever');
    default:
      return trs('loc_fail');
  }
}
