import 'package:latlong2/latlong.dart' show LatLng;
import '../common.dart';
import 'booking.dart';
import 'maps.dart';
import 'shell.dart';
import 'account.dart';

Widget customerHome() => Shell(tabs: [
      TabDef('tab_search', Icons.search, () => const SearchTab()),
      TabDef('tab_bookings', Icons.event_note, () => const MyBookingsTab()),
      TabDef('tab_favorites', Icons.favorite, () => const FavoritesTab()),
      TabDef('tab_account', Icons.person, () => const AccountTab()),
    ]);

/// Keyword matching (English + Roman Urdu + Urdu) to service categories.
Set<int> matchCategories(String q, List<Rec> cats) {
  final s = q.trim().toLowerCase();
  if (s.isEmpty) return {};
  final out = <int>{};
  final tokens = s.split(RegExp(r'\s+'));
  const kw = <String, List<String>>{
    'electrician': ['bijli', 'electric', 'wiring', 'pankha', 'light', 'switch', 'بجلی', 'الیکٹریشن'],
    'plumber': ['nal', 'nalka', 'pipe', 'paani', 'pani', 'plumb', 'tanki', 'پلمبر', 'نلکا', 'نل'],
    'carpenter': ['lakri', 'barhai', 'darwaza', 'furniture', 'carpent', 'کارپینٹر', 'بڑھئی', 'لکڑی'],
    'painter': ['rang', 'paint', 'rangsaz', 'پینٹر', 'رنگ'],
    'ac technician': ['ac', 'a.c', 'air condition', 'cooler', 'اے سی'],
    'mechanic': ['mechanic', 'gari', 'car', 'bike', 'motorcycle', 'مکینک', 'گاڑی'],
    'mason': ['mistri', 'raj', 'rajmistri', 'cement', 'mason', 'راج', 'مستری'],
    'cleaning': ['safai', 'clean', 'صفائی'],
  };
  for (final c in cats) {
    final en = (c['name_en'] as String).toLowerCase();
    final ur = c['name_ur'] as String;
    if (en.contains(s) || s.contains(en) || ur.contains(s)) {
      out.add(c['id'] as int);
      continue;
    }
    for (final e in kw.entries) {
      if (!en.contains(e.key)) continue;
      for (final k in e.value) {
        final hit = k.length <= 3 ? tokens.contains(k) : s.contains(k);
        if (hit) out.add(c['id'] as int);
      }
    }
  }
  return out;
}

