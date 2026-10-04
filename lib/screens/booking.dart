import 'dart:async';
import '../common.dart';

const List<String> statusFlow = [
  'requested',
  'accepted',
  'on_the_way',
  'in_progress',
  'completed'
];

class BookingTile extends StatelessWidget {
  final Rec b;
  final bool showWorker;
  const BookingTile({super.key, required this.b, this.showWorker = true});

  @override
  Widget build(BuildContext context) {
    final who = showWorker
        ? ((b['worker_name'] as String?) ?? trs('waiting_worker'))
        : (b['cust_name'] as String? ?? '');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => BookingDetail(id: b['id'] as int))),
        leading: CircleAvatar(
          child: Icon(b['is_urgent'] == 1 ? Icons.flash_on : Icons.build),
        ),
        title: Text('#${b['id']} • ${bookingCat(b)}'),
        subtitle: Text('$who\n${fmtTime(b['created_at'] as int?)}'),
        isThreeLine: true,
        trailing: StatusChip(b['status'] as String),
      ),
    );
  }
}

// ---------------------------------------------------------------- customer
class MyBookingsTab extends StatefulWidget {
  const MyBookingsTab({super.key});
  @override
  State<MyBookingsTab> createState() => _MyBookingsTabState();
}

class _MyBookingsTabState extends State<MyBookingsTab> {
  List<Rec> items = [];
  bool loading = true;
  Timer? t;

  @override
  void initState() {
    super.initState();
    _load();
    t = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Db.customerBookings(context.read<AppState>().uid);
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
    if (items.isEmpty) return emptyState(trs('no_bookings'), icon: Icons.event_busy);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        itemCount: items.length,
        itemBuilder: (c, i) => BookingTile(b: items[i]),
      ),
    );
  }
}

class BookingForm extends StatefulWidget {
  final Rec worker;
  const BookingForm({super.key, required this.worker});
  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  final desc = TextEditingController();
  final addr = TextEditingController();
  int? cat;
  String? photo;
  String? when;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final sk = skillsOf(widget.worker);
    if (sk.isNotEmpty) cat = sk.first['id'] as int;
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 60)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() => when = '${two(d.day)}/${two(d.month)}/${d.year} ${two(t.hour)}:${two(t.minute)}');
  }

  Future<void> _submit() async {
    final st = context.read<AppState>();
    if (cat == null || desc.text.trim().isEmpty || addr.text.trim().isEmpty) {
      showMsg(context, trs('fill_all'));
      return;
    }
    if (st.lat == null) {
      showMsg(context, trs('need_location'));
      return;
    }
    final nav = Navigator.of(context);
    setState(() => busy = true);
    final id = await Db.createBooking(
      customerId: st.uid,
      workerId: widget.worker['id'] as int,
      categoryId: cat!,
      description: desc.text.trim(),
      photo: photo,
      address: addr.text.trim(),
      lat: st.lat!,
      lng: st.lng!,
      preferred: when,
    );
    nav.pushReplacement(MaterialPageRoute(builder: (_) => BookingDetail(id: id)));
  }

  @override
  Widget build(BuildContext context) {
    final sk = skillsOf(widget.worker);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'book_now'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${trs('worker')}: ${widget.worker['name']}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Text(trs('service')),
        Wrap(spacing: 8, children: [
          for (final c in sk)
            ChoiceChip(
              label: Text(catLabel(c)),
              selected: cat == c['id'],
              onSelected: (_) => setState(() => cat = c['id'] as int),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: desc,
            maxLines: 3,
            decoration: InputDecoration(labelText: trs('problem_desc'))),
        const SizedBox(height: 12),
        TextField(
            controller: addr,
            maxLines: 2,
            decoration: InputDecoration(labelText: trs('job_address'), hintText: trs('address_hint'))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule),
          label: Text(when ?? trs('preferred_time')),
        ),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              final p = await pickImage(context);
              if (p != null) setState(() => photo = p);
            },
            icon: const Icon(Icons.add_a_photo),
            label: Text(trs('add_photo')),
          ),
          const SizedBox(width: 12),
          if (photo != null) fileImg(photo, w: 60, h: 60),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton(
              onPressed: busy ? null : _submit, child: Text(trs('send_request'))),
        ),
      ]),
    );
  }
}

class UrgentScreen extends StatefulWidget {
  final int categoryId;
  const UrgentScreen({super.key, required this.categoryId});
  @override
  State<UrgentScreen> createState() => _UrgentScreenState();
}

