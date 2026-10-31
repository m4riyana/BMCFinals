import 'dart:async';
import 'branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'services/payment_service.dart';
import 'services/auth_service.dart';
import 'commerce/storefront.dart';
import 'commerce/commerce_store.dart';
import 'commerce/commerce_api.dart';
import 'commerce/store_widgets.dart' show ProductPhoto, pesos;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  runApp(const IbashoApp());
}

class Product {
  final int id;
  final String name;
  final String category;
  final double price;
  final String emoji;
  const Product(this.id, this.name, this.category, this.price, this.emoji);
}

const products = <Product>[
  Product(1, 'Spiral Notebook', 'Notebooks', 65, '📓'),
  Product(2, 'Ballpoint Pens (5 pcs)', 'Writing', 45, '🖊️'),
  Product(3, 'Pencil Set', 'Writing', 35, '✏️'),
  Product(4, 'Coloring Materials', 'Art', 120, '🎨'),
  Product(5, 'Ruler', 'Essentials', 20, '📏'),
  Product(6, 'School Backpack', 'Essentials', 450, '🎒'),
  Product(7, 'Writing Pad', 'Notebooks', 55, '📄'),
  Product(8, 'Scissors', 'Essentials', 40, '✂️'),
];

class IbashoApp extends StatelessWidget {
  const IbashoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IBASHO STATIONERY',
      debugShowCheckedModeBanner: false,
      theme: ibashoTheme(),
      home: const AuthGate(),
    );
  }
}

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final Map<int, int> cart = {};
  String category = 'All';
  String search = '';
  int page = 0;

  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  double get total =>
      products.fold(0, (sum, p) => sum + p.price * (cart[p.id] ?? 0));

  void add(Product product) {
    setState(() => cart[product.id] = (cart[product.id] ?? 0) + 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('${product.name} added to cart'),
          duration: const Duration(seconds: 1)),
    );
  }

  void changeQuantity(Product product, int difference) {
    setState(() {
      final quantity = (cart[product.id] ?? 0) + difference;
      if (quantity <= 0) {
        cart.remove(product.id);
      } else {
        cart[product.id] = quantity;
      }
    });
  }

  void showProduct(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Text(product.emoji,
                      style: const TextStyle(fontSize: 96))),
              const SizedBox(height: 12),
              Text(product.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(product.category),
              const SizedBox(height: 8),
              Text('₱${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      add(product);
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Add to Cart'),
                  )),
              const SizedBox(height: 16),
            ]),
      ),
    );
  }

  Future<void> checkout() async {
    if (cart.isEmpty) return;
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final contactController = TextEditingController();
    final checkoutFormKey = GlobalKey<FormState>();
    bool saving = false;
    String? saveError;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: const Text('Checkout'),
            content: SingleChildScrollView(
              child: Form(
                key: checkoutFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total: ₱${total.toStringAsFixed(2)}'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter your full name'
                          : null,
                    ),
                    TextFormField(
                      controller: contactController,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Contact Number'),
                      validator: (value) =>
                          RegExp(r'^09\d{9}$').hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter an 11-digit number starting with 09',
                    ),
                    TextFormField(
                      controller: addressController,
                      minLines: 1,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(labelText: 'Delivery Address'),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter your delivery address'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                        'You will be redirected to Xendit Test Checkout. Your order is not paid until payment is verified.',
                        style: TextStyle(fontSize: 12)),
                    if (saveError != null) ...[
                      const SizedBox(height: 10),
                      Text(saveError!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!checkoutFormKey.currentState!.validate()) return;
                        updateDialog(() {
                          saving = true;
                          saveError = null;
                        });
                        try {
                          final payment = await PaymentService().createPayment(
                            customerName: nameController.text.trim(),
                            contactNumber: contactController.text.trim(),
                            address: addressController.text.trim(),
                            items: [
                              for (final product in products
                                  .where((p) => cart.containsKey(p.id)))
                                {
                                  'productId': product.id,
                                  'quantity': cart[product.id]!
                                },
                            ],
                          );
                          await PaymentService()
                              .openPayment(payment.paymentUrl);
                          if (!dialogContext.mounted || !mounted) return;
                          Navigator.pop(dialogContext);
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xendit Checkout Opened'),
                              content: Text(
                                  'Complete your test payment in the browser.\n\nReference: ${payment.referenceId}\n\nYour order will not be marked paid until the backend verifies payment.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('OK'))
                              ],
                            ),
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          updateDialog(() {
                            saving = false;
                            saveError = 'Could not open payment: $e';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Pay with Xendit'),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameController.dispose();
      contactController.dispose();
      addressController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = products
        .where((p) =>
            (category == 'All' || p.category == category) &&
            p.name.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const BrandLogo(), actions: [
        IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await AuthService().logout();
              if (context.mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.logout)),
        IconButton(
            onPressed: () => setState(() => page = 1),
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            )),
      ]),
      body: page == 0
          ? Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    onChanged: (value) => setState(() => search = value),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search school supplies',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16))),
                  )),
              SizedBox(
                  height: 48,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final c in [
                          'All',
                          'Notebooks',
                          'Writing',
                          'Art',
                          'Essentials'
                        ])
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(c),
                                selected: category == c,
                                onSelected: (_) => setState(() => category = c),
                              )),
                      ])),
              const SizedBox(height: 12),
              Expanded(
                  child: GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .73,
                ),
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  return Card(
                      clipBehavior: Clip.antiAlias,
                      color: Colors.white,
                      child: InkWell(
                        onTap: () => showProduct(p),
                        child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: Center(
                                        child: Text(p.emoji,
                                            style: const TextStyle(
                                                fontSize: 62)))),
                                Text(p.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text('₱${p.price.toStringAsFixed(2)}'),
                                const SizedBox(height: 6),
                                SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () => add(p),
                                      child: const Text('Add to Cart'),
                                    )),
                              ],
                            )),
                      ));
                },
              )),
            ])
          : Column(children: [
              Expanded(
                  child: cart.isEmpty
                      ? const Center(child: Text('Your cart is empty'))
                      : ListView(
                          children: [
                            for (final p in products
                                .where((p) => cart.containsKey(p.id)))
                              Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  child: ListTile(
                                    leading: Text(p.emoji,
                                        style: const TextStyle(fontSize: 34)),
                                    title: Text(p.name),
                                    subtitle: Text(
                                        '₱${p.price.toStringAsFixed(2)} each'),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                              onPressed: () =>
                                                  changeQuantity(p, -1),
                                              icon: const Icon(
                                                  Icons.remove_circle_outline)),
                                          Text('${cart[p.id]}'),
                                          IconButton(
                                              onPressed: () =>
                                                  changeQuantity(p, 1),
                                              icon: const Icon(
                                                  Icons.add_circle_outline)),
                                        ]),
                                  )),
                          ],
                        )),
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Text('Total: ₱${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: cart.isEmpty ? null : checkout,
                          child: const Text('Checkout'),
                        )),
                  ])),
            ]),
      bottomNavigationBar: NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (value) => setState(() => page = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.storefront_outlined), label: 'Shop'),
            NavigationDestination(
                icon: Icon(Icons.shopping_cart_outlined), label: 'Cart'),
          ]),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth;
  late final Stream<User?> _authChanges;

  @override
  void initState() {
    super.initState();
    _auth = AuthService();
    _authChanges = _auth.authStateChanges.distinct(
      (previous, next) => previous?.id == next?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authChanges,
      initialData: _auth.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Text('Authentication error: ${snapshot.error}')));
        }
        return snapshot.data == null ? const AuthPage() : const DashboardPage();
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _signup = false;
  bool _hidden = true;
  bool _busy = false;
  int _retrySeconds = 0;
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // Supabase sign-up may return no session until email confirmation. Persist
  // the chosen username once the user has an authenticated session instead.
  Future<void> _completePendingProfile() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    final username = user.userMetadata?['username'];
    if (username is! String ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9._-]{2,23}$').hasMatch(username)) return;
    try {
      final response = await CommerceApi().profile();
      final existing = response['profile'];
      // Never overwrite an existing completed profile.
      if (existing is Map && (existing['username']?.toString() ?? '').isNotEmpty) return;
      await CommerceApi().saveProfile(
        username: username,
        name: username,
        contactEmail: user.email ?? '',
        phoneNumber: '',
        address: '',
      );
    } catch (_) {
      // An unavailable profile backend must not invalidate a valid login.
      // The user can complete their profile from the account page later.
    }
  }

  Future<void> _resendConfirmation() async {
    if (_busy || _retrySeconds > 0) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter your registered email address first.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService().resendConfirmation(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('If your email is awaiting confirmation, check your inbox and Spam for the new link.')));
      _beginCooldown(60);
    } on AuthException catch (error) {
      if (!mounted) return;
      final match = RegExp(r'(\d+) seconds').firstMatch(error.message);
      if (error.statusCode == '429' || match != null) {
        _beginCooldown(int.tryParse(match?.group(1) ?? '') ?? 60);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error.statusCode == '429' ? 'Email sending is rate-limited. Try again later, or open the confirmation email already sent.' : error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _beginCooldown(int seconds) {
    _retryTimer?.cancel();
    setState(() => _retrySeconds = seconds);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _retrySeconds--);
      if (_retrySeconds <= 0) timer.cancel();
    });
  }

  Future<void> _submit() async {
    if (_retrySeconds > 0 || _busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_signup) {
        final credential =
            await AuthService().signUp(_email.text, _password.text, _username.text);
        if (credential.session == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Account submitted. Check your inbox (and Spam) for the confirmation link. If you need another link, use Resend confirmation on the login screen.'),
          ));
          mode(false, false);
          return;
        }
        final username = _username.text.trim();
        try {
          await CommerceApi().saveProfile(
            username: username,
            name: username,
            contactEmail: _email.text.trim(),
            phoneNumber: '',
            address: '',
          );
        } on CommerceException catch (error) {
          if (error.statusCode == 409) {
            // Account remains registered; profile conflict must be resolved by the user.
            rethrow;
          }
          throw CommerceException(
            'Your account was created, but your profile could not be saved. Sign in and try again. ${error.message}',
            error.statusCode,
          );
        }
      } else {
        final identifier = _email.text.trim();
        if (identifier.contains('@')) {
          await AuthService().login(identifier, _password.text);
        } else {
          final result = await CommerceApi().loginWithUsername(
            identifier,
            _password.text,
          );
          await AuthService().login('${result['email']}', _password.text);
        }
        await _completePendingProfile();
      }
    } on CommerceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } on AuthException catch (e) {
      if (!mounted) return;
      final limited = e.statusCode == '429' ||
          e.message.toLowerCase().contains('you can only request this after');
      if (limited) {
        final seconds = RegExp(r'(\d+) seconds').firstMatch(e.message);
        _beginCooldown(int.tryParse(seconds?.group(1) ?? '') ?? 60);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        limited ? 'Please wait $_retrySeconds seconds before trying again. If you already registered, check your email for the confirmation link.' : e.message,
      )));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _recovery = false;
  bool _sent = false;
  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService().resetPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to send the reset link. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void mode(bool signup, bool recovery) => setState(() {
        if (_signup != signup || _recovery != recovery) {
          _retryTimer?.cancel();
          _retrySeconds = 0;
        }
        _signup = signup;
        _recovery = recovery;
        _sent = false;
        _formKey.currentState?.reset();
      });
  @override
  Widget build(BuildContext context) => AuthLayout(
        recovery: _recovery,
        chapter: _recovery
            ? 'CHAPTER 03 • ACCOUNT RECOVERY'
            : _signup
                ? 'CHAPTER 02 • A NEW BEGINNING'
                : 'CHAPTER 01 • WELCOME BACK',
        form: Form(
            key: _formKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      _recovery
                          ? 'FORGOT PASSWORD?'
                          : _signup
                              ? 'YOUR STORY STARTS HERE'
                              : 'WELCOME BACK, CREATOR!',
                      style: const TextStyle(
                          fontSize: 10, letterSpacing: 2, color: red)),
                  const SizedBox(height: 16),
                  Text(
                      _recovery
                          ? "Let's find your\nway back."
                          : _signup
                              ? 'Make space for\nsomething new.'
                              : 'Find your way\nback to',
                      style: serif.copyWith(fontSize: 46)),
                  if (!_recovery && !_signup)
                    Text('IBASHO.', style: hand.copyWith(fontSize: 46)),
                  const SizedBox(height: 18),
                  Text(
                      _recovery
                          ? 'Enter your email to receive a password reset link.'
                          : 'Your favorite tools. A fresh page. Endless possibilities.',
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 13, height: 1.6)),
                  const SizedBox(height: 30),
                  if (_signup) ...[
                    const Text('Username',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _username,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        prefixIcon:
                            Icon(Icons.person_outline, color: red, size: 18),
                        hintText: 'Choose a username',
                      ),
                      validator: (value) => RegExp(
                                  r'^[A-Za-z][A-Za-z0-9._-]{2,23}$')
                              .hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Use 3–24 letters, numbers, periods, underscores, or hyphens',
                    ),
                    const SizedBox(height: 18),
                  ],
                  Text(
                      _signup || _recovery
                          ? 'Email address'
                          : 'Username or email address',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: _signup || _recovery
                          ? const [AutofillHints.email]
                          : const [AutofillHints.username, AutofillHints.email],
                      decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.alternate_email,
                              color: red, size: 18),
                          hintText: _signup || _recovery
                              ? 'Enter your email address'
                              : 'Enter your username or email'),
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        if (_signup || _recovery || input.contains('@')) {
                          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(input)
                              ? null
                              : 'Enter a valid email address';
                        }
                        return RegExp(r'^[A-Za-z][A-Za-z0-9._-]{2,23}$')
                                .hasMatch(input)
                            ? null
                            : 'Enter your username or a valid email address';
                      }),
                  if (!_recovery) ...[
                    const SizedBox(height: 18),
                    const Text('Password',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                        controller: _password,
                        obscureText: _hidden,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.key_outlined,
                                color: red, size: 18),
                            hintText: 'Enter your password',
                            suffixIcon: TextButton(
                                onPressed: () =>
                                    setState(() => _hidden = !_hidden),
                                child: Text(_hidden ? 'SHOW' : 'HIDE',
                                    style: const TextStyle(fontSize: 9)))),
                        validator: (v) => (v?.length ?? 0) < 6
                            ? 'Use at least 6 characters'
                            : null),
                    if (_signup) ...[
                      const SizedBox(height: 18),
                      TextFormField(
                          controller: _confirm,
                          obscureText: _hidden,
                          decoration: const InputDecoration(
                              labelText: 'Confirm password'),
                          validator: (v) => v != _password.text
                              ? 'Passwords do not match'
                              : null)
                    ],
                    if (!_signup)
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: _busy ? null : () => mode(false, true),
                              child: const Text('Forgot Password?',
                                  style: TextStyle(color: red, fontSize: 12)))),
                  ],
                  if (!_signup && !_recovery)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy || _retrySeconds > 0 ? null : _resendConfirmation,
                        child: Text(
                          _retrySeconds > 0
                              ? 'Resend available in $_retrySeconds s'
                              : 'Did not receive confirmation email? Resend',
                          style: const TextStyle(color: red, fontSize: 12),
                        ),
                      ),
                    ),
                  if (_sent)
                    const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Text(
                            'Check your inbox for your password reset link.',
                            style: TextStyle(color: red))),
                  const SizedBox(height: 28),
                  Container(
                      decoration: const BoxDecoration(boxShadow: [
                        BoxShadow(color: red, offset: Offset(4, 4))
                      ]),
                      child: FilledButton(
                          onPressed: _busy || _retrySeconds > 0
                              ? null
                              : _recovery
                                  ? _reset
                                  : _submit,
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    _retrySeconds > 0
                                        ? 'TRY AGAIN IN $_retrySeconds s'
                                        : _busy
                                        ? 'PLEASE WAIT...'
                                        : _recovery
                                            ? 'SEND RESET LINK'
                                            : _signup
                                                ? 'CREATE ACCOUNT'
                                                : 'LOGIN',
                                    style: const TextStyle(
                                        fontSize: 11, letterSpacing: 1.5)),
                                const Icon(Icons.arrow_forward, size: 19)
                              ]))),
                  const SizedBox(height: 24),
                  const Divider(),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => mode(!_signup && !_recovery, false),
                      child: Text(
                          _recovery || _signup
                              ? 'Back to Login'
                              : 'New to the studio? Create an account',
                          style: const TextStyle(color: red, fontSize: 12))),
                  const Text('Your Space. Your Tools. Your Story.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.black45)),
                ])),
      );
}

