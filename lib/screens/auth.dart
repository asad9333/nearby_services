import '../common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final id = TextEditingController();
  final pw = TextEditingController();
  bool busy = false;
  bool hide = true;

  Future<void> _login() async {
    if (id.text.trim().isEmpty || pw.text.isEmpty) {
      showMsg(context, trs('fill_all'));
      return;
    }
    final st = context.read<AppState>();
    setState(() => busy = true);
    final u = await Db.login(id.text.trim(), pw.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (u == null) {
      showMsg(context, trs('err_login'));
      return;
    }
    if (u['status'] != 'active') {
      showMsg(context, trs('err_suspended'));
      return;
    }
    await st.setUser(u);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => st.setLang(st.lang == 'en' ? 'ur' : 'en'),
                  child: Text(st.lang == 'en' ? 'اردو' : 'English'),
                ),
              ),
              Icon(Icons.handyman, size: 72, color: cs.primary),
              const SizedBox(height: 8),
              Text(trs('app_name'),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(trs('tagline'), style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 28),
              TextField(
                controller: id,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: trs('phone_or_email'), prefixIcon: const Icon(Icons.person)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw,
                obscureText: hide,
                decoration: InputDecoration(
                  labelText: trs('password'),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => hide = !hide),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : _login,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(trs('login')),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: Text(trs('create_account')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final pw = TextEditingController();
  final pw2 = TextEditingController();
  String role = 'customer';
  bool busy = false;

  Future<void> _register() async {
    final ph = Db.normPhone(phone.text);
    if (name.text.trim().isEmpty || ph.isEmpty || pw.text.isEmpty) {
      showMsg(context, trs('fill_all'));
      return;
    }
    if (ph.length < 10 || ph.length > 13) {
      showMsg(context, trs('err_phone'));
      return;
    }
    if (pw.text.length < 6) {
      showMsg(context, trs('err_pw_short'));
      return;
    }
    if (pw.text != pw2.text) {
      showMsg(context, trs('err_pw_match'));
      return;
    }
    final st = context.read<AppState>();
    final nav = Navigator.of(context);
    setState(() => busy = true);
    try {
      final u = await Db.register(
          name: name.text,
          phone: phone.text,
          email: email.text,
          password: pw.text,
          role: role);
      nav.popUntil((r) => r.isFirst);
      await st.setUser(u);
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showMsg(context, trs(e is String ? e : 'error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'create_account'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr(context, 'i_am'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: 'customer',
                label: Text(trs('role_customer')),
                icon: const Icon(Icons.person)),
            ButtonSegment(
                value: 'worker',
                label: Text(trs('role_worker')),
                icon: const Icon(Icons.engineering)),
          ],
          selected: {role},
          onSelectionChanged: (s) => setState(() => role = s.first),
        ),
        const SizedBox(height: 16),
        TextField(controller: name, decoration: InputDecoration(labelText: trs('full_name'))),
        const SizedBox(height: 12),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: trs('phone'), hintText: '03XXXXXXXXX')),
        const SizedBox(height: 12),
        TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: trs('email_optional'))),
        const SizedBox(height: 12),
        TextField(
            controller: pw,
            obscureText: true,
            decoration: InputDecoration(labelText: trs('password'))),
        const SizedBox(height: 12),
        TextField(
            controller: pw2,
            obscureText: true,
            decoration: InputDecoration(labelText: trs('confirm_password'))),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : _register,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(trs('register')),
          ),
        ),
      ]),
    );
  }
}
