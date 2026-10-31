import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/cloudinary_config.dart';

class StorageService {
  /// Checks whether Cloudinary configuration has valid credentials
  static bool get isConfigured {
    final cloudName = CloudinaryConfig.cloudName.trim();
    final uploadPreset = CloudinaryConfig.uploadPreset.trim();
    return cloudName.isNotEmpty &&
        uploadPreset.isNotEmpty &&
        !cloudName.startsWith('PUT_') &&
        !uploadPreset.startsWith('PUT_');
  }

  /// Uploads an image or document file to Cloudinary and returns the secure URL.
  ///
  /// [file]: The local file to upload.
  /// [resourceType]: 'auto', 'image', or 'raw'. Defaults to 'auto'.
  /// [onProgress]: Optional callback with progress between 0.0 and 1.0.
  Future<String?> uploadFile(
    File file, {
    String resourceType = 'auto',
    void Function(double progress)? onProgress,
  }) async {
    const envCloudName = String.fromEnvironment(
      'CLOUDINARY_CLOUD_NAME',
      defaultValue: '',
    );
    const envUploadPreset = String.fromEnvironment(
      'CLOUDINARY_UPLOAD_PRESET',
      defaultValue: '',
    );

    final cloudName = envCloudName.isNotEmpty
        ? envCloudName.trim()
        : CloudinaryConfig.cloudName.trim();
    final uploadPreset = envUploadPreset.isNotEmpty
        ? envUploadPreset.trim()
        : CloudinaryConfig.uploadPreset.trim();

    if (cloudName.isEmpty ||
        uploadPreset.isEmpty ||
        cloudName.startsWith('PUT_') ||
        uploadPreset.startsWith('PUT_')) {
      debugPrint(
        'Cloudinary Error: Cloud Name or Upload Preset is not configured in cloudinary_config.dart',
      );
      throw Exception(
        'Cloudinary not configured. Please set cloudName and uploadPreset in lib/config/cloudinary_config.dart',
      );
    }

    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload',
      );

      final totalBytes = await file.length();
      int bytesSent = 0;

      // Stream that reports upload progress
      final stream = http.ByteStream(
        file.openRead().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (data, sink) {
              bytesSent += data.length;
              try {
                if (onProgress != null && totalBytes > 0) {
                  final progress = bytesSent / totalBytes;
                  onProgress(progress.clamp(0.0, 1.0));
                }
              } catch (_) {}
              sink.add(data);
            },
          ),
        ),
      );

      final filename = file.path.split(Platform.pathSeparator).last;
      final multipartFile = http.MultipartFile(
        'file',
        stream,
        totalBytes,
        filename: filename,
      );

      final request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(multipartFile);

      debugPrint('Uploading $filename ($totalBytes bytes) to Cloudinary ($cloudName)...');

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        try {
          if (onProgress != null) onProgress(1.0);
        } catch (_) {}
        final secureUrl = data['secure_url'] as String?;
        debugPrint('Cloudinary upload success: $secureUrl');
        return secureUrl;
      } else {
        debugPrint('Cloudinary upload error (${resp.statusCode}): ${resp.body}');
        final errorMsg = _extractErrorMessage(resp.body);
        throw Exception('Cloudinary upload failed (${resp.statusCode}): $errorMsg');
      }
    } catch (e) {
      debugPrint('StorageService.uploadFile exception: $e');
      rethrow;
    }
  }

  /// Convenience helper specifically for profile & task images
  Future<String?> uploadImage(
    File imageFile, {
    void Function(double progress)? onProgress,
  }) {
    return uploadFile(
      imageFile,
      resourceType: 'image',
      onProgress: onProgress,
    );
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final parsed = json.decode(responseBody);
      if (parsed is Map && parsed['error'] is Map) {
        return parsed['error']['message'] ?? responseBody;
      }
    } catch (_) {}
    return responseBody;
  }
}
