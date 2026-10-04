import '../common.dart';
import 'shell.dart';

Widget adminHome() => Shell(showBell: true, tabs: [
      TabDef('tab_dashboard', Icons.dashboard, () => const AdminDashboard()),
      TabDef('tab_verifications', Icons.verified_user, () => const AdminVerifications()),
      TabDef('tab_users', Icons.people, () => const AdminUsers()),
      TabDef('tab_complaints', Icons.report, () => const AdminComplaints()),
      TabDef('tab_categories', Icons.category, () => const AdminCategories()),
    ]);

// --------------------------------------------------------------- dashboard
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Rec? s;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await Db.stats();
    if (mounted) setState(() => s = x);
  }

  Future<void> _demo() async {
    final st = context.read<AppState>();
    setState(() => busy = true);
    double lat = 28.4212, lng = 70.2989;
    final r = await currentLocation();
    if (r.lat != null) {
      lat = r.lat!;
      lng = r.lng!;
    }
    final n = await Db.seedDemo(lat, lng, 12);
    await Db.audit(st.uid, 'demo_seed', '$n workers');
    if (!mounted) return;
    setState(() => busy = false);
    showMsg(context, '$n ${trs('demo_added')}');
    _load();
  }

  Widget _card(IconData i, String v, String l) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Icon(i, color: Theme.of(context).colorScheme.primary),
              Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(l, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    tr(context, 'x');
    final x = s;
    if (x == null) return const Center(child: CircularProgressIndicator());
    final perCat = (x['per_cat'] as List).cast<Rec>();
    final top = (x['top'] as List).cast<Rec>();
    final areas = (x['areas'] as List).cast<Rec>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Row(children: [
            _card(Icons.person, '${x['customers']}', trs('customers')),
            _card(Icons.engineering, '${x['workers']}', trs('workers')),
            _card(Icons.verified, '${x['verified']}', trs('verified')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            _card(Icons.pending_actions, '${x['pending']}', trs('pending_verif')),
            _card(Icons.event_note, '${x['active']}', trs('active_bookings')),
            _card(Icons.check_circle, '${x['completed']}', trs('completed_jobs')),
          ]),
        ),
        Section(title: trs('workers_per_category'), children: [
          for (final c in perCat)
            kv(curLang == 'ur' ? c['name_ur'] as String : c['name_en'] as String, '${c['n']}'),
        ]),
        Section(title: trs('top_rated'), children: [
          if (top.isEmpty) Text(trs('no_reviews'), style: const TextStyle(color: Colors.grey)),
          for (final t in top)
            Row(children: [
              Expanded(child: Text(t['name'] as String)),
              Stars(numOf(t['avg_rating']), size: 14),
              Text(' ${numOf(t['avg_rating']).toStringAsFixed(1)} (${t['rating_count']})'),
            ]),
        ]),
        Section(title: trs('area_demand'), children: [
          if (areas.isEmpty) Text(trs('no_bookings'), style: const TextStyle(color: Colors.grey)),
          for (final a in areas) kv('${a['la']}, ${a['ln']}', '${a['n']} ${trs('bookings')}'),
        ]),
        Section(title: trs('tools'), children: [
          FilledButton.icon(
            onPressed: busy ? null : _demo,
            icon: const Icon(Icons.group_add),
            label: Text(trs('add_demo')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirm(context, trs('confirm_remove_demo'))) {
                await Db.removeDemo();
                _load();
              }
            },
            icon: const Icon(Icons.delete_sweep),
            label: Text(trs('remove_demo')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AuditLogScreen())),
            icon: const Icon(Icons.history),
            label: Text(trs('audit_log')),
          ),
        ]),
        Section(children: [
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
      ]),
    );
  }
}

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'audit_log'))),
      body: FutureBuilder<List<Rec>>(
        future: Db.auditLog(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          if (l.isEmpty) return emptyState(trs('empty'));
          return ListView.separated(
            itemCount: l.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, i) => ListTile(
              dense: true,
              title: Text('${l[i]['action']} — ${l[i]['detail']}'),
              subtitle: Text('${l[i]['actor_name'] ?? '-'} • ${fmtTime(l[i]['created_at'] as int?)}'),
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------- verifications
class AdminVerifications extends StatefulWidget {
  const AdminVerifications({super.key});
  @override
  State<AdminVerifications> createState() => _AdminVerificationsState();
}

class _AdminVerificationsState extends State<AdminVerifications> {
  List<Rec> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Db.verifications('pending');
    if (!mounted) return;
    setState(() {
      items = l;
      loading = false;
    });
  }

  Future<void> _decide(Rec w, bool approve) async {
    final st = context.read<AppState>();
    String remarks = '';
    if (!approve) {
      final r = await askText(context, trs('reject_reason'), lines: 2);
      if (r == null) return;
      remarks = r;
    }
    await Db.reviewVerification(st.uid, w['id'] as int, approve, remarks);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    tr(context, 'x');
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return emptyState(trs('no_pending'), icon: Icons.verified_user);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final w = items[i];
          return Section(children: [
            Row(children: [
              Avatar(path: w['photo'] as String?, name: w['name'] as String, r: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('${w['phone']}'),
                  Text('CNIC: ${w['cnic']}'),
                  Text('${w['address'] ?? ''}'),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            if (w['cnic_image'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: fileImg(w['cnic_image'] as String?, w: double.infinity, h: 180, fit: BoxFit.contain),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: FilledButton(
                      onPressed: () => _decide(w, true), child: Text(trs('approve')))),
              const SizedBox(width: 10),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => _decide(w, false), child: Text(trs('reject')))),
            ]),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------- users
class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});
  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  List<Rec> items = [];
  final q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Db.allUsers(q.text);
    if (mounted) setState(() => items = l);
  }

  @override
  Widget build(BuildContext context) {
    tr(context, 'x');
    final st = context.read<AppState>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
          controller: q,
          decoration: InputDecoration(
              hintText: trs('search_users'), prefixIcon: const Icon(Icons.search), isDense: true),
          onChanged: (_) => _load(),
        ),
      ),
      Expanded(
        child: items.isEmpty
            ? emptyState(trs('empty'), icon: Icons.people_outline)
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final u = items[i];
                  final active = u['status'] == 'active';
                  return ListTile(
                    leading: Avatar(path: u['photo'] as String?, name: u['name'] as String),
                    title: Text(u['name'] as String),
                    subtitle: Text('${u['phone']} • ${trs('role_${u['role']}')}'),
                    trailing: TextButton(
                      onPressed: () async {
                        await Db.setUserStatus(st.uid, u['id'] as int, active ? 'suspended' : 'active');
                        _load();
                      },
                      child: Text(active ? trs('suspend') : trs('activate'),
                          style: TextStyle(color: active ? Colors.red : Colors.green)),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// -------------------------------------------------------------- complaints
class AdminComplaints extends StatefulWidget {
  const AdminComplaints({super.key});
  @override
  State<AdminComplaints> createState() => _AdminComplaintsState();
}

class _AdminComplaintsState extends State<AdminComplaints> {
  List<Rec> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Db.complaints();
    if (!mounted) return;
    setState(() {
      items = l;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    tr(context, 'x');
    final st = context.read<AppState>();
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return emptyState(trs('no_complaints'), icon: Icons.report_off);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final x = items[i];
          final open = x['status'] == 'open';
          return Section(children: [
            Row(children: [
              Text('#${x['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(trs('c_${x['status']}'),
                  style: TextStyle(color: open ? Colors.orange : Colors.grey)),
            ]),
            kv(trs('reported_by'), '${x['reporter_name']}'),
            kv(trs('reported_user'), '${x['reported_name']} (${x['reported_status']})'),
            kv(trs('reason'), '${x['reason']}'),
            kv(trs('created'), fmtTime(x['created_at'] as int?)),
            if (open)
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await Db.resolveComplaint(st.uid, x['id'] as int, x['reported_id'] as int, false);
                      _load();
                    },
                    child: Text(trs('dismiss')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      await Db.resolveComplaint(st.uid, x['id'] as int, x['reported_id'] as int, true);
                      _load();
                    },
                    child: Text(trs('suspend')),
                  ),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}

// -------------------------------------------------------------- categories
class AdminCategories extends StatefulWidget {
  const AdminCategories({super.key});
  @override
  State<AdminCategories> createState() => _AdminCategoriesState();
}

class _AdminCategoriesState extends State<AdminCategories> {
  List<Rec> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Db.categories(activeOnly: false);
    if (mounted) setState(() => items = l);
  }

  Future<void> _edit(Rec? c) async {
    final st = context.read<AppState>();
    final en = TextEditingController(text: c == null ? '' : c['name_en'] as String);
    final ur = TextEditingController(text: c == null ? '' : c['name_ur'] as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c == null ? trs('add_category') : trs('edit_category')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: en, decoration: const InputDecoration(labelText: 'English')),
          const SizedBox(height: 10),
          TextField(controller: ur, decoration: const InputDecoration(labelText: 'اردو')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(trs('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(trs('save'))),
        ],
      ),
    );
    if (ok != true || en.text.trim().isEmpty || ur.text.trim().isEmpty) return;
    await Db.saveCategory(st.uid, c == null ? null : c['id'] as int, en.text.trim(), ur.text.trim());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    tr(context, 'x');
    final st = context.read<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(null), child: const Icon(Icons.add)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final x = items[i];
          final on = x['active'] == 1;
          return ListTile(
            title: Text(catLabel(x)),
            subtitle: Text('${x['name_en']} • ${x['name_ur']}'),
            leading: const Icon(Icons.category),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => _edit(x), icon: const Icon(Icons.edit)),
              Switch(
                value: on,
                onChanged: (v) async {
                  await Db.toggleCategory(st.uid, x['id'] as int, v);
                  _load();
                },
              ),
            ]),
          );
        },
      ),
    );
  }
}
