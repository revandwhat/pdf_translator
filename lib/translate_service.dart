import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  Future<String> extract(String path) async {
    final bytes = await File(path).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    return text.trim();
  }
}

class StyleStore {
  static const presets = <String, String>{
    'Literal': 'Translate faithfully and naturally, without changing the tone.',
    'Formal': 'Use a formal, polite, professional register.',
    'Barbarian': 'Use an aggressive, dramatic "barbarian warrior" voice: blunt, forceful, over-the-top wording and short battle-cry sentences.',
    'Short': 'Be very concise: shorten sentences aggressively and cut filler, but keep the meaning.',
  };

  static Future<List<String>> loadCustom() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList('custom_styles') ?? [];
  }

  static Future<void> addCustom(String instruction) async {
    final p = await SharedPreferences.getInstance();
    final list = await loadCustom();
    list.add(instruction.trim());
    await p.setStringList('custom_styles', list);
  }
}

class TranslateService {
  // If the API ever says "model not found", change this string.
  static const _model = 'gemini-3.8-flash';
  static const _url =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  Future<String?> getKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('gemini_key');
  }

  Future<void> setKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('gemini_key', key.trim());
  }

  List<String> chunk(String text, [int max = 3500]) {
    if (text.length <= max) return [text];
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    final chunks = <String>[];
    var buf = '';
    for (final para in paragraphs) {
      if (para.length > max) {
        if (buf.isNotEmpty) {
          chunks.add(buf.trim());
          buf = '';
        }
        for (var i = 0; i < para.length; i += max) {
          final end = (i + max < para.length) ? i + max : para.length;
          chunks.add(para.substring(i, end));
        }
        continue;
      }
      if (('$buf\n\n$para').length > max) {
        chunks.add(buf.trim());
        buf = para;
      } else {
        buf = buf.isEmpty ? para : '$buf\n\n$para';
      }
    }
    if (buf.trim().isNotEmpty) chunks.add(buf.trim());
    return chunks;
  }

  Future<String> _call(String prompt, String key) async {
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        final res = await http
            .post(
              Uri.parse('$_url?key=$key'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {'temperature': 0.3},
              }),
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final cands = data['candidates'] as List?;
          if (cands != null && cands.isNotEmpty) {
            final parts = cands[0]['content']['parts'] as List;
            return (parts[0]['text'] ?? '').toString().trim();
          }
          throw Exception('Empty response from API');
        }
        if (res.statusCode == 429 || res.statusCode >= 500) {
          await Future.delayed(Duration(seconds: 8 * attempt));
          continue;
        }
        throw Exception('API ${res.statusCode}: ${res.body}');
      } on TimeoutException {
        if (attempt == 4) rethrow;
      }
    }
    throw Exception('API kept failing (rate limit?) - try again later');
  }

  Future<String> translateChunk(String text, String lang, String? style) async {
    final key = await getKey();
    if (key == null || key.isEmpty) throw Exception('NO_KEY');
    final styleLine = (style == null || style.trim().isEmpty)
        ? ''
        : 'Style instructions: ${style.trim()}\n';
    final prompt = 'You are a professional translator.\n'
        'Translate the text inside <text> tags into $lang.\n'
        '$styleLine'
        'Rules:\n'
        '- Output ONLY the translation. No notes, no explanations, no markdown.\n'
        '- Keep the paragraph structure.\n\n'
        '<text>\n$text\n</text>';
    return _call(prompt, key);
  }

  Future<String> translateAll(
    String text, {
    required String lang,
    String? style,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final chunks = chunk(text);
    final out = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      if (cancelled?.call() ?? false) throw Exception('CANCELLED');
      out.add(await translateChunk(chunks[i], lang, style));
      onProgress?.call(i + 1, chunks.length);
      if (i < chunks.length - 1) {
        await Future.delayed(const Duration(seconds: 6));
      }
    }
    return out.join('\n\n');
  }

  Future<File> saveTxt(String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = 'translated_${DateTime.now().millisecondsSinceEpoch}.txt';
    return File('${dir.path}/$name').writeAsString(content);
  }
}
