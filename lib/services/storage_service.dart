import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'secrets_service.dart';

// Top-level function for isolate — cannot capture closures
String _computePayloadHash(Uint8List bytes) {
  return sha256.convert(bytes).toString();
}

class StorageService {
  static const _uuid = Uuid();
  
  // Upload image to Cloudflare R2
  static Future<String> uploadImage({
    required File file,
    required String folder,
  }) async {
    final fileName = '${_uuid.v4()}.jpg';
    final key = '$folder/$fileName';
    
    final bytes = await file.readAsBytes();
    
    return await _uploadToR2(
      key: key,
      bytes: bytes,
      contentType: 'image/jpeg',
    );
  }
  
  // Upload file with custom content type (for videos, etc.)
  static Future<String> uploadFile({
    required File file,
    required String folder,
    required String contentType,
    required String extension,
  }) async {
    final fileName = '${_uuid.v4()}.$extension';
    final key = '$folder/$fileName';
    final bytes = await file.readAsBytes();
    return await _uploadToR2(
      key: key,
      bytes: bytes,
      contentType: contentType,
    );
  }

  // Upload image from bytes (for web)
  static Future<String> uploadImageBytes({
    required Uint8List bytes,
    required String folder,
    required String extension,
  }) async {
    final fileName = '${_uuid.v4()}.$extension';
    final key = '$folder/$fileName';
    
    return await _uploadToR2(
      key: key,
      bytes: bytes,
      contentType: 'image/$extension',
    );
  }
  
  // Upload to R2 via direct S3 PUT request with AWS Signature Version 4
  static Future<String> _uploadToR2({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final secrets = SecretsService.instance;
    final bucket = secrets.r2BucketName;
    final accessKey = secrets.r2AccessKeyId;
    final secretKey = secrets.r2SecretAccessKey;
    final endpoint = secrets.r2Endpoint;

    final uri = Uri.parse(endpoint);
    final host = uri.host;

    final region = 'auto';
    final service = 's3';

    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);

    final payloadHash = await Isolate.run(() => _computePayloadHash(bytes));
    final canonicalUri = '/$bucket/$key';

    final canonicalHeaders = 'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    final signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = 'PUT\n'
        '$canonicalUri\n'
        '\n'
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';

    final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = 'AWS4-HMAC-SHA256\n'
        '$amzDate\n'
        '$credentialScope\n'
        '$canonicalRequestHash';

    final signingKey = _getSigningKey(secretKey, dateStamp, region, service);
    final signatureBytes = _hmacSha256(signingKey, stringToSign);
    final signature = signatureBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final authorization = 'AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final uploadUrl = '$endpoint/$bucket/$key';
    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {
        'Authorization': authorization,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': payloadHash,
        'Content-Type': contentType,
        'Content-Length': bytes.length.toString(),
        'Host': host,
      },
      body: bytes,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return '${secrets.r2PublicUrl}/$key';
    } else {
      throw Exception('Failed to upload image: ${response.statusCode} ${response.body}');
    }
  }
  
  // Delete image from R2
  static Future<void> deleteImage(String imageUrl) async {
    // Extract key from URL
    final uri = Uri.parse(imageUrl);
    final key = uri.path.substring(1); // Remove leading slash
    
    final secrets = SecretsService.instance;
    final bucket = secrets.r2BucketName;
    final accessKey = secrets.r2AccessKeyId;
    final secretKey = secrets.r2SecretAccessKey;
    final endpoint = secrets.r2Endpoint;

    final host = Uri.parse(endpoint).host;
    final region = 'auto';
    final service = 's3';
    
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);
    
    final payloadHash = sha256.convert([]).toString(); // Empty body
    final canonicalUri = '/$bucket/$key';
    
    final canonicalHeaders = 'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    final signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
    
    final canonicalRequest = 'DELETE\n'
        '$canonicalUri\n'
        '\n'
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';
        
    final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = 'AWS4-HMAC-SHA256\n'
        '$amzDate\n'
        '$credentialScope\n'
        '$canonicalRequestHash';
        
    final signingKey = _getSigningKey(secretKey, dateStamp, region, service);
    final signatureBytes = _hmacSha256(signingKey, stringToSign);
    final signature = signatureBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    final authorization = 'AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';
    
    final deleteUrl = '$endpoint/$bucket/$key';
    final response = await http.delete(
      Uri.parse(deleteUrl),
      headers: {
        'Authorization': authorization,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': payloadHash,
        'Host': host,
      },
    );
    
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete image: ${response.statusCode} ${response.body}');
    }
  }
  
  // Get optimized image URL with transformations
  static String getOptimizedUrl(String imageUrl, {int? width, int? height}) {
    return imageUrl;
  }
  
  // Helpers for AWS SigV4
  static String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T'
        '${_twoDigits(date.hour)}'
        '${_twoDigits(date.minute)}'
        '${_twoDigits(date.second)}Z';
  }
  
  static String _formatDateStamp(DateTime date) {
    return '${date.year}'
        '${_twoDigits(date.month)}'
        '${_twoDigits(date.day)}';
  }
  
  static String _twoDigits(int n) {
    return n >= 10 ? '$n' : '0$n';
  }
  
  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }
  
  static List<int> _getSigningKey(String secretKey, String dateStamp, String region, String service) {
    final kDate = _hmacSha256(utf8.encode('AWS4$secretKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, service);
    final kSigning = _hmacSha256(kService, 'aws4_request');
    return kSigning;
  }
}
