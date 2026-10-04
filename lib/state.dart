import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';
import 'i18n.dart';

class AppState extends ChangeNotifier {
  Rec? user;
  String lang = 'en';
  double? lat;
  double? lng;
  String locLabel = '';
  int unread = 0;

  // search preferences (kept while switching tabs)
  int? sCat;
  double sRadius = 5;
  double sMinRating = 0;
  double sMaxRate = 0;
  bool sSmart = false;
  String sQuery = '';
  bool sMap = false;

  int get uid => user!['id'] as int;
  String get role => (user?['role'] as String?) ?? '';
  String get userName => (user?['name'] as String?) ?? '';

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString('lang') ?? 'en';
    setCurLang(lang);
    final id = p.getInt('uid');
    if (id != null) {
      final u = await Db.userById(id);
      if (u != null && u['status'] == 'active') user = u;
    }
    if (user != null) unread = await Db.unreadCount(uid);
  }

  Future<void> setUser(Rec? u) async {
    user = u;
    final p = await SharedPreferences.getInstance();
    if (u == null) {
      await p.remove('uid');
      unread = 0;
      sCat = null;
      sQuery = '';
    } else {
      await p.setInt('uid', u['id'] as int);
      unread = await Db.unreadCount(u['id'] as int);
    }
    notifyListeners();
  }

  Future<void> reloadUser() async {
    if (user == null) return;
    user = await Db.userById(uid);
    notifyListeners();
  }

  Future<void> setLang(String l) async {
    lang = l;
    setCurLang(l);
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
    notifyListeners();
  }

  Future<void> refreshUnread() async {
    if (user == null) return;
    final n = await Db.unreadCount(uid);
    if (n != unread) {
      unread = n;
      notifyListeners();
    }
  }

  void setLocation(double a, double b, String label) {
    lat = a;
    lng = b;
    locLabel = label;
    notifyListeners();
  }

  void touch() => notifyListeners();
}
