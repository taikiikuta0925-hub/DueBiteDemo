import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AiExpiryResult {
  const AiExpiryResult({
    required this.name,
    required this.expiryDate,
    required this.category,
    required this.confidence,
    required this.isDemo,
  });

  final String name;
  final DateTime expiryDate;
  final String category;
  final double confidence;
  final bool isDemo;
}

class ProductChatMessage {
  const ProductChatMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};
}

class ProductAgentResult {
  const ProductAgentResult({
    required this.reply,
    required this.ready,
    required this.name,
    required this.expiryDate,
    required this.category,
    required this.confidence,
    required this.isDemo,
  });

  final String reply;
  final bool ready;
  final String name;
  final DateTime? expiryDate;
  final String category;
  final double confidence;
  final bool isDemo;
}

class AiExpiryService {
  const AiExpiryService();

  static const endpoint = String.fromEnvironment('AI_API_BASE_URL');

  bool get isConfigured => endpoint.trim().isNotEmpty;

  Future<AiExpiryResult> analyze(XFile image) async {
    if (!isConfigured) {
      // UIをAPIキーなしでも確認できる開発用フォールバック。
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      return AiExpiryResult(
        name: 'プレーンヨーグルト',
        expiryDate: DateTime.now().add(const Duration(days: 7)),
        category: '乳製品',
        confidence: 0.94,
        isDemo: true,
      );
    }

    final bytes = await image.readAsBytes();
    final uri = _endpointFor('analyze-expiry');
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'imageBase64': base64Encode(bytes),
            'mimeType': image.mimeType ?? _mimeTypeFor(image.name),
            'today': _dateOnly(DateTime.now()),
            'locale': 'ja-JP',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiExpiryException('AIサーバーに接続できませんでした (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = decoded['data'] is Map<String, dynamic>
        ? decoded['data'] as Map<String, dynamic>
        : decoded;
    final expiryText = payload['expiryDate'] as String?;
    final expiryDate = expiryText == null
        ? null
        : DateTime.tryParse(expiryText);
    if (expiryDate == null) {
      throw const AiExpiryException('写真から賞味期限を読み取れませんでした');
    }

    return AiExpiryResult(
      name: payload['name'] as String? ?? '',
      expiryDate: expiryDate,
      category: payload['category'] as String? ?? 'その他',
      confidence: (payload['confidence'] as num?)?.toDouble() ?? 0,
      isDemo: false,
    );
  }

  Future<ProductAgentResult> identifyProduct(
    List<ProductChatMessage> messages,
  ) async {
    if (!isConfigured) return _demoIdentify(messages);

    final response = await http
        .post(
          _endpointFor('identify-product'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'messages': messages.map((message) => message.toJson()).toList(),
            'today': _dateOnly(DateTime.now()),
            'locale': 'ja-JP',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiExpiryException(
        _errorMessage(response.body, fallback: 'AIエージェントに接続できませんでした'),
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final expiryText = decoded['expiryDate'] as String? ?? '';
    final expiryDate = DateTime.tryParse(expiryText);
    final name = decoded['name'] as String? ?? '';
    final ready =
        decoded['ready'] == true &&
        name.trim().isNotEmpty &&
        expiryDate != null;
    return ProductAgentResult(
      reply: decoded['reply'] as String? ?? 'もう少し詳しく教えてください。',
      ready: ready,
      name: name,
      expiryDate: expiryDate,
      category: decoded['category'] as String? ?? 'その他',
      confidence: (decoded['confidence'] as num?)?.toDouble() ?? 0,
      isDemo: false,
    );
  }

  Uri _endpointFor(String action) {
    final uri = Uri.parse(endpoint);
    final segments = [...uri.pathSegments];
    if (segments.isNotEmpty &&
        (segments.last == 'analyze-expiry' ||
            segments.last == 'identify-product')) {
      segments[segments.length - 1] = action;
    } else {
      segments.add(action);
    }
    return uri.replace(pathSegments: segments);
  }

  Future<ProductAgentResult> _demoIdentify(
    List<ProductChatMessage> messages,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final conversation = messages
        .where((message) => message.role == 'user')
        .map((message) => message.text)
        .join(' ');
    final product = _detectDemoProduct(conversation);
    final expiryDate = _detectDemoDate(conversation);

    if (product == null) {
      return const ProductAgentResult(
        reply: 'どんな食品ですか？ パッケージの名前や種類を教えてください。',
        ready: false,
        name: '',
        expiryDate: null,
        category: 'その他',
        confidence: 0,
        isDemo: true,
      );
    }
    if (expiryDate == null) {
      return ProductAgentResult(
        reply: '$productのパッケージに印字された賞味期限または消費期限はいつですか？',
        ready: false,
        name: product,
        expiryDate: null,
        category: _demoCategory(product),
        confidence: .7,
        isDemo: true,
      );
    }
    return ProductAgentResult(
      reply: '$product、期限は${_dateOnly(expiryDate)}ですね。この内容で登録できます。',
      ready: true,
      name: product,
      expiryDate: expiryDate,
      category: _demoCategory(product),
      confidence: .9,
      isDemo: true,
    );
  }

  String? _detectDemoProduct(String text) {
    const products = ['ヨーグルト', '牛乳', '豆腐', '納豆', '卵', 'チーズ', 'ハム', 'パン'];
    for (final product in products) {
      if (text.contains(product)) return product;
    }
    return null;
  }

  String _demoCategory(String product) {
    if (product == '牛乳') return '飲み物';
    if (product == 'ヨーグルト' || product == 'チーズ') return '乳製品';
    if (product == 'ハム') return '肉・魚';
    return '冷蔵品';
  }

  DateTime? _detectDemoDate(String text) {
    final iso = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(text);
    if (iso != null) {
      return DateTime.tryParse(
        '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}',
      );
    }
    final japanese = RegExp(
      r'(?:(\d{4})年)?\s*(\d{1,2})月\s*(\d{1,2})日',
    ).firstMatch(text);
    if (japanese == null) return null;
    final now = DateTime.now();
    final year = int.tryParse(japanese.group(1) ?? '') ?? now.year;
    final month = int.tryParse(japanese.group(2) ?? '');
    final day = int.tryParse(japanese.group(3) ?? '');
    if (month == null || day == null) return null;
    final candidate = DateTime(year, month, day);
    if (candidate.month != month || candidate.day != day) return null;
    return candidate;
  }

  String _errorMessage(String responseBody, {required String fallback}) {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final message = decoded['error'];
      if (message is String && message.trim().isNotEmpty) return message;
    } catch (_) {
      // 読めないエラーレスポンスは利用者向けメッセージへ置き換える。
    }
    return fallback;
  }

  String _mimeTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class AiExpiryException implements Exception {
  const AiExpiryException(this.message);

  final String message;

  @override
  String toString() => message;
}