class _UrgentScreenState extends State<UrgentScreen> {
  final desc = TextEditingController();
  final addr = TextEditingController();
  String? photo;
  bool busy = false;

  Future<void> _submit() async {
    final st = context.read<AppState>();
    if (desc.text.trim().isEmpty || addr.text.trim().isEmpty) {
      showMsg(context, trs('fill_all'));
      return;
    }
    if (st.lat == null) {
      showMsg(context, trs('need_location'));
      return;
    }
    final nav = Navigator.of(context);
    setState(() => busy = true);
    final id = await Db.createUrgent(
      customerId: st.uid,
      categoryId: widget.categoryId,
      description: desc.text.trim(),
      photo: photo,
      address: addr.text.trim(),
      lat: st.lat!,
      lng: st.lng!,
    );
    if (!mounted) return;
    if (id == null) {
      setState(() => busy = false);
      showMsg(context, trs('no_workers_urgent'));
      return;
    }
    nav.pushReplacement(MaterialPageRoute(builder: (_) => BookingDetail(id: id)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'urgent_request'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.red.withAlpha(25), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.flash_on, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(trs('urgent_info'))),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
            controller: desc,
            maxLines: 3,
            decoration: InputDecoration(labelText: trs('problem_desc'))),
        const SizedBox(height: 12),
        TextField(
            controller: addr,
            maxLines: 2,
            decoration: InputDecoration(labelText: trs('job_address'), hintText: trs('address_hint'))),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              final p = await pickImage(context);
              if (p != null) setState(() => photo = p);
            },
            icon: const Icon(Icons.add_a_photo),
            label: Text(trs('add_photo')),
          ),
          const SizedBox(width: 12),
          if (photo != null) fileImg(photo, w: 60, h: 60),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: busy ? null : _submit,
            icon: const Icon(Icons.flash_on),
            label: Text(trs('broadcast_now')),
          ),
        ),
      ]),
    );
  }
}

// ----------------------------------------------------------- booking detail
class BookingDetail extends StatefulWidget {
  final int id;
  const BookingDetail({super.key, required this.id});
  @override
  State<BookingDetail> createState() => _BookingDetailState();
}

