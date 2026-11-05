import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final api = ApiClient();
  final subject = TextEditingController();
  final description = TextEditingController();
  String category = 'bug';
  String? supportEmail;
  String? error;
  String? reportReference;
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    loadConfig();
  }

  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> loadConfig() async {
    try {
      final result = await api.get('support/config', auth: true);
      if (mounted) setState(() => supportEmail = result['supportEmail']?.toString());
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submitReport() async {
    if (subject.text.trim().length < 5 || description.text.trim().length < 20) {
      setState(() => error = 'Add a subject (at least 5 characters) and describe the problem in at least 20 characters.');
      return;
    }
    setState(() {
      sending = true;
      error = null;
      reportReference = null;
    });
    try {
      final result = await api.post(
        'support/reports',
        auth: true,
        body: {
          'category': category,
          'subject': subject.text.trim(),
          'description': description.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() {
        reportReference = result['reportId']?.toString();
        subject.clear();
        description.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & support')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.support_agent_rounded),
                      SizedBox(width: 10),
                      Text('Contact support', style: TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const LinearProgressIndicator(minHeight: 2)
                  else if (supportEmail == null || supportEmail!.isEmpty)
                    Text(
                      'A support email has not been configured yet. You can still submit a report below.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  else
                    Row(
                      children: [
                        Expanded(child: SelectableText(supportEmail!)),
                        IconButton(
                          tooltip: 'Copy support email',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: supportEmail!));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Support email copied.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Report a problem', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'bug', child: Text('App issue')),
                      DropdownMenuItem(value: 'account', child: Text('Account')),
                      DropdownMenuItem(value: 'payments', child: Text('Payments')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: sending ? null : (value) {
                      if (value != null) setState(() => category = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subject,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Subject'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: description,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Describe the problem',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                  if (reportReference != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Report received. Reference: $reportReference',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: sending ? null : submitReport,
                      icon: sending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(sending ? 'Sending report…' : 'Submit report'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
