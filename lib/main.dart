import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'translate_service.dart';

void main() => runApp(const PdfApp());

class PdfApp extends StatelessWidget {
  const PdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _pdf = PdfService();
  final _svc = TranslateService();

  static const _langs = {
    'Indonesian': 'Indonesian (Bahasa Indonesia)',
    'English': 'English',
    'Korean': 'Korean',
    'Chinese': 'Simplified Chinese',
  };

  List<String> _customStyles = [];
  String _lang = 'English';
  String? _styleInstruction = StyleStore.presets['Literal'];
  String? _source;
  String? _result;
  bool _busy = false;
  int _done = 0, _total = 0;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    StyleStore.loadCustom().then((l) {
      if (mounted) setState(() => _customStyles = l);
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickPdf() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _source = null;
      _result = null;
    });
    try {
      final text = await _pdf.extract(path);
      if (!mounted) return;
      if (text.isEmpty) {
        _snack('No text found - looks like a scanned/image PDF (OCR not supported yet)');
      }
      setState(() => _source = text);
    } catch (e) {
      _snack('Failed to read PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _translate() async {
    if (_source == null || _source!.isEmpty) return;
    final key = await _svc.getKey();
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      _askForKey();
      return;
    }
    setState(() {
      _busy = true;
      _done = 0;
      _total = 0;
      _result = null;
      _cancelRequested = false;
    });
    try {
      final out = await _svc.translateAll(
        _source!,
        lang: _langs[_lang]!,
        style: _styleInstruction,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            _done = d;
            _total = t;
          });
        },
        cancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() => _result = out);
    } catch (e) {
      final msg = e.toString();
      _snack(msg.contains('NO_KEY')
          ? 'Add your Gemini API key first (key icon, top right)'
          : msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAndShare() async {
    if (_result == null) return;
    final f = await _svc.saveTxt(_result!);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path)], text: 'Translation'),
    );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _result ?? ''));
    _snack('Copied to clipboard');
  }

  Future<void> _askForKey() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API key'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Free: open aistudio.google.com in your browser, tap '
                '"Get API key", create one, and paste it here. '
                'The key stays on this device only.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'AIza...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await _svc.setKey(c.text);
      if (mounted) _snack('API key saved');
    }
  }

  Future<void> _newStyle() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New style'),
        content: TextField(
          controller: c,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. make it formal, a little long, and stylish',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      final s = c.text.trim();
      await StyleStore.addCustom(s);
      if (!mounted) return;
      setState(() {
        _customStyles.add(s);
        _styleInstruction = s;
      });
    }
  }

  List<Widget> _styleChips() {
    final chips = <Widget>[];
    StyleStore.presets.forEach((name, instr) {
      chips.add(ChoiceChip(
        label: Text(name),
        selected: _styleInstruction == instr,
        onSelected: (_) => setState(() => _styleInstruction = instr),
      ));
    });
    for (final s in _customStyles) {
      chips.add(ChoiceChip(
        label: Text('★ ${s.length > 16 ? '${s.substring(0, 16)}…' : s}'),
        selected: _styleInstruction == s,
        onSelected: (_) => setState(() => _styleInstruction = s),
      ));
    }
    chips.add(ActionChip(
      avatar: const Icon(Icons.add, size: 18),
      label: const Text('New style'),
      onPressed: _newStyle,
    ));
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Translator'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.key), onPressed: _askForKey),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _card('1. PDF file', [
                FilledButton.icon(
                  onPressed: _busy ? null : _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(_source == null ? 'Choose PDF' : 'Choose another PDF'),
                ),
                if (_source != null) ...[
                  const SizedBox(height: 8),
                  Text('${_source!.length} characters extracted'),
                  const SizedBox(height: 8),
                  _box(
                    height: 110,
                    child: SelectableText(
                      _source!.length > 500 ? '${_source!.substring(0, 500)}…' : _source!,
                    ),
                  ),
                ],
              ]),
              _card('2. Target language', [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _langs.entries
                      .map((e) => ChoiceChip(
                            label: Text(e.key),
                            selected: _lang == e.key,
                            onSelected: (_) => setState(() => _lang = e.key),
                          ))
                      .toList(),
                ),
              ]),
              _card('3. Style', [
                Wrap(spacing: 8, runSpacing: 8, children: _styleChips()),
              ]),
              _card('4. Translate', [
                FilledButton.icon(
                  onPressed: (_busy || _source == null || _source!.isEmpty)
                      ? null
                      : _translate,
                  icon: const Icon(Icons.translate),
                  label: Text(_busy ? 'Working…' : 'Translate'),
                ),
                if (_busy && _total > 0) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _done / _total),
                  Text('Part $_done of $_total'),
                  TextButton(
                    onPressed: () => _cancelRequested = true,
                    child: const Text('Cancel'),
                  ),
                ],
                if (_busy && _total == 0) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ]),
              if (_result != null)
                _card('Result', [
                  _box(height: 300, child: SelectableText(_result!)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveAndShare,
                        icon: const Icon(Icons.save),
                        label: const Text('.txt'),
                      ),
                    ),
                  ]),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _box({required double height, required Widget child}) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(child: child),
    );
  }
}
