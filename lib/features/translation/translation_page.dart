import 'package:flutter/material.dart';

import '../../app/theme/eazy_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class TranslationPage extends StatefulWidget {
  const TranslationPage({super.key});

  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  final api = ApiClient();
  final input = TextEditingController();

  String target = 'fr';
  String result = '';
  String error = '';
  bool busy = false;

  Future<void> translate() async {
    final source = input.text.trim();
    if (busy) return;
    if (source.isEmpty) {
      setState(() {
        error = 'Enter some text to translate.';
        result = '';
      });
      return;
    }

    setState(() {
      busy = true;
      error = '';
      result = '';
    });

    try {
      final response = await api.post(
        'translation',
        body: {'text': source, 'targetLanguage': target},
        auth: true,
      );
      final translated = response['translatedText']?.toString().trim();
      if (translated == null || translated.isEmpty) {
        throw const ApiException(
          'The translation provider returned an empty result. Please try again.',
          kind: ApiErrorKind.provider,
        );
      }
      if (mounted) setState(() => result = translated);
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Translation could not be completed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Translation',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Translation uses the production provider boundary. If no vendor is configured, Eazy reports that honestly instead of fabricating a result.',
                style: TextStyle(color: EazyColors.muted, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: input,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Write something to translate...',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: target,
            items: const [
              DropdownMenuItem(value: 'fr', child: Text('French')),
              DropdownMenuItem(value: 'es', child: Text('Spanish')),
              DropdownMenuItem(value: 'de', child: Text('German')),
              DropdownMenuItem(value: 'yo', child: Text('Yorùbá')),
            ],
            onChanged: busy ? null : (value) => setState(() => target = value ?? 'fr'),
            decoration: const InputDecoration(labelText: 'Target language'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : translate,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.translate_rounded),
            label: Text(busy ? 'Translating...' : 'Translate'),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, style: const TextStyle(color: EazyColors.red)),
            ),
          if (result.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(result, style: const TextStyle(fontSize: 17, height: 1.4)),
              ),
            ),
        ],
      ),
    );
  }
}
