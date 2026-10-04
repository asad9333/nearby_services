import 'package:flutter/services.dart';
import 'common.dart';
import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/customer.dart';
import 'screens/worker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Db.init();
  final state = AppState();
  await state.restore();
  runApp(ChangeNotifierProvider<AppState>.value(value: state, child: const NearbyApp()));
}

class NearbyApp extends StatelessWidget {
  const NearbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget home;
    if (s.user == null) {
      home = const LoginScreen();
    } else if (s.role == 'admin') {
      home = adminHome();
    } else if (s.role == 'worker') {
      home = workerHome();
    } else {
      home = customerHome();
    }
    return MaterialApp(
      title: 'Nearby Services',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Directionality(
        textDirection: s.lang == 'ur' ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: KeyedSubtree(key: ValueKey('${s.user?['id']}-${s.role}'), child: home),
    );
  }
}
