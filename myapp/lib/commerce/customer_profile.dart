import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../branding.dart';
import 'commerce_api.dart';
import 'commerce_store.dart';
import 'models.dart';
import 'store_widgets.dart';

class CustomerProfileCard extends StatefulWidget {
  final CommerceStore store;
  const CustomerProfileCard({super.key, required this.store});

  @override
  State<CustomerProfileCard> createState() => _CustomerProfileCardState();
}

class _CustomerProfileCardState extends State<CustomerProfileCard> {
  bool busy = false;

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(value),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  String profileError(Object error) {
    if (error is CommerceException && error.statusCode == null) {
      return 'Profile service is unavailable at ${widget.store.api.baseUrl}. Start the backend and try saving again. Your edits are still here.';
    }
    if (error is CommerceException) return error.message;
    return 'Unable to update your profile. Please try again.';
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      message(profileError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Navigator.push completes when pop starts, before the exit animation ends.
  // Keep controllers and focus nodes alive until the route is fully removed.
  Future<T?> _showProfileDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    );
    final result = await navigator.push(route);
    await route.completed;
    return result;
  }

  Future<void> choosePhoto() => run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null || !mounted) return;
    final fileLength = await file.length();
    if (!mounted) return;
    if (fileLength == null || fileLength == 0 || fileLength > 5 * 1024 * 1024) {
      message('Choose a non-empty image smaller than 5 MB.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      message('Unable to read that image, or it exceeds 5 MB.');
      return;
    }
    bool saving = false;
    String? error;
    final saved = await _showProfileDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Preview profile picture'),
            content: SizedBox(
              width: 300,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipOval(child: Image.memory(bytes, width: 180, height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    width: 180, height: 180,
                    child: Center(child: Text('Unable to preview this image.')),
                  ),
                )),
                const SizedBox(height: 16),
                const Text('Your picture will be cropped to a square.'),
                if (saving) const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
                if (error != null) Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(error!, style: const TextStyle(color: red)),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: saving ? null : () async {
                  update(() { saving = true; error = null; });
                  try {
                    await widget.store.uploadProfilePhoto(bytes, file.name);
                    if (dialogContext.mounted) {
                      update(() => saving = false);
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (failure) {
                    if (dialogContext.mounted) {
                      update(() {
                        saving = false;
                        error = profileError(failure);
                      });
                    }
                  }
                },
                child: Text(saving ? 'SAVING...' : 'SAVE PHOTO'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) message('Profile picture saved.');
  });

  Future<void> editDetails(CustomerProfile profile) async {
    final username = TextEditingController(text: profile.username);
    final name = TextEditingController(text: profile.name);
    final contactEmail = TextEditingController(
        text: profile.contactEmail.isNotEmpty
            ? profile.contactEmail
            : profile.email);
    final phone = TextEditingController(text: profile.phoneNumber);
    final address = TextEditingController(text: profile.address);
    final usernameFocus = FocusNode();
    final nameFocus = FocusNode();
    final emailFocus = FocusNode();
    final phoneFocus = FocusNode();
    final addressFocus = FocusNode();
    final formKey = GlobalKey<FormState>();
    final saveQueue = <Future<void>>[Future<void>.value()];
    String lastSaved = '';
    String fingerprint() => [
          username.text.trim(),
          name.text.trim(),
          contactEmail.text.trim(),
          phone.text.trim(),
          address.text.trim(),
        ].join('\u0000');
    lastSaved = fingerprint();

    Future<bool> saveDetails() async {
      final completer = Completer<bool>();
      final previous = saveQueue.last;
      final next = previous.then((_) async {
        if (!mounted) {
          completer.complete(false);
          return;
        }
        if (!(formKey.currentState?.validate() ?? false)) {
          completer.complete(false);
          return;
        }
        final current = fingerprint();
        if (current == lastSaved) {
          completer.complete(true);
          return;
        }
        try {
          await widget.store.saveProfile(
            username: username.text.trim(),
            name: name.text.trim(),
            contactEmail: contactEmail.text.trim(),
            phoneNumber: phone.text.trim(),
            address: address.text.trim(),
          );
          lastSaved = current;
          message('Saved Successfully');
          completer.complete(true);
        } catch (error) {
          message(profileError(error));
          completer.complete(false);
        }
      });
      saveQueue.add(next);
      return completer.future;
    }

    final accepted = await _showProfileDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your profile'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: username,
                  focusNode: usernameFocus,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) => RegExp(
                              r'^[A-Za-z][A-Za-z0-9._-]{2,23}$')
                          .hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use 3–24 letters, numbers, periods, underscores, or hyphens',
                ),
                TextFormField(
                  controller: name,
                  focusNode: nameFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => (value?.trim().length ?? 0) >= 2
                      ? null
                      : 'Enter your name',
                ),
                TextFormField(
                  controller: contactEmail,
                  focusNode: emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Contact email'),
                  validator: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Enter a valid email address',
                ),
                TextFormField(
                  controller: phone,
                  focusNode: phoneFocus,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  validator: (value) => (value?.trim().isEmpty ?? true) ||
                          RegExp(r'^(09\d{9}|\+639\d{9})$')
                              .hasMatch(value!.trim())
                      ? null
                      : 'Use a valid Philippine mobile number',
                ),
                TextFormField(
                  controller: address,
                  focusNode: addressFocus,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration:
                      const InputDecoration(labelText: 'Complete address'),
                  validator: (value) => (value?.trim().isEmpty ?? true) ||
                          (value?.trim().length ?? 0) >= 10
                      ? null
                      : 'Enter a complete address',
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  if (await saveDetails() && dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                }
              },
              child: const Text('SAVE & DONE')),
        ],
      ),
    );
    if (accepted == true && mounted) setState(() {});
    await saveQueue.last;
    username.dispose();
    name.dispose();
    contactEmail.dispose();
    phone.dispose();
    address.dispose();
    usernameFocus.dispose();
    nameFocus.dispose();
    emailFocus.dispose();
    phoneFocus.dispose();
    addressFocus.dispose();
  }

  Future<String?> currentPasswordDialog(String title) async {
    final controller = TextEditingController();
    final password = await _showProfileDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('CONTINUE')),
        ],
      ),
    );
    controller.dispose();
    return password;
  }

  Future<void> changeEmail(CustomerProfile profile) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) {
      message('Sign in with email and password to change your email.');
      return;
    }
    final emailController = TextEditingController(text: profile.email);
    final password = await currentPasswordDialog('Verify your identity');
    if (password == null || password.isEmpty) {
      emailController.dispose();
      return;
    }
    if (!mounted) {
      emailController.dispose();
      return;
    }
    final newEmail = await _showProfileDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change email address'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'New email address'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, emailController.text.trim()),
              child: const Text('SEND VERIFICATION')),
        ],
      ),
    );
    emailController.dispose();
    if (newEmail == null || newEmail.isEmpty) return;
    await run(() async {
      final check = await Supabase.instance.client.auth.signInWithPassword(email: user.email!, password: password);
      if (check.user?.id != user.id) throw Exception('Identity verification failed');
      await Supabase.instance.client.auth.updateUser(UserAttributes(email: newEmail));
      message(
          'Check $newEmail for the Supabase email-change confirmation link.');
    });
  }

  Future<void> changePassword() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) {
      message('Sign in with email and password to change your password.');
      return;
    }
    final current = await currentPasswordDialog('Change password');
    if (current == null || current.isEmpty) return;
    if (!mounted) return;
    final next = TextEditingController();
    final confirm = TextEditingController();
    final accepted = await _showProfileDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final formKey = GlobalKey<FormState>();
        return AlertDialog(
          title: const Text('Choose a new password'),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (value) => (value?.length ?? 0) >= 6
                    ? null
                    : 'Use at least 6 characters',
              ),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm password'),
                validator: (value) =>
                    value == next.text ? null : 'Passwords do not match',
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCEL')),
            FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('UPDATE PASSWORD')),
          ],
        );
      },
    );
    if (accepted == true) {
      await run(() async {
        final check = await Supabase.instance.client.auth.signInWithPassword(email: user.email!, password: current);
        if (check.user?.id != user.id) throw Exception('Identity verification failed');
        await Supabase.instance.client.auth.updateUser(UserAttributes(password: next.text));
        message('Your password has been updated.');
      });
    }
    next.dispose();
    confirm.dispose();
  }

  Future<void> refreshEmail() async {
    await run(() async {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) await Supabase.instance.client.auth.refreshSession();
      await widget.store.refreshProfile();
      message('Account details refreshed.');
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final profile = widget.store.profile ?? const CustomerProfile();
          final photo = profile.profilePhotoPath;
          return Panel(
            color: paper,
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('Your account details'),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Stack(children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: beige,
                    backgroundImage: photo.isEmpty
                        ? null
                        : NetworkImage(widget.store.api.imageUrl(photo)),
                    child: photo.isEmpty
                        ? const Icon(Icons.person_outline, size: 34, color: ink)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: busy ? null : choosePhoto,
                      borderRadius: BorderRadius.circular(20),
                      child: const CircleAvatar(
                        radius: 13,
                        backgroundColor: red,
                        child: Icon(Icons.edit, size: 13, color: paper),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            profile.name.isEmpty
                                ? profile.username
                                : profile.name,
                            style: serif.copyWith(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text('@${profile.username} · ${profile.email}',
                            style: const TextStyle(color: muted, fontSize: 12)),
                        if (profile.phoneNumber.isNotEmpty ||
                            profile.address.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            [profile.phoneNumber, profile.address]
                                .where((value) => value.isNotEmpty)
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ]),
                ),
                if (busy)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 18),
              Wrap(spacing: 10, runSpacing: 8, children: [
                TextButton(
                    onPressed: busy ? null : () => editDetails(profile),
                    child: const Text('EDIT PROFILE')),
                TextButton(
                    onPressed: busy ? null : () => changeEmail(profile),
                    child: const Text('CHANGE EMAIL')),
                TextButton(
                    onPressed: busy ? null : changePassword,
                    child: const Text('CHANGE PASSWORD')),
                TextButton(
                    onPressed: busy ? null : refreshEmail,
                    child: const Text('REFRESH ACCOUNT')),
                if (photo.isNotEmpty)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                              await widget.store.removeProfilePhoto();
                              message('Profile picture removed.');
                            }),
                    child: const Text('REMOVE PICTURE'),
                  ),
              ]),
            ]),
          );
        },
      );
}
