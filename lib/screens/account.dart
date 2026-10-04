import '../common.dart';
import 'shell.dart';

class AccountTab extends StatelessWidget {
  final List<Widget> extra;
  const AccountTab({super.key, this.extra = const []});

  Future<void> _changePw(BuildContext context) async {
    final st = context.read<AppState>();
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(trs('change_password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: oldC,
              obscureText: true,
              decoration: InputDecoration(labelText: trs('old_password'))),
          const SizedBox(height: 10),
          TextField(
              controller: newC,
              obscureText: true,
              decoration: InputDecoration(labelText: trs('new_password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(trs('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(trs('ok'))),
        ],
      ),
    );
    if (ok != true) return;
    if (newC.text.length < 6) {
      if (context.mounted) showMsg(context, trs('err_pw_short'));
      return;
    }
    final done = await Db.changePassword(st.uid, oldC.text, newC.text);
    if (context.mounted) showMsg(context, trs(done ? 'password_changed' : 'err_old_password'));
  }

  Future<void> _editName(BuildContext context) async {
    final st = context.read<AppState>();
    final v = await askText(context, trs('full_name'), initial: st.userName);
    if (v == null) return;
    await Db.updateUser(st.uid, {'name': v});
    await st.reloadUser();
  }

  Future<void> _photo(BuildContext context) async {
    final st = context.read<AppState>();
    final p = await pickImage(context);
    if (p == null) return;
    await Db.updateUser(st.uid, {'photo': p});
    await st.reloadUser();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return ListView(children: [
      Section(children: [
        Row(children: [
          GestureDetector(
            onTap: () => _photo(context),
            child: Avatar(path: st.user?['photo'] as String?, name: st.userName, r: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${st.user?['phone'] ?? ''}'),
              Text(trs('role_${st.role}'), style: const TextStyle(color: Colors.black54)),
            ]),
          ),
          IconButton(onPressed: () => _editName(context), icon: const Icon(Icons.edit)),
        ]),
      ]),
      ...extra,
      Section(children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.language),
          title: Text(trs('language')),
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('EN')),
              ButtonSegment(value: 'ur', label: Text('اردو')),
            ],
            selected: {st.lang},
            onSelectionChanged: (s) => st.setLang(s.first),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock),
          title: Text(trs('change_password')),
          onTap: () => _changePw(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout, color: Colors.red),
          title: Text(trs('logout'), style: const TextStyle(color: Colors.red)),
          onTap: () async {
            if (await confirm(context, trs('confirm_logout')) && context.mounted) {
              await doLogout(context);
            }
          },
        ),
      ]),
    ]);
  }
}
