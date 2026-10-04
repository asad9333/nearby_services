import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'geo.dart';

typedef Rec = Map<String, dynamic>;

const String _bookingSelect = '''
SELECT b.*, c.name_en AS cat_en, c.name_ur AS cat_ur,
 cu.name AS cust_name, cu.phone AS cust_phone,
 wu.name AS worker_name, wu.phone AS worker_phone, wu.photo AS worker_photo,
 (SELECT rating FROM reviews r WHERE r.booking_id = b.id) AS review_rating,
 (SELECT comment FROM reviews r WHERE r.booking_id = b.id) AS review_comment,
 (SELECT COUNT(*) FROM broadcast_targets t WHERE t.booking_id = b.id) AS target_count
FROM bookings b
LEFT JOIN categories c ON c.id = b.category_id
JOIN users cu ON cu.id = b.customer_id
LEFT JOIN users wu ON wu.id = b.worker_id
''';

class Db {
  static late Database db;

  static int now() => DateTime.now().millisecondsSinceEpoch;

  static String hash(String p) =>
      sha256.convert(utf8.encode('nbsvc::$p')).toString();

  static String normPhone(String p) {
    var d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('92') && d.length == 12) d = '0${d.substring(2)}';
    return d;
  }

  static String waNumber(String p) {
    final d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('0')) return '92${d.substring(1)}';
    return d;
  }

  static List<Rec> _l(List<Map<String, Object?>> r) =>
      r.map((e) => Map<String, dynamic>.from(e)).toList();

  static double _d(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

  // ---------------------------------------------------------------- init
  static Future<void> init() async {
    final path = join(await getDatabasesPath(), 'nearby_services.db');
    db = await openDatabase(path, version: 1, onCreate: _create);
  }

  static Future<void> _create(Database d, int v) async {
    await d.execute('''CREATE TABLE users(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      phone TEXT UNIQUE NOT NULL, email TEXT, role TEXT NOT NULL,
      password_hash TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active',
      photo TEXT, created_at INTEGER NOT NULL)''');
    await d.execute('''CREATE TABLE categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name_en TEXT NOT NULL,
      name_ur TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)''');
    await d.execute('''CREATE TABLE worker_profiles(
      user_id INTEGER PRIMARY KEY, bio TEXT DEFAULT '', experience INTEGER DEFAULT 0,
      rate REAL DEFAULT 0, rate_type TEXT DEFAULT 'visit',
      work_hours TEXT DEFAULT '9 AM - 6 PM', latitude REAL, longitude REAL,
      address TEXT DEFAULT '', service_radius REAL DEFAULT 10,
      is_available INTEGER DEFAULT 0, verif_status TEXT DEFAULT 'none',
      cnic TEXT DEFAULT '', cnic_image TEXT, admin_remarks TEXT DEFAULT '',
      avg_rating REAL DEFAULT 0, rating_count INTEGER DEFAULT 0,
      completed_jobs INTEGER DEFAULT 0, avg_response_sec REAL DEFAULT 0,
      portfolio TEXT DEFAULT '')''');
    await d.execute(
        'CREATE INDEX idx_wp_loc ON worker_profiles(latitude, longitude)');
    await d.execute('''CREATE TABLE worker_skills(
      worker_id INTEGER, category_id INTEGER, PRIMARY KEY(worker_id, category_id))''');
    await d.execute('''CREATE TABLE bookings(
      id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER NOT NULL,
      worker_id INTEGER, category_id INTEGER, description TEXT, photo TEXT,
      address TEXT, lat REAL, lng REAL, preferred_time TEXT, status TEXT,
      quote REAL, quote_status TEXT DEFAULT 'none', is_urgent INTEGER DEFAULT 0,
      expanded INTEGER DEFAULT 0, reject_ids TEXT DEFAULT '',
      created_at INTEGER, updated_at INTEGER, completed_at INTEGER)''');
    await d.execute('''CREATE TABLE broadcast_targets(
      booking_id INTEGER, worker_id INTEGER, PRIMARY KEY(booking_id, worker_id))''');
    await d.execute('''CREATE TABLE reviews(
      id INTEGER PRIMARY KEY AUTOINCREMENT, booking_id INTEGER UNIQUE,
      customer_id INTEGER, worker_id INTEGER, rating INTEGER, comment TEXT,
      created_at INTEGER)''');
    await d.execute('''CREATE TABLE messages(
      id INTEGER PRIMARY KEY AUTOINCREMENT, sender_id INTEGER, receiver_id INTEGER,
      text TEXT, created_at INTEGER)''');
    await d.execute('''CREATE TABLE favorites(
      customer_id INTEGER, worker_id INTEGER, PRIMARY KEY(customer_id, worker_id))''');
    await d.execute('''CREATE TABLE blocks(
      customer_id INTEGER, worker_id INTEGER, PRIMARY KEY(customer_id, worker_id))''');
    await d.execute('''CREATE TABLE complaints(
      id INTEGER PRIMARY KEY AUTOINCREMENT, reporter_id INTEGER, reported_id INTEGER,
      reason TEXT, status TEXT DEFAULT 'open', created_at INTEGER)''');
    await d.execute('''CREATE TABLE notifications(
      id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, type TEXT, body TEXT,
      ref_id INTEGER, is_read INTEGER DEFAULT 0, created_at INTEGER)''');
    await d.execute('''CREATE TABLE audit_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT, actor_id INTEGER, action TEXT,
      detail TEXT, created_at INTEGER)''');

    const cats = [
      ['Electrician', 'الیکٹریشن'],
      ['Plumber', 'پلمبر'],
      ['Carpenter', 'کارپینٹر'],
      ['Painter', 'پینٹر'],
      ['AC Technician', 'اے سی ٹیکنیشن'],
      ['Mechanic', 'مکینک'],
      ['Mason', 'راج مستری'],
      ['Home Cleaning', 'گھر کی صفائی'],
    ];
    for (final c in cats) {
      await d.insert('categories', {'name_en': c[0], 'name_ur': c[1], 'active': 1});
    }
    await d.insert('users', {
      'name': 'Admin',
      'phone': '03000000000',
      'email': 'admin@nearby.pk',
      'role': 'admin',
      'password_hash': hash('admin123'),
      'status': 'active',
      'created_at': now(),
    });
  }

  // ---------------------------------------------------------------- users
  static Future<Rec?> userById(int id) async {
    final r = await db.query('users', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) return null;
    return Map<String, dynamic>.from(r.first);
  }

  static Future<Rec> register({
    required String name,
    required String phone,
    String? email,
    required String password,
    required String role,
  }) async {
    final ph = normPhone(phone);
    final ex = await db.query('users', where: 'phone=?', whereArgs: [ph]);
    if (ex.isNotEmpty) throw 'err_phone_used';
    final em = (email ?? '').trim().toLowerCase();
    if (em.isNotEmpty) {
      final e = await db.query('users', where: 'lower(email)=?', whereArgs: [em]);
      if (e.isNotEmpty) throw 'err_email_used';
    }
    final id = await db.insert('users', {
      'name': name.trim(),
      'phone': ph,
      'email': em,
      'role': role,
      'password_hash': hash(password),
      'status': 'active',
      'created_at': now(),
    });
    if (role == 'worker') {
      await db.insert('worker_profiles', {'user_id': id});
    }
    await audit(id, 'register', role);
    return (await userById(id))!;
  }

  static Future<Rec?> login(String idf, String password) async {
    final s = idf.trim();
    final r = await db.query('users',
        where: '(phone=? OR lower(email)=?) AND password_hash=?',
        whereArgs: [normPhone(s), s.toLowerCase(), hash(password)]);
    if (r.isEmpty) return null;
    return Map<String, dynamic>.from(r.first);
  }

  static Future<void> updateUser(int id, Map<String, Object?> f) async {
    await db.update('users', f, where: 'id=?', whereArgs: [id]);
  }

  static Future<bool> changePassword(int id, String oldPw, String newPw) async {
    final r = await db.query('users',
        where: 'id=? AND password_hash=?', whereArgs: [id, hash(oldPw)]);
    if (r.isEmpty) return false;
    await db.update('users', {'password_hash': hash(newPw)},
        where: 'id=?', whereArgs: [id]);
    return true;
  }

  static Future<void> setUserStatus(int adminId, int uid, String status) async {
    await db.update('users', {'status': status}, where: 'id=?', whereArgs: [uid]);
    await audit(adminId, 'user_$status', 'user #$uid');
  }

  static Future<List<Rec>> allUsers(String q) async {
    final s = '%${q.trim().toLowerCase()}%';
    return _l(await db.rawQuery(
        "SELECT * FROM users WHERE role != 'admin' AND (lower(name) LIKE ? OR phone LIKE ?) ORDER BY id DESC",
        [s, s]));
  }

  // ----------------------------------------------------------- categories
  static Future<List<Rec>> categories({bool activeOnly = true}) async {
    return _l(await db.query('categories',
        where: activeOnly ? 'active=1' : null, orderBy: 'id'));
  }

  static Future<void> saveCategory(int adminId, int? id, String en, String ur) async {
    if (id == null) {
      await db.insert('categories', {'name_en': en, 'name_ur': ur, 'active': 1});
      await audit(adminId, 'category_add', en);
    } else {
      await db.update('categories', {'name_en': en, 'name_ur': ur},
          where: 'id=?', whereArgs: [id]);
      await audit(adminId, 'category_edit', en);
    }
  }

  static Future<void> toggleCategory(int adminId, int id, bool active) async {
    await db.update('categories', {'active': active ? 1 : 0},
        where: 'id=?', whereArgs: [id]);
    await audit(adminId, active ? 'category_on' : 'category_off', '#$id');
  }

  // -------------------------------------------------------------- workers
  static Future<List<Rec>> workerSkills(int uid) async {
    return _l(await db.rawQuery(
        'SELECT c.* FROM categories c JOIN worker_skills ws ON ws.category_id=c.id WHERE ws.worker_id=?',
        [uid]));
  }

  static Future<Map<int, List<Rec>>> _skillMap() async {
    final rows = _l(await db.rawQuery(
        'SELECT ws.worker_id AS wid, c.id AS id, c.name_en AS name_en, c.name_ur AS name_ur FROM worker_skills ws JOIN categories c ON c.id=ws.category_id'));
    final m = <int, List<Rec>>{};
    for (final r in rows) {
      m.putIfAbsent(r['wid'] as int, () => <Rec>[]).add(r);
    }
    return m;
  }

  static Future<Rec?> workerFull(int uid) async {
    final r = await db.rawQuery(
        'SELECT u.id AS id, u.name AS name, u.phone AS phone, u.email AS email, u.photo AS photo, u.status AS status, w.* FROM users u JOIN worker_profiles w ON w.user_id=u.id WHERE u.id=?',
        [uid]);
    if (r.isEmpty) return null;
    final m = Map<String, dynamic>.from(r.first);
    m['skills'] = await workerSkills(uid);
    return m;
  }

  static Future<void> saveWorkerProfile(int uid, Map<String, Object?> f) async {
    await db.update('worker_profiles', f, where: 'user_id=?', whereArgs: [uid]);
  }

  static Future<void> setWorkerSkills(int uid, List<int> ids) async {
    await db.delete('worker_skills', where: 'worker_id=?', whereArgs: [uid]);
    for (final c in ids) {
      await db.insert('worker_skills', {'worker_id': uid, 'category_id': c});
    }
  }

  static Future<void> setAvailable(int uid, bool on) async {
    await db.update('worker_profiles', {'is_available': on ? 1 : 0},
        where: 'user_id=?', whereArgs: [uid]);
  }

  static Future<void> submitVerification(int uid, String cnic, String cnicImage) async {
    await db.update(
        'worker_profiles',
        {
          'cnic': cnic,
          'cnic_image': cnicImage,
          'verif_status': 'pending',
          'admin_remarks': ''
        },
        where: 'user_id=?',
        whereArgs: [uid]);
    await notifyRole('admin', 'verif_new', null);
  }

  static Future<List<Rec>> verifications(String status) async {
    return _l(await db.rawQuery(
        'SELECT u.id AS id, u.name AS name, u.phone AS phone, u.photo AS photo, w.cnic AS cnic, w.cnic_image AS cnic_image, w.verif_status AS verif_status, w.address AS address, w.experience AS experience, w.rate AS rate FROM users u JOIN worker_profiles w ON w.user_id=u.id WHERE w.verif_status=? ORDER BY u.id DESC',
        [status]));
  }

  static Future<void> reviewVerification(
      int adminId, int workerId, bool approve, String remarks) async {
    await db.update(
        'worker_profiles',
        {
          'verif_status': approve ? 'approved' : 'rejected',
          'admin_remarks': remarks,
          if (approve) 'is_available': 1,
        },
        where: 'user_id=?',
        whereArgs: [workerId]);
    await notify(workerId, approve ? 'verif_ok' : 'verif_no', remarks, null);
    await audit(adminId, approve ? 'verify_approve' : 'verify_reject', 'worker #$workerId');
  }

  static double _score(Rec w, double radius) {
    final d = w['distance'] as double;
    var rt = _d(w['avg_rating']);
    if (rt == 0) rt = 3;
    final resp = min(_d(w['avg_response_sec']), 600.0);
    return 0.6 * (d / radius) + 0.25 * ((5 - rt) / 5) + 0.15 * (resp / 600);
  }

  static Future<List<Rec>> searchWorkers({
    required double lat,
    required double lng,
    Set<int>? categoryIds,
    String? nameQuery,
    required double radiusKm,
    int? customerId,
    double minRating = 0,
    double maxRate = 0,
    bool smart = false,
  }) async {
    final dLat = radiusKm / 111.0;
    final dLng = radiusKm / (111.0 * max(0.05, cos(lat * pi / 180)));
    final sb = StringBuffer(
        "SELECT u.id AS id, u.name AS name, u.phone AS phone, u.photo AS photo, w.* FROM users u JOIN worker_profiles w ON w.user_id=u.id WHERE u.role='worker' AND u.status='active' AND w.verif_status='approved' AND w.is_available=1 AND w.latitude BETWEEN ? AND ? AND w.longitude BETWEEN ? AND ?");
    if (categoryIds != null && categoryIds.isNotEmpty) {
      sb.write(
          ' AND u.id IN (SELECT worker_id FROM worker_skills WHERE category_id IN (${categoryIds.join(',')}))');
    }
    if (customerId != null) {
      sb.write(
          ' AND u.id NOT IN (SELECT worker_id FROM blocks WHERE customer_id = $customerId)');
    }
    final rows = _l(await db.rawQuery(
        sb.toString(), [lat - dLat, lat + dLat, lng - dLng, lng + dLng]));
    final skills = await _skillMap();
    final nq = (nameQuery ?? '').trim().toLowerCase();
    final out = <Rec>[];
    for (final r in rows) {
      final d = haversineKm(lat, lng, _d(r['latitude']), _d(r['longitude']));
      if (d > radiusKm) continue;
      final sr = r['service_radius'] == null ? 10.0 : _d(r['service_radius']);
      if (d > sr) continue;
      if (_d(r['avg_rating']) < minRating) continue;
      if (maxRate > 0 && _d(r['rate']) > maxRate) continue;
      r['skills'] = skills[r['id'] as int] ?? <Rec>[];
      if (nq.isNotEmpty) {
        final hay = '${r['name']} ${r['bio']} ' +
            (r['skills'] as List<Rec>)
                .map((c) => '${c['name_en']} ${c['name_ur']}')
                .join(' ');
        if (!hay.toLowerCase().contains(nq)) continue;
      }
      r['distance'] = d;
      out.add(r);
    }
    if (smart) {
      out.sort((a, b) => _score(a, radiusKm).compareTo(_score(b, radiusKm)));
    } else {
      out.sort((a, b) {
        final x = ((a['distance'] as double) * 10).round();
        final y = ((b['distance'] as double) * 10).round();
        if (x != y) return x.compareTo(y);
        final c = _d(b['avg_rating']).compareTo(_d(a['avg_rating']));
        if (c != 0) return c;
        return (a['distance'] as double).compareTo(b['distance'] as double);
      });
    }
    return out;
  }

  static Future<List<Rec>> workerReviews(int wid) async {
    return _l(await db.rawQuery(
        'SELECT r.*, u.name AS cust_name FROM reviews r JOIN users u ON u.id=r.customer_id WHERE r.worker_id=? ORDER BY r.id DESC LIMIT 30',
        [wid]));
  }

  // ------------------------------------------------- favorites/block/report
  static Future<bool> isFavorite(int cid, int wid) async {
    final r = await db.query('favorites',
        where: 'customer_id=? AND worker_id=?', whereArgs: [cid, wid]);
    return r.isNotEmpty;
  }

  static Future<void> toggleFavorite(int cid, int wid) async {
    if (await isFavorite(cid, wid)) {
      await db.delete('favorites',
          where: 'customer_id=? AND worker_id=?', whereArgs: [cid, wid]);
    } else {
      await db.insert('favorites', {'customer_id': cid, 'worker_id': wid},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<List<Rec>> favorites(int cid) async {
    final rows = _l(await db.rawQuery(
        'SELECT u.id AS id, u.name AS name, u.phone AS phone, u.photo AS photo, u.status AS status, w.* FROM favorites f JOIN users u ON u.id=f.worker_id JOIN worker_profiles w ON w.user_id=u.id WHERE f.customer_id=?',
        [cid]));
    final skills = await _skillMap();
    for (final r in rows) {
      r['skills'] = skills[r['id'] as int] ?? <Rec>[];
    }
    return rows;
  }

  static Future<void> blockWorker(int cid, int wid) async {
    await db.insert('blocks', {'customer_id': cid, 'worker_id': wid},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('favorites',
        where: 'customer_id=? AND worker_id=?', whereArgs: [cid, wid]);
  }

  static Future<void> reportUser(int reporter, int reported, String reason) async {
    await db.insert('complaints', {
      'reporter_id': reporter,
      'reported_id': reported,
      'reason': reason,
      'status': 'open',
      'created_at': now(),
    });
    await notifyRole('admin', 'complaint_new', null);
  }

  static Future<List<Rec>> complaints() async {
    return _l(await db.rawQuery(
        'SELECT c.*, r.name AS reporter_name, d.name AS reported_name, d.status AS reported_status FROM complaints c JOIN users r ON r.id=c.reporter_id JOIN users d ON d.id=c.reported_id ORDER BY (c.status=\'open\') DESC, c.id DESC'));
  }

  static Future<void> resolveComplaint(int adminId, int id, int reportedId, bool suspend) async {
    await db.update('complaints', {'status': suspend ? 'actioned' : 'dismissed'},
        where: 'id=?', whereArgs: [id]);
    if (suspend) {
      await db.update('users', {'status': 'suspended'},
          where: 'id=?', whereArgs: [reportedId]);
      await audit(adminId, 'suspend', 'user #$reportedId (complaint #$id)');
    } else {
      await audit(adminId, 'complaint_dismiss', '#$id');
    }
  }

  // ------------------------------------------------------------- bookings
  static Future<Rec?> bookingById(int id) async {
    final r = await db.rawQuery('$_bookingSelect WHERE b.id=?', [id]);
    if (r.isEmpty) return null;
    return Map<String, dynamic>.from(r.first);
  }

  static Future<List<Rec>> customerBookings(int cid) async {
    return _l(await db.rawQuery(
        '$_bookingSelect WHERE b.customer_id=? ORDER BY b.id DESC', [cid]));
  }

  static Future<List<Rec>> workerJobs(int wid, List<String> statuses) async {
    final ph = List.filled(statuses.length, '?').join(',');
    return _l(await db.rawQuery(
        '$_bookingSelect WHERE b.worker_id=? AND b.status IN ($ph) ORDER BY b.id DESC',
        [wid, ...statuses]));
  }

  static Future<List<Rec>> workerRequests(int wid) async {
    return _l(await db.rawQuery(
        "$_bookingSelect WHERE b.status='requested' AND (b.worker_id=? OR (b.worker_id IS NULL AND b.id IN (SELECT booking_id FROM broadcast_targets WHERE worker_id=?))) ORDER BY b.id DESC",
        [wid, wid]));
  }

  static Future<int> createBooking({
    required int customerId,
    required int workerId,
    required int categoryId,
    required String description,
    String? photo,
    required String address,
    required double lat,
    required double lng,
    String? preferred,
  }) async {
    final t = now();
    final id = await db.insert('bookings', {
      'customer_id': customerId,
      'worker_id': workerId,
      'category_id': categoryId,
      'description': description,
      'photo': photo,
      'address': address,
      'lat': lat,
      'lng': lng,
      'preferred_time': preferred,
      'status': 'requested',
      'quote_status': 'none',
      'is_urgent': 0,
      'created_at': t,
      'updated_at': t,
    });
    await notify(workerId, 'b_new', '#$id', id);
    return id;
  }

  static Future<int?> createUrgent({
    required int customerId,
    required int categoryId,
    required String description,
    String? photo,
    required String address,
    required double lat,
    required double lng,
  }) async {
    final cand = await searchWorkers(
        lat: lat, lng: lng, categoryIds: {categoryId}, radiusKm: 50, customerId: customerId);
    if (cand.isEmpty) return null;
    final t = now();
    final id = await db.insert('bookings', {
      'customer_id': customerId,
      'worker_id': null,
      'category_id': categoryId,
      'description': description,
      'photo': photo,
      'address': address,
      'lat': lat,
      'lng': lng,
      'status': 'requested',
      'quote_status': 'none',
      'is_urgent': 1,
      'created_at': t,
      'updated_at': t,
    });
    for (final w in cand.take(5)) {
      await db.insert('broadcast_targets', {'booking_id': id, 'worker_id': w['id']},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await notify(w['id'] as int, 'b_urgent', '#$id', id);
    }
    return id;
  }

  static Future<int> expandUrgent(int bid) async {
    final b = await bookingById(bid);
    if (b == null || b['worker_id'] != null || b['status'] != 'requested') return 0;
    final have = _l(await db.query('broadcast_targets',
            where: 'booking_id=?', whereArgs: [bid]))
        .map((e) => e['worker_id'] as int)
        .toSet();
    final cand = await searchWorkers(
        lat: _d(b['lat']),
        lng: _d(b['lng']),
        categoryIds: {b['category_id'] as int},
        radiusKm: 100,
        customerId: b['customer_id'] as int);
    final fresh = cand.where((w) => !have.contains(w['id'] as int)).take(5).toList();
    for (final w in fresh) {
      await db.insert('broadcast_targets', {'booking_id': bid, 'worker_id': w['id']},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await notify(w['id'] as int, 'b_urgent', '#$bid', bid);
    }
    await db.rawUpdate('UPDATE bookings SET expanded = expanded + 1 WHERE id=?', [bid]);
    return fresh.length;
  }

  static Future<bool> acceptBooking(int bid, int wid) async {
    final b = await bookingById(bid);
    if (b == null) return false;
    final t = now();
    int n;
    if (b['is_urgent'] == 1 && b['worker_id'] == null) {
      n = await db.rawUpdate(
          "UPDATE bookings SET worker_id=?, status='accepted', updated_at=? WHERE id=? AND worker_id IS NULL AND status='requested'",
          [wid, t, bid]);
    } else {
      n = await db.rawUpdate(
          "UPDATE bookings SET status='accepted', updated_at=? WHERE id=? AND worker_id=? AND status='requested'",
          [t, bid, wid]);
    }
    if (n == 0) return false;
    final sec = (t - (b['created_at'] as int)) / 1000.0;
    await db.rawUpdate(
        'UPDATE worker_profiles SET avg_response_sec = CASE WHEN avg_response_sec = 0 THEN ? ELSE avg_response_sec * 0.7 + ? * 0.3 END WHERE user_id=?',
        [sec, sec, wid]);
    await notify(b['customer_id'] as int, 'b_accepted', '#$bid', bid);
    if (b['is_urgent'] == 1) {
      final others = await db.query('broadcast_targets',
          where: 'booking_id=? AND worker_id != ?', whereArgs: [bid, wid]);
      for (final o in others) {
        await notify(o['worker_id'] as int, 'b_taken', '#$bid', bid);
      }
    }
    return true;
  }

  static Future<void> rejectBooking(int bid, int wid) async {
    final b = await bookingById(bid);
    if (b == null) return;
    if (b['is_urgent'] == 1 && b['worker_id'] == null) {
      await db.delete('broadcast_targets',
          where: 'booking_id=? AND worker_id=?', whereArgs: [bid, wid]);
      return;
    }
    final rj = '${b['reject_ids'] ?? ''}$wid,';
    await db.update('bookings',
        {'status': 'rejected', 'reject_ids': rj, 'updated_at': now()},
        where: 'id=? AND worker_id=?', whereArgs: [bid, wid]);
    await notify(b['customer_id'] as int, 'b_rejected', '#$bid', bid);
  }

  static Future<Rec?> nextNearestFor(int bid) async {
    final b = await bookingById(bid);
    if (b == null) return null;
    final rejected = '${b['reject_ids'] ?? ''}'
        .split(',')
        .where((e) => e.isNotEmpty)
        .map(int.parse)
        .toSet();
    final cand = await searchWorkers(
        lat: _d(b['lat']),
        lng: _d(b['lng']),
        categoryIds: {b['category_id'] as int},
        radiusKm: 100,
        customerId: b['customer_id'] as int);
    for (final w in cand) {
      if (!rejected.contains(w['id'] as int)) return w;
    }
    return null;
  }

  static Future<void> reassign(int bid, int newWid) async {
    await db.update(
        'bookings',
        {
          'worker_id': newWid,
          'status': 'requested',
          'quote': null,
          'quote_status': 'none',
          'created_at': now(),
          'updated_at': now(),
        },
        where: 'id=?',
        whereArgs: [bid]);
    await notify(newWid, 'b_new', '#$bid', bid);
  }

  static Future<void> setStatus(int bid, String status, int actorId) async {
    final b = await bookingById(bid);
    if (b == null) return;
    final t = now();
    await db.update(
        'bookings',
        {
          'status': status,
          'updated_at': t,
          if (status == 'completed') 'completed_at': t,
        },
        where: 'id=?',
        whereArgs: [bid]);
    if (status == 'completed' && b['worker_id'] != null) {
      await db.rawUpdate(
          'UPDATE worker_profiles SET completed_jobs = completed_jobs + 1 WHERE user_id=?',
          [b['worker_id']]);
    }
    final other = actorId == b['customer_id'] ? b['worker_id'] : b['customer_id'];
    if (other != null) {
      await notify(other as int, 'b_$status', '#$bid', bid);
    }
  }

  static Future<void> sendQuote(int bid, double amount) async {
    final b = await bookingById(bid);
    if (b == null) return;
    await db.update('bookings',
        {'quote': amount, 'quote_status': 'sent', 'updated_at': now()},
        where: 'id=?', whereArgs: [bid]);
    await notify(b['customer_id'] as int, 'b_quote', '#$bid', bid);
  }

  static Future<void> respondQuote(int bid, bool accept) async {
    final b = await bookingById(bid);
    if (b == null) return;
    await db.update(
        'bookings', {'quote_status': accept ? 'accepted' : 'declined', 'updated_at': now()},
        where: 'id=?', whereArgs: [bid]);
    if (b['worker_id'] != null) {
      await notify(b['worker_id'] as int,
          accept ? 'b_quote_ok' : 'b_quote_no', '#$bid', bid);
    }
  }

  static Future<bool> addReview(int bid, int rating, String comment) async {
    final b = await bookingById(bid);
    if (b == null || b['status'] != 'completed' || b['worker_id'] == null) return false;
    final ex = await db.query('reviews', where: 'booking_id=?', whereArgs: [bid]);
    if (ex.isNotEmpty) return false;
    final wid = b['worker_id'] as int;
    await db.insert('reviews', {
      'booking_id': bid,
      'customer_id': b['customer_id'],
      'worker_id': wid,
      'rating': rating,
      'comment': comment,
      'created_at': now(),
    });
    final a = await db.rawQuery(
        'SELECT AVG(rating) AS a, COUNT(*) AS n FROM reviews WHERE worker_id=?', [wid]);
    await db.update(
        'worker_profiles',
        {'avg_rating': _d(a.first['a']), 'rating_count': a.first['n']},
        where: 'user_id=?',
        whereArgs: [wid]);
    await notify(wid, 'b_review', '#$bid', bid);
    return true;
  }

  static Future<Rec> earnings(int wid) async {
    final a = await db.rawQuery(
        "SELECT COUNT(*) AS n, COALESCE(SUM(CASE WHEN quote_status='accepted' THEN quote ELSE 0 END),0) AS total FROM bookings WHERE worker_id=? AND status='completed'",
        [wid]);
    final n = DateTime.now();
    final start = DateTime(n.year, n.month).millisecondsSinceEpoch;
    final m = await db.rawQuery(
        "SELECT COUNT(*) AS n, COALESCE(SUM(CASE WHEN quote_status='accepted' THEN quote ELSE 0 END),0) AS total FROM bookings WHERE worker_id=? AND status='completed' AND completed_at>=?",
        [wid, start]);
    return {
      'n': a.first['n'],
      'total': _d(a.first['total']),
      'month_n': m.first['n'],
      'month_total': _d(m.first['total']),
    };
  }

  // ------------------------------------------------------------- messages
  static Future<List<Rec>> thread(int a, int b) async {
    return _l(await db.rawQuery(
        'SELECT * FROM messages WHERE (sender_id=? AND receiver_id=?) OR (sender_id=? AND receiver_id=?) ORDER BY id',
        [a, b, b, a]));
  }

  static Future<void> sendMessage(int from, int to, String text) async {
    await db.insert('messages', {
      'sender_id': from,
      'receiver_id': to,
      'text': text,
      'created_at': now(),
    });
    final ex = await db.query('notifications',
        where: "user_id=? AND type='msg' AND ref_id=? AND is_read=0",
        whereArgs: [to, from]);
    if (ex.isEmpty) await notify(to, 'msg', '', from);
  }

  // -------------------------------------------------------- notifications
  static Future<void> notify(int uid, String type, String? body, int? ref) async {
    await db.insert('notifications', {
      'user_id': uid,
      'type': type,
      'body': body ?? '',
      'ref_id': ref,
      'is_read': 0,
      'created_at': now(),
    });
  }

  static Future<void> notifyRole(String role, String type, int? ref) async {
    final us = await db.query('users', where: 'role=?', whereArgs: [role]);
    for (final u in us) {
      await notify(u['id'] as int, type, '', ref);
    }
  }

  static Future<List<Rec>> notifications(int uid) async {
    return _l(await db.query('notifications',
        where: 'user_id=?', whereArgs: [uid], orderBy: 'id DESC', limit: 100));
  }

  static Future<int> unreadCount(int uid) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM notifications WHERE user_id=? AND is_read=0', [uid]);
    return (r.first['n'] as int?) ?? 0;
  }

  static Future<void> markAllRead(int uid) async {
    await db.update('notifications', {'is_read': 1},
        where: 'user_id=?', whereArgs: [uid]);
  }

  // ---------------------------------------------------------------- admin
  static Future<void> audit(int? actor, String action, String detail) async {
    await db.insert('audit_log',
        {'actor_id': actor, 'action': action, 'detail': detail, 'created_at': now()});
  }

  static Future<List<Rec>> auditLog() async {
    return _l(await db.rawQuery(
        'SELECT a.*, u.name AS actor_name FROM audit_log a LEFT JOIN users u ON u.id=a.actor_id ORDER BY a.id DESC LIMIT 200'));
  }

  static Future<int> _count(String sql) async {
    final r = await db.rawQuery(sql);
    return (r.first.values.first as int?) ?? 0;
  }

  static Future<Rec> stats() async {
    return {
      'customers': await _count("SELECT COUNT(*) FROM users WHERE role='customer'"),
      'workers': await _count("SELECT COUNT(*) FROM users WHERE role='worker'"),
      'verified': await _count(
          "SELECT COUNT(*) FROM worker_profiles WHERE verif_status='approved'"),
      'pending': await _count(
          "SELECT COUNT(*) FROM worker_profiles WHERE verif_status='pending'"),
      'bookings': await _count('SELECT COUNT(*) FROM bookings'),
      'active': await _count(
          "SELECT COUNT(*) FROM bookings WHERE status IN ('requested','accepted','on_the_way','in_progress')"),
      'completed': await _count("SELECT COUNT(*) FROM bookings WHERE status='completed'"),
      'complaints': await _count("SELECT COUNT(*) FROM complaints WHERE status='open'"),
      'per_cat': _l(await db.rawQuery(
          'SELECT c.name_en AS name_en, c.name_ur AS name_ur, COUNT(ws.worker_id) AS n FROM categories c LEFT JOIN worker_skills ws ON ws.category_id=c.id GROUP BY c.id ORDER BY n DESC')),
      'top': _l(await db.rawQuery(
          "SELECT u.name AS name, w.avg_rating AS avg_rating, w.rating_count AS rating_count FROM worker_profiles w JOIN users u ON u.id=w.user_id WHERE w.rating_count>0 ORDER BY w.avg_rating DESC, w.rating_count DESC LIMIT 5")),
      'areas': _l(await db.rawQuery(
          'SELECT ROUND(lat,2) AS la, ROUND(lng,2) AS ln, COUNT(*) AS n FROM bookings WHERE lat IS NOT NULL GROUP BY la, ln ORDER BY n DESC LIMIT 5')),
    };
  }

  // ----------------------------------------------------------- demo data
  static Future<int> seedDemo(double lat, double lng, int count) async {
    final rnd = Random();
    const names = [
      'Ali Raza', 'Usman Khan', 'Bilal Ahmed', 'Hamza Sheikh', 'Imran Baloch',
      'Kashif Mehmood', 'Faisal Iqbal', 'Naveed Akhtar', 'Shahid Hussain',
      'Rashid Ali', 'Tariq Javed', 'Zubair Ahmad', 'Adnan Malik', 'Sajid Nawaz',
      'Waqas Ahmed', 'Arslan Butt'
    ];
    final cats = await categories();
    if (cats.isEmpty) return 0;
    var made = 0;
    final base = rnd.nextInt(8000);
    for (var i = 0; i < count; i++) {
      final phone = '0399${(1000000 + base * 10 + i).toString().padLeft(7, '0').substring(0, 7)}';
      final ex = await db.query('users', where: 'phone=?', whereArgs: [phone]);
      if (ex.isNotEmpty) continue;
      final id = await db.insert('users', {
        'name': names[(base + i) % names.length],
        'phone': phone,
        'email': 'demo$phone@demo.nearby.pk',
        'role': 'worker',
        'password_hash': hash('demo123'),
        'status': 'active',
        'created_at': now(),
      });
      final dLat = (rnd.nextDouble() * 2 - 1) * 0.09;
      final dLng = (rnd.nextDouble() * 2 - 1) * 0.09 / max(0.2, cos(lat * pi / 180));
      final rc = 3 + rnd.nextInt(40);
      await db.insert('worker_profiles', {
        'user_id': id,
        'bio': 'Experienced and reliable. Demo profile.',
        'experience': 1 + rnd.nextInt(15),
        'rate': (300 + rnd.nextInt(18) * 100).toDouble(),
        'rate_type': rnd.nextBool() ? 'visit' : 'hour',
        'work_hours': '9 AM - 8 PM',
        'latitude': lat + dLat,
        'longitude': lng + dLng,
        'address': 'Demo area',
        'service_radius': 15.0 + rnd.nextInt(20),
        'is_available': 1,
        'verif_status': 'approved',
        'cnic': '0000000000000',
        'avg_rating': 3.4 + rnd.nextDouble() * 1.6,
        'rating_count': rc,
        'completed_jobs': rc + rnd.nextInt(20),
        'avg_response_sec': 30.0 + rnd.nextInt(500),
      });
      final shuffled = [...cats]..shuffle(rnd);
      final k = 1 + rnd.nextInt(2);
      for (final c in shuffled.take(k)) {
        await db.insert('worker_skills', {'worker_id': id, 'category_id': c['id']});
      }
      made++;
    }
    return made;
  }

  static Future<void> removeDemo() async {
    final ids = _l(await db.query('users', where: "email LIKE '%@demo.nearby.pk'"))
        .map((e) => e['id'] as int)
        .toList();
    for (final id in ids) {
      await db.delete('worker_profiles', where: 'user_id=?', whereArgs: [id]);
      await db.delete('worker_skills', where: 'worker_id=?', whereArgs: [id]);
      await db.delete('favorites', where: 'worker_id=?', whereArgs: [id]);
      await db.delete('users', where: 'id=?', whereArgs: [id]);
    }
  }
}
