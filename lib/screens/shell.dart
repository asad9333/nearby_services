import 'dart:async';
import '../common.dart';
import 'notifications.dart';

class TabDef {
  final String key;
  final IconData icon;
  final Widget Function() build;
  TabDef(this.key, this.icon, this.build);
}

class Shell extends StatefulWidget {
  final List<TabDef> tabs;
  final bool showBell;
  const Shell({super.key, required this.tabs, this.showBell = true});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().refreshUnread();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) context.read<AppState>().refreshUnread();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(trs(widget.tabs[i].key)),
        actions: [
          if (widget.showBell)
            IconButton(
              icon: Badge(
                label: Text('${st.unread}'),
                isLabelVisible: st.unread > 0,
                child: const Icon(Icons.notifications),
              ),
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                if (mounted) st.refreshUnread();
              },
            ),
          TextButton(
            onPressed: () => st.setLang(st.lang == 'en' ? 'ur' : 'en'),
            child: Text(st.lang == 'en' ? 'اردو' : 'EN'),
          ),
        ],
      ),
      body: widget.tabs[i].build(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (x) => setState(() => i = x),
        destinations: [
          for (final t in widget.tabs)
            NavigationDestination(icon: Icon(t.icon), label: trs(t.key)),
        ],
      ),
    );
  }
}

Future<void> doLogout(BuildContext context) async {
  final st = context.read<AppState>();
  Navigator.of(context).popUntil((r) => r.isFirst);
  await st.setUser(null);
}
