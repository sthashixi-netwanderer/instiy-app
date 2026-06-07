import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class AIConfig {
  final String provider;
  final String apiKey;
  final String model;

  AIConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
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

class AIService {
  static Future<AIConfig?> loadConfig() async {
    try {
      final providerRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'active_ai_provider'});
      final provider = providerRes?.toString();
      if (provider == null || (provider != 'gemini' && provider != 'groq')) {
        return null;
      }

      String? apiKey;
      String? model;

      if (provider == 'gemini') {
        final keyRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'gemini_api_key'});
        apiKey = keyRes?.toString();
        final modelRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'gemini_model'});
        model = modelRes?.toString() ?? 'gemini-1.5-flash';
      } else {
        final keyRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'groq_api_key'});
        apiKey = keyRes?.toString();
        final modelRes = await SupabaseService.client.rpc('get_ai_key', params: {'p_key_name': 'groq_model'});
        model = modelRes?.toString() ?? 'llama-3.2-11b-vision-preview';
      }

      if (apiKey == null || apiKey.trim().isEmpty) {
        return null;
      }

      return AIConfig(
        provider: provider,
        apiKey: apiKey.trim(),
        model: model.trim(),
      );
    } catch (e) {
      debugPrint('Error loading AI config: $e');
      return null;
    }
  }

  static Future<AIResult?> analyzeProductImage({
    File? localFile,
    String? imageUrl,
    required List<String> categoryNames,
  }) async {
    try {
      // 1. Load configuration
      final config = await loadConfig();
      if (config == null) {
        throw Exception('AI configurations or active API keys are not set by the administrator.');
      }

      // 2. Fetch and base64-encode the image bytes
      String base64Image;
      String mimeType = 'image/jpeg';

      if (localFile != null) {
        final bytes = await localFile.readAsBytes();
        base64Image = base64Encode(bytes);
        if (localFile.path.endsWith('.png')) {
          mimeType = 'image/png';
        } else if (localFile.path.endsWith('.webp')) {
          mimeType = 'image/webp';
        }
      } else if (imageUrl != null && imageUrl.isNotEmpty) {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          base64Image = base64Encode(response.bodyBytes);
          if (imageUrl.toLowerCase().contains('.png')) {
            mimeType = 'image/png';
          } else if (imageUrl.toLowerCase().contains('.webp')) {
            mimeType = 'image/webp';
          }
        } else {
          throw Exception('Failed to download product image from URL.');
        }
      } else {
        throw Exception('No product image provided for AI analysis.');
      }

      // 3. Construct the prompt
      final prompt = '''
Analyze this product image. Your task is to output a JSON object containing:
1. "title": A short, catchy product title (max 6-8 words).
2. "description": A detailed product description.
3. "category_keyword": A relevant search keyword for this product that can match one of the available categories.
4. "category_name": The exact name of the category from this list that fits the product best: ${categoryNames.join(', ')}.
5. "specifications": A dictionary of 3 to 6 technical key-value pairs representing specifications (e.g. "Brand": "Nike", "Color": "Black", "Material": "Leather").

Return ONLY the raw JSON object, without any markdown formatting or surrounding backticks (no ```json ... ```).
''';

      // 4. Send API request based on active provider
      String responseText = '';

      if (config.provider == 'gemini') {
        final url = 'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent?key=${config.apiKey}';
        final body = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inline_data': {
                    'mime_type': mimeType,
                    'data': base64Image,
                  }
                }
              ]
            }
          ],
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
        } else {
          throw Exception('Gemini API call failed with status: ${response.statusCode}\nBody: ${response.body}');
        }
      } else if (config.provider == 'groq') {
        final url = 'https://api.groq.com/openai/v1/chat/completions';
        final body = {
          'model': config.model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,$base64Image',
                  }
                }
              ]
            }
          ],
          'response_format': {
            'type': 'json_object',
          }
        };

        final response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
          final resBody = jsonDecode(response.body);
          responseText = resBody['choices']?[0]?['message']?['content']?.toString() ?? '';
        } else {
          throw Exception('Groq API call failed with status: ${response.statusCode}\nBody: ${response.body}');
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
    return cleaned;
  }
}
