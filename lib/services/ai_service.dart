import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../models/picked_media.dart';

class AIConfig {
  final String provider;
  final List<String> apiKeys;
  final String model;
  final String? cloudflareAccountId;

  AIConfig({
    required this.provider,
    required this.apiKeys,
    required this.model,
    this.cloudflareAccountId,
  });
}

class AIResult {
  final String title;
  final String description;
  final String categoryKeyword;
  final String categoryName;
  final Map<String, String> specifications;

  AIResult({
    required this.title,
    required this.description,
    required this.categoryKeyword,
    required this.categoryName,
    required this.specifications,
  });

  factory AIResult.fromJson(Map<String, dynamic> json) {
    // Extract specifications safely
    final specsMap = <String, String>{};
    if (json['specifications'] is Map) {
      (json['specifications'] as Map).forEach((k, v) {
        specsMap[k.toString()] = v.toString();
      });
    }

    return AIResult(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      categoryKeyword: json['category_keyword']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
      specifications: specsMap,
    );
  }
}

/// Background isolate: reads files from disk and returns base64 + mime pairs.
List<Map<String, String>> _encodeImagesIsolate(List<String> filePaths) {
  final results = <Map<String, String>>[];
  for (final path in filePaths) {
    final bytes = File(path).readAsBytesSync();
    var mime = 'image/jpeg';
    if (path.endsWith('.png')) {
      mime = 'image/png';
    } else if (path.endsWith('.webp')) {
      mime = 'image/webp';
    }
    results.add({'mime': mime, 'data': base64Encode(bytes)});
  }
  return results;
}

class AIService {
  static Future<AIConfig?> loadConfig() async {
    try {
      final providerRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'active_ai_provider'});
      final provider = providerRes?.toString();
      if (provider == null || (provider != 'gemini' && provider != 'groq' && provider != 'cloudflare')) {
        return null;
      }

      List<String> apiKeys = [];
      String? model;
      String? cloudflareAccountId;

