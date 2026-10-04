import 'dart:async';
import '../common.dart';
import 'booking.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Rec> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = context.read<AppState>();
    final l = await Db.notifications(st.uid);
    await Db.markAllRead(st.uid);
    await st.refreshUnread();
    if (!mounted) return;
    setState(() {
      items = l;
      loading = false;
    });
  }

  Future<void> _open(Rec n) async {
    final type = n['type'] as String;
    final ref = n['ref_id'] as int?;
    if (ref == null) return;
    if (type == 'msg') {
      final u = await Db.userById(ref);
      if (u == null || !mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ChatScreen(otherId: ref, otherName: u['name'] as String)));
    } else if (type.startsWith('b_')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetail(id: ref)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'notifications'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? emptyState(trs('no_notifications'), icon: Icons.notifications_none)
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final n = items[i];
                    final body = (n['body'] as String?) ?? '';
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.notifications)),
                      title: Text(trs('n_${n['type']}')),
                      subtitle: Text(
                          '${body.isEmpty ? '' : '$body • '}${fmtTime(n['created_at'] as int?)}'),
                      onTap: () => _open(n),
                    );
                  },
                ),
    );
  }
}