class _BookingDetailState extends State<BookingDetail> {
  Rec? b;
  Timer? timer;
  bool busy = false;
  int rating = 5;
  final comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final role = context.read<AppState>().role;
    Rec? x = await Db.bookingById(widget.id);
    if (x == null || !mounted) return;
    if (role == 'customer' &&
        x['is_urgent'] == 1 &&
        x['worker_id'] == null &&
        x['status'] == 'requested') {
      final waited = (Db.now() - (x['created_at'] as int)) / 120000;
      if (waited >= (x['expanded'] as int) + 1) {
        await Db.expandUrgent(widget.id);
        x = await Db.bookingById(widget.id) ?? x;
      }
    }
    if (mounted) setState(() => b = x);
  }

  Future<void> _do(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showMsg(context, trs('error'));
    }
    if (mounted) setState(() => busy = false);
    await _load();
  }

  Widget _timeline(Rec b) {
    final st = b['status'] as String;
    if (st == 'cancelled' || st == 'rejected') {
      return Center(child: StatusChip(st));
    }
    final idx = statusFlow.indexOf(st);
    final col = Theme.of(context).colorScheme.primary;
    return Row(children: [
      for (var i = 0; i < statusFlow.length; i++)
        Expanded(
          child: Column(children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: i <= idx ? col : Colors.grey.shade300,
              child: Icon(i <= idx ? Icons.check : Icons.circle_outlined,
                  size: 14, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(trs('st_${statusFlow[i]}'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
          ]),
        ),
    ]);
  }

  List<Widget> _workerActions(Rec b, int uid) {
    final st = b['status'] as String;
    final qs = b['quote_status'] as String? ?? 'none';
    final out = <Widget>[];
    if (st == 'requested') {
      out.add(Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () => _do(() async {
                      final ok = await Db.acceptBooking(widget.id, uid);
                      if (!ok && mounted) showMsg(context, trs('job_taken'));
                    }),
            icon: const Icon(Icons.check),
            label: Text(trs('accept')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => _do(() => Db.rejectBooking(widget.id, uid)),
            icon: const Icon(Icons.close),
            label: Text(trs('reject')),
          ),
        ),
      ]));
    }
    if (st == 'accepted' || st == 'on_the_way' || st == 'in_progress') {
      if (qs == 'none' || qs == 'declined') {
        out.add(OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final v = await askText(context, trs('send_quote'), number: true);
                  final amt = double.tryParse(v ?? '');
                  if (amt == null || amt <= 0) return;
                  await _do(() => Db.sendQuote(widget.id, amt));
                },
          icon: const Icon(Icons.request_quote),
          label: Text(trs('send_quote')),
        ));
        out.add(const SizedBox(height: 8));
      }
      if (st == 'accepted') {
        out.add(FilledButton(
            onPressed: busy ? null : () => _do(() => Db.setStatus(widget.id, 'on_the_way', uid)),
            child: Text(trs('mark_on_the_way'))));
      } else if (st == 'on_the_way') {
        out.add(FilledButton(
            onPressed: busy ? null : () => _do(() => Db.setStatus(widget.id, 'in_progress', uid)),
            child: Text(trs('mark_in_progress'))));
      } else {
        out.add(FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (await confirm(context, trs('confirm_complete'))) {
                      await _do(() => Db.setStatus(widget.id, 'completed', uid));
                    }
                  },
            child: Text(trs('mark_completed'))));
      }
      if (st == 'accepted') {
        out.add(TextButton(
            onPressed: busy ? null : () => _cancel(uid),
            child: Text(trs('cancel_booking'), style: const TextStyle(color: Colors.red))));
      }
      out.add(const SizedBox(height: 4));
      out.add(OutlinedButton.icon(
        onPressed: () => openNav(numOf(b['lat']), numOf(b['lng'])),
        icon: const Icon(Icons.navigation),
        label: Text(trs('navigate')),
      ));
    }
    return out;
  }

  Future<void> _cancel(int uid) async {
    if (await confirm(context, trs('confirm_cancel'))) {
      await _do(() => Db.setStatus(widget.id, 'cancelled', uid));
    }
  }

  List<Widget> _customerActions(Rec b, int uid) {
    final st = b['status'] as String;
    final qs = b['quote_status'] as String? ?? 'none';
    final out = <Widget>[];
    if (qs == 'sent' && st != 'completed' && st != 'cancelled') {
      out.add(Row(children: [
        Expanded(
          child: FilledButton(
              onPressed: busy ? null : () => _do(() => Db.respondQuote(widget.id, true)),
              child: Text(trs('accept_quote'))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
              onPressed: busy ? null : () => _do(() => Db.respondQuote(widget.id, false)),
              child: Text(trs('decline_quote'))),
        ),
      ]));
      out.add(const SizedBox(height: 8));
    }
    if (st == 'rejected') {
      out.add(FilledButton.icon(
        onPressed: busy
            ? null
            : () => _do(() async {
                  final n = await Db.nextNearestFor(widget.id);
                  if (n == null) {
                    if (mounted) showMsg(context, trs('no_more_workers'));
                    return;
                  }
                  await Db.reassign(widget.id, n['id'] as int);
                  if (mounted) showMsg(context, '${trs('sent_to')} ${n['name']}');
                }),
        icon: const Icon(Icons.near_me),
        label: Text(trs('next_nearest')),
      ));
    }
    if (b['is_urgent'] == 1 && b['worker_id'] == null && st == 'requested') {
      out.add(OutlinedButton.icon(
        onPressed: busy
            ? null
            : () => _do(() async {
                  final n = await Db.expandUrgent(widget.id);
                  if (mounted) showMsg(context, n == 0 ? trs('no_more_workers') : '${trs('notified_more')} $n');
                }),
        icon: const Icon(Icons.campaign),
        label: Text(trs('notify_more')),
      ));
    }
    if (st == 'requested' || st == 'accepted' || st == 'rejected') {
      out.add(TextButton(
          onPressed: busy ? null : () => _cancel(uid),
          child: Text(trs('cancel_booking'), style: const TextStyle(color: Colors.red))));
    }
    if (st == 'completed') {
      if (b['review_rating'] == null) {
        out.add(Section(title: trs('rate_worker'), children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => rating = i),
                icon: Icon(i <= rating ? Icons.star : Icons.star_border,
                    color: Colors.amber.shade700, size: 34),
              ),
          ]),
          TextField(
              controller: comment,
              maxLines: 3,
              decoration: InputDecoration(labelText: trs('write_review'))),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: busy
                ? null
                : () => _do(() async {
                      await Db.addReview(widget.id, rating, comment.text.trim());
                      if (mounted) showMsg(context, trs('review_saved'));
                    }),
            child: Text(trs('submit_review')),
          ),
        ]));
      } else {
        out.add(Section(title: trs('your_review'), children: [
          Stars((b['review_rating'] as num).toDouble(), size: 22),
          if (((b['review_comment'] as String?) ?? '').isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(b['review_comment'] as String)),
        ]));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final bk = b;
    if (bk == null) {
      return Scaffold(
          appBar: AppBar(title: Text(trs('booking'))),
          body: const Center(child: CircularProgressIndicator()));
    }
    final isWorker = st.role == 'worker';
    final otherId = isWorker ? bk['customer_id'] as int : bk['worker_id'] as int?;
    final otherName = isWorker ? (bk['cust_name'] as String? ?? '') : (bk['worker_name'] as String?);
    final otherPhone = isWorker ? bk['cust_phone'] as String? : bk['worker_phone'] as String?;
    final quote = bk['quote'];
    return Scaffold(
      appBar: AppBar(title: Text('${trs('booking')} #${bk['id']}')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Section(children: [_timeline(bk)]),
        if (bk['is_urgent'] == 1)
          Section(children: [
            Row(children: [
              const Icon(Icons.flash_on, color: Colors.red),
              const SizedBox(width: 6),
              Text(trs('urgent_request'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (bk['worker_id'] == null && bk['status'] == 'requested')
                Text('${bk['target_count']} ${trs('workers_notified')}'),
            ]),
          ]),
        Section(title: trs('job_details'), children: [
          kv(trs('service'), bookingCat(bk)),
          kv(trs('problem_desc'), (bk['description'] as String?) ?? ''),
          kv(trs('job_address'), (bk['address'] as String?) ?? ''),
          if (bk['preferred_time'] != null) kv(trs('preferred_time'), bk['preferred_time'] as String),
          kv(trs('created'), fmtTime(bk['created_at'] as int?)),
          if (bk['photo'] != null && (bk['photo'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: fileImg(bk['photo'] as String?, w: double.infinity, h: 180)),
            ),
        ]),
        if (quote != null)
          Section(title: trs('quote'), children: [
            Text('Rs ${numOf(quote).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(trs('quote_${bk['quote_status']}')),
          ]),
        if (otherName != null && otherId != null)
          Section(title: isWorker ? trs('customer') : trs('worker'), children: [
            Text(otherName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (otherPhone != null) Text(otherPhone),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (otherPhone != null)
                OutlinedButton.icon(
                    onPressed: () => callPhone(otherPhone),
                    icon: const Icon(Icons.call),
                    label: Text(trs('call'))),
              if (otherPhone != null)
                OutlinedButton.icon(
                    onPressed: () => openWhatsApp(otherPhone),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp')),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(otherId: otherId, otherName: otherName))),
                  icon: const Icon(Icons.message),
                  label: Text(trs('chat'))),
            ]),
          ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isWorker ? _workerActions(bk, st.uid) : _customerActions(bk, st.uid),
          ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------------- chat
class ChatScreen extends StatefulWidget {
  final int otherId;
  final String otherName;
  const ChatScreen({super.key, required this.otherId, required this.otherName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Rec> msgs = [];
  final ctrl = TextEditingController();
  Timer? t;

  @override
  void initState() {
    super.initState();
    _load();
    t = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    t?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Db.thread(context.read<AppState>().uid, widget.otherId);
    if (mounted && l.length != msgs.length) setState(() => msgs = l);
  }

  Future<void> _send() async {
    final txt = ctrl.text.trim();
    if (txt.isEmpty) return;
    ctrl.clear();
    await Db.sendMessage(context.read<AppState>().uid, widget.otherId, txt);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AppState>().uid;
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherName)),
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? emptyState(trs('no_messages'), icon: Icons.chat_bubble_outline)
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: msgs.length,
                  itemBuilder: (c, i) {
                    final m = msgs[msgs.length - 1 - i];
                    final mine = m['sender_id'] == uid;
                    return Align(
                      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m['text'] as String),
                          Text(fmtTime(m['created_at'] as int?),
                              style: const TextStyle(fontSize: 10, color: Colors.black45)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(hintText: trs('type_message')),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