      if (provider == 'gemini') {
        final keysRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'gemini_api_keys'});
        final keysStr = keysRes?.toString();
        if (keysStr != null && keysStr.trim().startsWith('[')) {
          try {
            final List<dynamic> decoded = jsonDecode(keysStr);
            apiKeys = decoded.map((k) => k.toString().trim()).where((k) => k.isNotEmpty).toList();
          } catch (_) {}
        }
        if (apiKeys.isEmpty) {
          final keyRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'gemini_api_key'});
          final key = keyRes?.toString();
          if (key != null && key.trim().isNotEmpty) {
            apiKeys.add(key.trim());
          }
        }
        final modelRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'gemini_model'});
        model = modelRes?.toString() ?? 'gemini-1.5-flash';
      } else if (provider == 'groq') {
        final keysRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'groq_api_keys'});
        final keysStr = keysRes?.toString();
        if (keysStr != null && keysStr.trim().startsWith('[')) {
          try {
            final List<dynamic> decoded = jsonDecode(keysStr);
            apiKeys = decoded.map((k) => k.toString().trim()).where((k) => k.isNotEmpty).toList();
          } catch (_) {}
        }
        if (apiKeys.isEmpty) {
          final keyRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'groq_api_key'});
          final key = keyRes?.toString();
          if (key != null && key.trim().isNotEmpty) {
            apiKeys.add(key.trim());
          }
        }
        final modelRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'groq_model'});
        model = modelRes?.toString() ?? 'meta-llama/llama-4-scout-17b-16e-instruct';
      } else if (provider == 'cloudflare') {
        final keysRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'cloudflare_api_keys'});
        final keysStr = keysRes?.toString();
        if (keysStr != null && keysStr.trim().startsWith('[')) {
          try {
            final List<dynamic> decoded = jsonDecode(keysStr);
            apiKeys = decoded.map((k) => k.toString().trim()).where((k) => k.isNotEmpty).toList();
          } catch (_) {}
        }
        if (apiKeys.isEmpty) {
          final keyRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'cloudflare_api_key'});
          final key = keyRes?.toString();
          if (key != null && key.trim().isNotEmpty) {
            apiKeys.add(key.trim());
          }
        }
        final modelRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'cloudflare_model'});
        model = modelRes?.toString() ?? '@cf/meta/llama-4-scout-17b-16e-instruct';
        final accountIdRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'cloudflare_account_id'});
        cloudflareAccountId = accountIdRes?.toString();
      }

      if (apiKeys.isEmpty || model == null) {
        debugPrint('AI config missing: provider=$provider, apiKeys=empty, model=${model != null ? "set" : "null"}');
        return null;
      }

      if (provider == 'cloudflare' && (cloudflareAccountId == null || cloudflareAccountId.trim().isEmpty)) {
        debugPrint('AI config missing: cloudflare_account_id is not set');
        return null;
      }

      return AIConfig(
        provider: provider,
        apiKeys: apiKeys,
        model: model.trim(),
        cloudflareAccountId: cloudflareAccountId?.trim(),
      );
    } catch (e) {
      debugPrint('Error loading AI config: $e');
      return null;
    }
  }

  static Future<AIResult?> analyzeProductImage({
    List<dynamic> localFiles = const [],
    List<String> imageUrls = const [],
    required List<String> categoryNames,
  }) async {
    try {
      // 1. Load configuration
      final config = await loadConfig();
      if (config == null) {
        throw Exception('AI configurations or active API keys are not set by the administrator.');
      }

      // 2. Encode local images (off main thread when possible)
      final images = <Map<String, String>>[];
      const maxImages = 5;

      if (localFiles.isNotEmpty) {
        if (kIsWeb) {
          // On web, files are PickedMedia with bytes already loaded.
          for (final file in localFiles) {
            if (images.length >= maxImages) break;
            if (file is PickedMedia) {
              images.add({'mime': 'image/jpeg', 'data': base64Encode(file.bytes)});
            }
          }
        } else {
          // On mobile, use file paths for background encoding.
          final paths = localFiles.map<String>((f) => f.path ?? '').where((p) => p.isNotEmpty).toList();
          if (paths.isNotEmpty) {
            final localImages = await compute(_encodeImagesIsolate, paths);
            for (final img in localImages) {
              if (images.length >= maxImages) break;
              images.add(img);
            }
          }
        }
      }

      // 3. Fetch remote images in parallel
      for (final url in imageUrls) {
        if (images.length >= maxImages) break;
        if (url.isEmpty) continue;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          var mime = 'image/jpeg';
          if (url.toLowerCase().contains('.png')) {
            mime = 'image/png';
          } else if (url.toLowerCase().contains('.webp')) {
            mime = 'image/webp';
          }
          images.add({'mime': mime, 'data': base64Encode(response.bodyBytes)});
        }
      }

      if (images.isEmpty) {
        throw Exception('No product image provided for AI analysis.');
      }

      // 4. Construct the prompt
      final imageCount = images.length;
      final prompt = '''
Analyze ${imageCount == 1 ? 'this product image' : 'these $imageCount product images'} carefully. Look at all provided images to get a complete understanding of the product from different angles. Your task is to output a JSON object containing:
1. "title": A short, catchy product title (max 6-8 words).
2. "description": A detailed product description covering appearance, features, and condition.
3. "category_keyword": A relevant search keyword for this product that can match one of the available categories.
4. "category_name": The exact name of the category from this list that fits the product best: ${categoryNames.join(', ')}.
5. "specifications": A dictionary of 3 to 6 technical key-value pairs representing specifications (e.g. "Brand": "Nike", "Color": "Black", "Material": "Leather").

Return ONLY the raw JSON object, without any markdown formatting or surrounding backticks (no ```json ... ```).
''';

      // 4. Build image content parts (provider-specific)
      String responseText = '';

      for (int idx = 0; idx < config.apiKeys.length; idx++) {
        final currentApiKey = config.apiKeys[idx];
        try {
          if (config.provider == 'gemini') {
            final url = 'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent?key=$currentApiKey';
            final parts = <Map<String, dynamic>>[
              {'text': prompt},
              ...images.map((img) => {
                'inline_data': {
                  'mime_type': img['mime'],
                  'data': img['data'],
                }
              }),
            ];
            final body = {
              'contents': [{'parts': parts}],
              'generationConfig': {
                'responseMimeType': 'application/json',
              }
            };

            final response = await http.post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            );

            if (response.statusCode == 200) {
              final resBody = jsonDecode(response.body);
              responseText = resBody['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '';
              break;
            } else {
              throw Exception('Gemini API call failed with status: ${response.statusCode}\nBody: ${response.body}');
            }
          } else if (config.provider == 'groq') {
            final url = 'https://api.groq.com/openai/v1/chat/completions';
            final content = <Map<String, dynamic>>[
              {'type': 'text', 'text': prompt},
              ...images.map((img) => {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${img['mime']};base64,${img['data']}',
                }
              }),
            ];
            final body = {
              'model': config.model,
              'messages': [
                {'role': 'user', 'content': content}
              ],
              'response_format': {
                'type': 'json_object',
              }
            };

            final response = await http.post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $currentApiKey',
              },
              body: jsonEncode(body),
            );

            if (response.statusCode == 200) {
              final resBody = jsonDecode(response.body);
              responseText = resBody['choices']?[0]?['message']?['content']?.toString() ?? '';
              break;
            } else {
              throw Exception('Groq API call failed with status: ${response.statusCode}\nBody: ${response.body}');
            }
          } else if (config.provider == 'cloudflare') {
            if (config.cloudflareAccountId == null || config.cloudflareAccountId!.isEmpty) {
              throw Exception('Cloudflare Account ID is not configured.');
            }

            final cfUrl = 'https://api.cloudflare.com/client/v4/accounts/${config.cloudflareAccountId}/ai/run/${config.model}';
            final content = <Map<String, dynamic>>[
              {'type': 'text', 'text': prompt},
              ...images.map((img) => {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${img['mime']};base64,${img['data']}',
                }
              }),
            ];
            final body = {
              'messages': [
                {'role': 'user', 'content': content}
              ],
              'stream': false,
            };

            final response = await http.post(
              Uri.parse(cfUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $currentApiKey',
              },
              body: jsonEncode(body),
            );

            if (response.statusCode == 200) {
              final resBody = jsonDecode(response.body);
              responseText = resBody['result']?['response']?.toString() ?? '';
              break;
            } else {
              throw Exception('Cloudflare Workers AI call failed with status: ${response.statusCode}\nBody: ${response.body}');
            }
          }
        } catch (e) {
          debugPrint('AI call failed with key index $idx (${config.provider}): $e');
          if (idx == config.apiKeys.length - 1) {
            rethrow;
          }
        }
      }

      // 5. Clean and parse JSON response
      if (responseText.isEmpty) {
        throw Exception('AI returned an empty response.');
      }

      final cleanedJson = _cleanJsonString(responseText);
      final decoded = jsonDecode(cleanedJson);
      return AIResult.fromJson(decoded);
    } catch (e) {
      debugPrint('AI processing error: $e');
      rethrow;
    }
  }

  static String _cleanJsonString(String rawText) {
    var cleaned = rawText.trim();
    if (cleaned.startsWith('```')) {
      final firstLineEnd = cleaned.indexOf('\n');
      if (firstLineEnd != -1) {
        cleaned = cleaned.substring(firstLineEnd).trim();
      }
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3).trim();
    }

    // Fix unquoted JSON: {key: value, key2: value2} → {"key": "value", "key2": "value2"}
    // Only apply if it looks like a Dart/Python map literal, not already valid JSON
    if (cleaned.startsWith('{') && !cleaned.startsWith('{"')) {
      cleaned = _fixUnquotedJson(cleaned);
    }

    return cleaned;
  }

  static String _fixUnquotedJson(String input) {
    final buffer = StringBuffer();
    var i = 0;
    final len = input.length;

    while (i < len) {
      final c = input[i];

      if (c == '{' || c == '}' || c == '[' || c == ']') {
        buffer.write(c);
        i++;
      } else if (c == ',') {
        buffer.write(',');
        i++;
      } else if (c == ':') {
        buffer.write(':');
        i++;
      } else if (c == '"') {
        // Already quoted — pass through until closing quote
        buffer.write('"');
        i++;
        while (i < len && input[i] != '"') {
          if (input[i] == '\\') {
            buffer.write(input[i]);
            i++;
          }
          if (i < len) {
            buffer.write(input[i]);
            i++;
          }
        }
        if (i < len) {
          buffer.write('"');
          i++;
        }
      } else if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
        i++;
      } else {
        // Unquoted token — read until next structural delimiter
        // (don't stop at spaces — values like "Olive Green" need to stay together)
        var token = '';
        while (i < len && ',:}]'.contains(input[i]) == false) {
          token += input[i];
          i++;
        }
        token = token.trim();
        if (token.isNotEmpty) {
          buffer.write('"$token"');
        }
      }
    }

    return buffer.toString();
  }
}
