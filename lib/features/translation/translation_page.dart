import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  List<Map<String, String>> languages = [];
  String source = 'auto';
  String target = 'fr';
  String result = '';
  String error = '';
  bool loadingLanguages = true;
  bool providerAvailable = false;
  bool busy = false;
  String _languageName(String code) {
    if (code == 'auto') return 'Detect automatically';
    return languages.firstWhere(
      (language) => language['code'] == code,
      orElse: () => {'name': code},
    )['name']!;
  }

  Future<void> _chooseLanguage({required bool isSource}) async {
    final controller = TextEditingController();
    String query = '';
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final filtered = languages.where((language) {
            if (isSource && language['code'] == target) return false;
            if (!isSource && language['code'] == source) return false;
            final value = (language['name']! + ' ' + language['code']!).toLowerCase();
            return value.contains(query.toLowerCase());
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search languages or language codes',
                      ),
                    ),
                  ),
                  if (isSource)
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: const Text('Detect automatically'),
                      onTap: () => Navigator.pop(sheetContext, 'auto'),
                    ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching supported languages.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, index) {
                              final language = filtered[index];
                              return ListTile(
                                title: Text(language['name']!),
                                trailing: Text(
                                  language['code']!,
                                  style: TextStyle(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
                                ),
                                onTap: () => Navigator.pop(sheetContext, language['code']),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || selected == null) return;
    setState(() {
      if (isSource) {
        source = selected;
        if (source == target) source = 'auto';
      } else {
        target = selected;
        if (target == source) source = 'auto';
      }
    });
  }

  @override
  void initState() {
    super.initState();
    loadLanguages();
  }

  Future<void> loadLanguages() async {
    if (mounted) {
      setState(() {
        loadingLanguages = true;
        error = '';
        result = '';
      });
    }
    try {
      final response = await api.get('translation/capabilities', auth: true);
      final available = response['providerAvailable'] == true;
      final items = (response['languages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => {
                'code': item['code']?.toString() ?? '',
                'name': item['name']?.toString() ?? '',
              })
          .where((item) => item['code']!.isNotEmpty && item['name']!.isNotEmpty)
          .toList()
        ..sort((a, b) => a['name']!.compareTo(b['name']!));
      if (!mounted) return;
      setState(() {
        providerAvailable = available && items.isNotEmpty;
        languages = items;
        if (!languages.any((language) => language['code'] == target)) {
          target = languages.any((language) => language['code'] == 'fr')
              ? 'fr'
              : (languages.isNotEmpty ? languages.first['code']! : '');
        }
        if (source != 'auto' && !languages.any((language) => language['code'] == source)) {
          source = 'auto';
        }
      });
      if (!providerAvailable) {
        setState(() => error = 'Translation is temporarily unavailable. Please try again shortly.');
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (_) {
      if (mounted) setState(() => error = 'We could not load the available languages. Please try again.');
    } finally {
      if (mounted) setState(() => loadingLanguages = false);
    }
  }

  Future<void> translate() async {
    if (input.text.trim().isEmpty || busy || !providerAvailable || target.isEmpty) return;
    setState(() {
      busy = true;
      error = '';
      result = '';
    });
    try {
      final body = <String, dynamic>{
        'text': input.text.trim(),
        'targetLanguage': target,
        if (source != 'auto') 'sourceLanguage': source,
      };
      final response = await api.post('translation', body: body, auth: true);
      if (!mounted) return;
      setState(() => result = response['translatedText']?.toString() ?? '');
      if (result.isEmpty) setState(() => error = 'We could not produce a translation. Please try again.');
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Translation', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              tooltip: 'Refresh languages',
              onPressed: loadingLanguages ? null : loadLanguages,
              icon: loadingLanguages
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.paddingOf(context).bottom + 28),
          children: [
            const Text(
              'Translate naturally',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Write your message, choose the languages, and get your translation.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: input,
              minLines: 5,
              maxLines: 10,
              maxLength: 5000,
              decoration: const InputDecoration(
                hintText: 'Write something to translate...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            if (loadingLanguages)
              const LinearProgressIndicator()
            else if (languages.isNotEmpty) ...[
              Text(
                '${languages.length} languages supported by the configured provider',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 9),
              OutlinedButton(
                onPressed: () => _chooseLanguage(isSource: true),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.translate_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Translate from', style: TextStyle(fontSize: 11)),
                          Text(_languageName(source), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => _chooseLanguage(isSource: false),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Translate to', style: TextStyle(fontSize: 11)),
                          Text(_languageName(target), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy || loadingLanguages || !providerAvailable ? null : translate,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.translate_rounded),
              label: Text(busy ? 'Translating' : 'Translate'),
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.35)),
              ),
            if (result.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Translation', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                          IconButton(
                            tooltip: 'Copy translation',
                            onPressed: () => Clipboard.setData(ClipboardData(text: result)),
                            icon: const Icon(Icons.copy_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result,
                        style: const TextStyle(fontSize: 17, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