class WorkerCard extends StatelessWidget {
  final Rec w;
  final VoidCallback onTap;
  const WorkerCard({super.key, required this.w, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skills = skillsOf(w).map(catLabel).join(', ');
    final dist = w['distance'] as double?;
    final perKey = w['rate_type'] == 'hour' ? 'per_hour' : 'per_visit';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Avatar(path: w['photo'] as String?, name: w['name'] as String, r: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(w['name'] as String,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blue, size: 16),
                ]),
                Text(skills, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 2),
                Row(children: [
                  Stars(numOf(w['avg_rating']), size: 15),
                  Text(' (${w['rating_count'] ?? 0})', style: const TextStyle(fontSize: 12)),
                ]),
                Text('Rs ${numOf(w['rate']).toStringAsFixed(0)} / ${trs(perKey)}',
                    style: const TextStyle(fontSize: 13)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (dist != null)
                Text(fmtDist(dist),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 4),
              Text(trs('online'), style: const TextStyle(color: Colors.green, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  List<Rec> cats = [];
  List<Rec> results = [];
  bool loading = true;
  double usedRadius = 5;
  String? geoError;
  final qc = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    qc.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final s = context.read<AppState>();
    cats = await Db.categories();
    qc.text = s.sQuery;
    if (s.lat == null) {
      await _gps();
    } else {
      await _load();
    }
  }

  Future<void> _gps() async {
    final s = context.read<AppState>();
    if (mounted) setState(() => loading = true);
    final r = await currentLocation();
    if (!mounted) return;
    if (r.lat != null) {
      s.setLocation(r.lat!, r.lng!, trs('current_location'));
      geoError = null;
    } else {
      geoError = r.error;
    }
    await _load();
  }

  Future<void> _pickOnMap() async {
    final s = context.read<AppState>();
    final p = await Navigator.push<LatLng>(
        context,
        MaterialPageRoute(
            builder: (_) => MapPickerScreen(
                initial: s.lat != null ? LatLng(s.lat!, s.lng!) : kDefaultCenter)));
    if (p != null && mounted) {
      s.setLocation(p.latitude, p.longitude, trs('picked_location'));
      geoError = null;
      await _load();
    }
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    if (s.lat == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (mounted) setState(() => loading = true);
    Set<int>? ids;
    String? nameQ;
    if (s.sCat != null) {
      ids = {s.sCat!};
    } else if (s.sQuery.trim().isNotEmpty) {
      final m = matchCategories(s.sQuery, cats);
      if (m.isNotEmpty) {
        ids = m;
      } else {
        nameQ = s.sQuery.trim();
      }
    }
    var res = <Rec>[];
    var used = s.sRadius;
    for (final r in [2.0, 5.0, 10.0, 25.0, 50.0].where((x) => x >= s.sRadius)) {
      res = await Db.searchWorkers(
        lat: s.lat!,
        lng: s.lng!,
        categoryIds: ids,
        nameQuery: nameQ,
        radiusKm: r,
        customerId: s.uid,
        minRating: s.sMinRating,
        maxRate: s.sMaxRate,
        smart: s.sSmart,
      );
      used = r;
      if (res.isNotEmpty) break;
    }
    if (!mounted) return;
    setState(() {
      results = res;
      usedRadius = used;
      loading = false;
    });
  }

  void _openWorker(Rec w) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerDetail(workerId: w['id'] as int)));
  }

  Future<void> _filters() async {
    final s = context.read<AppState>();
    double minR = s.sMinRating;
    bool smart = s.sSmart;
    final rateC = TextEditingController(text: s.sMaxRate > 0 ? s.sMaxRate.toStringAsFixed(0) : '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trs('filters'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('${trs('min_rating')}: ${minR.toStringAsFixed(1)}'),
            Slider(
              value: minR,
              min: 0,
              max: 5,
              divisions: 10,
              onChanged: (v) => setS(() => minR = v),
            ),
            TextField(
              controller: rateC,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: trs('max_rate')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(trs('smart_rank')),
              subtitle: Text(trs('smart_rank_info')),
              value: smart,
              onChanged: (v) => setS(() => smart = v),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    minR = 0;
                    rateC.clear();
                    smart = false;
                    Navigator.pop(c, true);
                  },
                  child: Text(trs('reset')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(trs('apply'))),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok == true) {
      s.sMinRating = minR;
      s.sSmart = smart;
      s.sMaxRate = double.tryParse(rateC.text.trim()) ?? 0;
      await _load();
    }
  }

  Future<void> _urgent() async {
    final s = context.read<AppState>();
    if (s.lat == null) {
      showMsg(context, trs('need_location'));
      return;
    }
    int? cid = s.sCat;
    if (cid == null) {
      final ids = matchCategories(s.sQuery, cats);
      if (ids.length == 1) cid = ids.first;
    }
    cid ??= await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(trs('choose_service')),
        children: [
          for (final c in cats)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, c['id'] as int),
              child: Text(catLabel(c)),
            ),
        ],
      ),
    );
    if (cid == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => UrgentScreen(categoryId: cid!)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    tr(context, 'x');
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        onPressed: _urgent,
        icon: const Icon(Icons.flash_on),
        label: Text(trs('urgent')),
      ),
      body: Column(children: [
        // location bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Icon(Icons.place, color: s.lat != null ? Colors.green : Colors.red),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.lat != null
                    ? '${s.locLabel}  (${s.lat!.toStringAsFixed(4)}, ${s.lng!.toStringAsFixed(4)})'
                    : trs('no_location'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            IconButton(
                tooltip: 'GPS',
                onPressed: _gps,
                icon: const Icon(Icons.my_location)),
            IconButton(
                tooltip: trs('pick_on_map'),
                onPressed: _pickOnMap,
                icon: const Icon(Icons.edit_location_alt)),
          ]),
        ),
        if (geoError != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.orange.withAlpha(40), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text(geoErrorText(geoError), style: const TextStyle(fontSize: 12))),
              if (geoError == 'gps_off')
                TextButton(onPressed: openLocationSettings, child: Text(trs('settings'))),
              if (geoError == 'perm_forever')
                TextButton(onPressed: openAppSettings, child: Text(trs('settings'))),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: qc,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: trs('search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: qc.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            qc.clear();
                            s.sQuery = '';
                            _load();
                          }),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  s.sQuery = v;
                  s.sCat = null;
                  _load();
                },
              ),
            ),
            IconButton(onPressed: _filters, icon: const Icon(Icons.tune)),
            IconButton(
              onPressed: () => setState(() => s.sMap = !s.sMap),
              icon: Icon(s.sMap ? Icons.list : Icons.map),
            ),
          ]),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text(trs('all')),
                  selected: s.sCat == null,
                  onSelected: (_) {
                    s.sCat = null;
                    _load();
                  },
                ),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(catLabel(c)),
                    selected: s.sCat == c['id'],
                    onSelected: (_) {
                      s.sCat = c['id'] as int;
                      s.sQuery = '';
                      qc.clear();
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final r in [2.0, 5.0, 10.0, 25.0])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text('${r.toInt()} km'),
                    selected: s.sRadius == r,
                    onSelected: (_) {
                      s.sRadius = r;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (!loading && results.isNotEmpty && usedRadius > s.sRadius)
          Container(
            width: double.infinity,
            color: Colors.amber.withAlpha(50),
            padding: const EdgeInsets.all(6),
            child: Text(
              '${trs('expanded_to')} ${usedRadius.toInt()} km',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : s.lat == null
                  ? emptyState(trs('need_location'), icon: Icons.location_off)
                  : results.isEmpty
                      ? emptyState(trs('no_workers'), icon: Icons.search_off)
                      : s.sMap
                          ? WorkersMap(
                              lat: s.lat!, lng: s.lng!, workers: results, onTap: _openWorker)
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 80, top: 4),
                                itemCount: results.length,
                                itemBuilder: (c, i) =>
                                    WorkerCard(w: results[i], onTap: () => _openWorker(results[i])),
                              ),
                            ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ worker detail
class WorkerDetail extends StatefulWidget {
  final int workerId;
  const WorkerDetail({super.key, required this.workerId});
  @override
  State<WorkerDetail> createState() => _WorkerDetailState();
}

class _WorkerDetailState extends State<WorkerDetail> {
  Rec? w;
  List<Rec> reviews = [];
  bool fav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final x = await Db.workerFull(widget.workerId);
    final r = await Db.workerReviews(widget.workerId);
    final f = await Db.isFavorite(s.uid, widget.workerId);
    if (!mounted) return;
    setState(() {
      w = x;
      reviews = r;
      fav = f;
    });
  }

  Future<void> _report() async {
    final s = context.read<AppState>();
    final reason = await askText(context, trs('report_reason'), lines: 3);
    if (reason == null) return;
    await Db.reportUser(s.uid, widget.workerId, reason);
    if (mounted) showMsg(context, trs('report_sent'));
  }

  Future<void> _block() async {
    final s = context.read<AppState>();
    if (!await confirm(context, trs('confirm_block'))) return;
    await Db.blockWorker(s.uid, widget.workerId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final x = w;
    if (x == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    double? dist;
    if (s.lat != null && x['latitude'] != null) {
      dist = haversineKm(s.lat!, s.lng!, numOf(x['latitude']), numOf(x['longitude']));
    }
    final portfolio = ((x['portfolio'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList();
    final online = x['is_available'] == 1;
    final perKey = x['rate_type'] == 'hour' ? 'per_hour' : 'per_visit';
    return Scaffold(
      appBar: AppBar(
        title: Text(x['name'] as String),
        actions: [
          IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.red : null),
            onPressed: () async {
              await Db.toggleFavorite(s.uid, widget.workerId);
              _load();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (c) => [
              PopupMenuItem(value: 'report', child: Text(trs('report'))),
              PopupMenuItem(value: 'block', child: Text(trs('block'))),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: online
                ? () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => BookingForm(worker: x)))
                : null,
            icon: const Icon(Icons.event_available),
            label: Text(online ? trs('book_now') : trs('offline')),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
        Section(children: [
          Row(children: [
            Avatar(path: x['photo'] as String?, name: x['name'] as String, r: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                      child: Text(x['name'] as String,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  if (x['verif_status'] == 'approved')
                    const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.verified, color: Colors.blue, size: 20)),
                ]),
                Row(children: [
                  Stars(numOf(x['avg_rating']), size: 18),
                  Text(' ${numOf(x['avg_rating']).toStringAsFixed(1)} (${x['rating_count']})'),
                ]),
                Text(skillsOf(x).map(catLabel).join(', '),
                    style: const TextStyle(color: Colors.black54)),
              ]),
            ),
          ]),
          const Divider(height: 24),
          kv(trs('rate'), 'Rs ${numOf(x['rate']).toStringAsFixed(0)} / ${trs(perKey)}'),
          kv(trs('experience'), '${x['experience']} ${trs('years')}'),
          kv(trs('work_hours'), (x['work_hours'] as String?) ?? ''),
          kv(trs('completed_jobs'), '${x['completed_jobs']}'),
          if (dist != null) kv(trs('distance'), fmtDist(dist)),
          kv(trs('area'), (x['address'] as String?) ?? ''),
          kv(trs('status'), online ? trs('online') : trs('offline')),
        ]),
        if (((x['bio'] as String?) ?? '').isNotEmpty)
          Section(title: trs('about'), children: [Text(x['bio'] as String)]),
        Section(title: trs('contact'), children: [
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => callPhone(x['phone'] as String),
                icon: const Icon(Icons.call),
                label: Text(trs('call'))),
            OutlinedButton.icon(
                onPressed: () => openWhatsApp(x['phone'] as String),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp')),
            OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            otherId: x['id'] as int, otherName: x['name'] as String))),
                icon: const Icon(Icons.message),
                label: Text(trs('chat'))),
          ]),
        ]),
        if (portfolio.isNotEmpty)
          Section(title: trs('portfolio'), children: [
            SizedBox(
              height: 110,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in portfolio)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(8), child: fileImg(p, w: 110, h: 110)),
                  ),
              ]),
            ),
          ]),
        Section(title: '${trs('reviews')} (${reviews.length})', children: [
          if (reviews.isEmpty) Text(trs('no_reviews'), style: const TextStyle(color: Colors.grey)),
          for (final r in reviews)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(r['cust_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Stars((r['rating'] as num).toDouble(), size: 14),
                ]),
                if (((r['comment'] as String?) ?? '').isNotEmpty) Text(r['comment'] as String),
                Text(fmtTime(r['created_at'] as int?),
                    style: const TextStyle(fontSize: 11, color: Colors.black45)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- favorites
class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});
  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  List<Rec> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final l = await Db.favorites(s.uid);
    for (final w in l) {
      if (s.lat != null && w['latitude'] != null) {
        w['distance'] = haversineKm(s.lat!, s.lng!, numOf(w['latitude']), numOf(w['longitude']));
      }
    }
    if (!mounted) return;
    setState(() {
      items = l;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    tr(context, 'x');
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return emptyState(trs('no_favorites'), icon: Icons.favorite_border);
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      itemCount: items.length,
      itemBuilder: (c, i) => WorkerCard(
        w: items[i],
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => WorkerDetail(workerId: items[i]['id'] as int)));
          _load();
        },
      ),
    );
  }
}