class DashboardPage extends StatefulWidget {
  final CommerceStore? store;
  const DashboardPage({super.key, this.store});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final CommerceStore store;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? CommerceStore();
    store.load();
  }

  @override
  void dispose() {
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store, builder: (context, _) => dashboard(context));

  Widget dashboard(BuildContext context) {
    void shop(
            {StoreSection section = StoreSection.shop,
            bool showCart = false}) =>
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Storefront(
            store: store,
            initialSection: section,
            showCartOnOpen: showCart,
            onLogin: (loginContext) async {
              await Navigator.of(loginContext).push<void>(
                MaterialPageRoute<void>(builder: (_) => const AuthPage()),
              );
            },
          ),
        ));
    final email = store.userEmail ?? 'Creator';
    final name =
        email.split('@').first.isEmpty ? 'Creator' : email.split('@').first;
    final essentials =
        store.products.where((product) => product.inStock).take(3).toList();
    final cards = <Widget>[
      Panel(
          color: ink,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('01    THE STATIONERY COLLECTION',
                style: TextStyle(
                    color: Color(0xFFD59090), fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 20),
            Text('Your next great idea\nstarts here.',
                style: serif.copyWith(color: paper, fontSize: 30)),
            const SizedBox(height: 18),
            const Text(
                'Thoughtful tools for school, work, and everything you dream of.',
                style: TextStyle(color: paper, fontSize: 12, height: 1.7)),
            const SizedBox(height: 20),
            OutlinedButton(
                onPressed: () => shop(),
                style: OutlinedButton.styleFrom(
                    foregroundColor: paper,
                    side: const BorderSide(color: paper)),
                child: const Text('EXPLORE SUPPLIES →'))
          ])),
      Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('02    YOUR ESSENTIALS',
            style: TextStyle(color: red, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 18),
        if (essentials.isEmpty)
          const SizedBox(
              height: 72,
              child: Center(
                  child: Icon(Icons.menu_book_outlined, size: 58, color: red)))
        else
          SizedBox(
              height: 72,
              child: Row(children: [
                for (var i = 0; i < essentials.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                      child: Tooltip(
                          message: essentials[i].name,
                          child: InkWell(
                            onTap: () => shop(),
                            child: ProductPhoto(essentials[i].imagePath,
                                label: essentials[i].name, padding: 4),
                          ))),
                ],
              ])),
        const SizedBox(height: 16),
        const Text('A fresh page for every possibility.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        if (store.products.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
              '${store.products.length} essentials · from ${pesos(store.products.map((p) => p.price).reduce((a, b) => a < b ? a : b))}',
              style: const TextStyle(fontSize: 10, color: red)),
        ],
        TextButton(
            onPressed: () => shop(), child: const Text('FIND YOUR TOOLS →'))
      ])),
      Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('03    YOUR PROFILE',
            style: TextStyle(color: red, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 24),
        CircleAvatar(
            radius: 35,
            backgroundColor: red,
            child: Text(name.substring(0, 1).toUpperCase(),
                style: serif.copyWith(color: paper, fontSize: 32))),
        const SizedBox(height: 24),
        const Text('Your own little space.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Text(email,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        Wrap(spacing: 4, children: [
          TextButton(
              onPressed: () => shop(section: StoreSection.orders),
              child: const Text('My orders',
                  style: TextStyle(fontSize: 11, color: red))),
          TextButton(
              onPressed: () => shop(section: StoreSection.wishlist),
              child: Text('Wishlist (${store.wishlist.length})',
                  style: const TextStyle(fontSize: 11, color: red))),
        ]),
      ])),
    ];
    return Scaffold(
      appBar: AppBar(
          toolbarHeight: 90,
          title: const FittedBox(fit: BoxFit.scaleDown, child: BrandLogo()),
          bottom: const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: Divider(height: 2, thickness: 2, color: ink)),
          actions: [
            IconButton(
                tooltip: 'Shopping cart',
                onPressed: () => shop(showCart: true),
                icon: Badge(
                    isLabelVisible: store.cartCount > 0,
                    label: Text('${store.cartCount}'),
                    backgroundColor: red,
                    child: const Icon(Icons.shopping_bag_outlined))),
            TextButton(
                onPressed: () => AuthService().logout(),
                child: const Text('LOGOUT →')),
            const SizedBox(width: 24)
          ]),
      body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 600 ? 20 : 28,
              vertical: 40),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: Column(children: [
                    Panel(
                        color: beige,
                        padding: const EdgeInsets.all(40),
                        child: LayoutBuilder(
                            builder: (context, c) => Row(children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        const Text('CHAPTER 04 • YOUR IBASHO',
                                            style: TextStyle(
                                                color: red,
                                                fontSize: 10,
                                                letterSpacing: 2)),
                                        const SizedBox(height: 16),
                                        Text('Welcome back,',
                                            style: serif.copyWith(
                                                fontSize: c.maxWidth < 600
                                                    ? 36
                                                    : 58)),
                                        Text('$name.',
                                            style: hand.copyWith(
                                                fontSize: c.maxWidth < 600
                                                    ? 32
                                                    : 50)),
                                        const SizedBox(height: 20),
                                        const Text(
                                            'This is your quiet corner to create. Find the tools for your next great idea.',
                                            style: TextStyle(
                                                fontSize: 13, height: 1.6))
                                      ])),
                                  if (c.maxWidth > 650) ...[
                                    const SizedBox(width: 25),
                                    const Speech(
                                        'A place where\nyour ideas belong.')
                                  ]
                                ]))),
                    const SizedBox(height: 30),
                    LayoutBuilder(
                        builder: (context, c) => c.maxWidth < 800
                            ? Column(children: [
                                for (final card in cards)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 24),
                                      child: SizedBox(
                                          width: double.infinity, child: card))
                              ])
                            : IntrinsicHeight(
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                    Expanded(flex: 5, child: cards[0]),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 3, child: cards[1]),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 3, child: cards[2])
                                  ]))),
                    const SizedBox(height: 54),
                    const Text('Your Space. Your Tools. Your Story.',
                        style: TextStyle(
                            color: red, letterSpacing: 2, fontSize: 11)),
                  ])))),
    );
  }
}

ThemeData ibashoTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: red),
      scaffoldBackgroundColor: cream,
      appBarTheme:
          const AppBarTheme(centerTitle: false, backgroundColor: paper),
      fontFamily: 'Lato',
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: paper,
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.all(22))),
      inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFFAF8F0),
          border: OutlineInputBorder(borderRadius: BorderRadius.zero)),
      cardTheme: const CardThemeData(
          color: paper,
          shape:
              RoundedRectangleBorder(side: BorderSide(color: ink, width: 2))),
    );
