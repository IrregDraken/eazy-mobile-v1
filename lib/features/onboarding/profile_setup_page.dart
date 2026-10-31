import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/media/media_service.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, required this.auth});
  final AuthController auth;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final first = TextEditingController(),
      middle = TextEditingController(),
      last = TextEditingController();
  final username = TextEditingController(), bio = TextEditingController();
  DateTime? dob;
  bool busy = false, checking = false, usernameManuallyEdited = false;
  bool avatarBusy = false;
  String? avatarPath;
  String? avatarLocalPath;
  bool? available;
  String? error;

  @override
  void initState() {
    super.initState();
    final p = widget.auth.profile;
    first.text = p?['firstName']?.toString() ?? '';
    middle.text = p?['middleName']?.toString() ?? '';
    last.text = p?['lastName']?.toString() ?? '';
    username.text =
        p?['username']?.toString().replaceFirst(RegExp(r'^user_'), '') ?? '';
    bio.text = p?['bio']?.toString() ?? '';
    final raw = p?['dateOfBirth']?.toString();
    if (raw != null && raw.length >= 10) {
      dob = DateTime.tryParse(raw.substring(0, 10));
    }
  }

  @override
  void dispose() {
    for (final c in [first, middle, last, username, bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickDob() async {
    final now = DateTime.now();
    final latest = DateTime(now.year - 18, now.month, now.day);
    final initial = dob == null || dob!.isAfter(latest) ? latest : dob!;
    DateTime selected = initial;
    final value = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: context.eazyBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.eazyMuted.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'When were you born?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'You must be at least 18 to use Eazy.',
                      style: TextStyle(color: context.eazyMuted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CalendarDatePicker(
                    initialDate: initial,
                    firstDate: DateTime(1900),
                    lastDate: latest,
                    currentDate: latest,
                    onDateChanged: (date) => setSheetState(() => selected = date),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(selected),
                      child: const Text('Confirm date of birth'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (value != null) setState(() => dob = value);
  }

  Future<void> pickAvatar() async {
    setState(() {
      avatarBusy = true;
      error = null;
    });
    try {
      final upload = await EazyMediaService(ApiClient()).pickAndUpload(kind: 'avatar');
      if (upload != null && mounted) {
        setState(() {
          avatarPath = upload.path;
          avatarLocalPath = upload.localPath;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => avatarBusy = false);
    }
  }

  void suggestUsername() {
    if (usernameManuallyEdited) return;
    final candidate = [first.text.trim(), last.text.trim()]
        .where((part) => part.isNotEmpty)
        .join('_')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (candidate.length >= 3) {
      final text =
          candidate.length > 32 ? candidate.substring(0, 32) : candidate;
      username.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      available = null;
    }
  }

  Future<void> checkUsername() async {
    final value = username.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(value)) {
      setState(() => available = null);
      return;
    }
    setState(() => checking = true);
    try {
      final result = await ApiClient().get(
        'profiles/username/$value/availability',
      );
      if (mounted) setState(() => available = result['available'] == true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> save() async {
    final f = first.text.trim(), u = username.text.trim().toLowerCase();
    if (f.isEmpty || u.isEmpty || dob == null) {
      setState(
        () => error = 'First name, username and date of birth are required.',
      );
      return;
    }
    final today = DateTime.now();
    var age = today.year - dob!.year;
    if (today.month < dob!.month ||
        (today.month == dob!.month && today.day < dob!.day)) {
      age--;
    }
    if (age < 18) {
      setState(() => error = 'You must be at least 18 years old to use Eazy.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(u)) {
      setState(
        () =>
            error =
                'Username must be 3-32 lowercase letters, numbers or underscores.',
      );
      return;
    }
    if (available == false) {
      setState(() => error = 'That username is already taken.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final profile = <String, dynamic>{
        'firstName': f,
        'middleName': middle.text.trim(),
        'lastName': last.text.trim(),
        'username': u,
        'bio': bio.text.trim(),
        'dateOfBirth':
            '${dob!.year.toString().padLeft(4, '0')}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}',
      };
      if (avatarPath != null) profile['avatarUrl'] = avatarPath;
      await widget.auth.completeOnboarding(profile);
      if (mounted) context.go('/discovery');
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set up your profile')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        children: [
          Text(
            'Make Eazy yours',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'A few details unlock your social identity, wallet and marketplace experience.',
            style: TextStyle(color: context.eazyMuted, height: 1.5),
          ),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: context.eazyAccent.withValues(alpha: .10),
                  backgroundImage: avatarLocalPath != null
                      ? FileImage(File(avatarLocalPath!))
                      : widget.auth.profile?['avatarUrl'] is String
                          ? NetworkImage(widget.auth.profile!['avatarUrl'].toString())
                          : null,
                  child: avatarLocalPath != null || widget.auth.profile?['avatarUrl'] is String
                      ? null
                      : Icon(Icons.person_rounded, size: 38, color: context.eazyAccent),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy || avatarBusy ? null : pickAvatar,
                  icon: avatarBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.add_a_photo_outlined),
                  label: Text(avatarBusy ? 'Uploading photo…' : avatarPath != null ? 'Photo uploaded' : 'Add profile photo'),
                ),
                Text(
                  'Add a clear photo so people can recognise you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.eazyMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (error != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: first,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(suggestUsername),
            decoration: const InputDecoration(labelText: 'First name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: middle,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Middle name (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: last,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(suggestUsername),
            decoration: const InputDecoration(
              labelText: 'Last name (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: username,
            autocorrect: false,
            onChanged:
                (_) => setState(() {
                  usernameManuallyEdited = true;
                  available = null;
                }),
            onEditingComplete: checkUsername,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixText: '@ ',
              suffixIcon:
                  checking
                      ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : available == true
                      ? Icon(Icons.check_circle, color: context.eazyAccent)
                      : available == false
                      ? Icon(Icons.cancel, color: Theme.of(context).colorScheme.error)
                      : null,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            tileColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EazyRadius.md),
              side: BorderSide(color: context.eazyBorder),
            ),
            leading: Icon(Icons.cake_outlined, color: context.eazyAccent),
            title: Text(
              dob == null
                  ? 'Date of birth'
                  : '${dob!.day}/${dob!.month}/${dob!.year}',
            ),
            subtitle: const Text('Required to complete your Eazy profile'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: busy ? null : pickDob,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bio,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Bio',
              hintText: 'Tell people a little about you',
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: busy ? null : save,
              child:
                  busy
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Finish setup'),
            ),
          ),
        ],
      ),
    ),
  );
}
