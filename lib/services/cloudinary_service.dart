import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import '../models/media_item.dart';

class MediaValidationException implements Exception {
  final String message;
  MediaValidationException(this.message);
  @override
  String toString() => message;
}

class CloudinaryService {
  static const String cloudName = 'owkkbtpa';
  static const String uploadPreset = 'vibestream_unsigned';

  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxVideoSizeBytes = 100 * 1024 * 1024; // 100 MB
  static const Duration maxVideoDuration = Duration(seconds: 60);
  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<void> validateMedia(String filePath, MediaType type) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaValidationException('File not found.');
    }

    final sizeBytes = await file.length();

    if (type == MediaType.image) {
      if (sizeBytes > maxImageSizeBytes) {
        throw MediaValidationException(
          'Image is too large (${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB). '
          'Max is ${maxImageSizeBytes ~/ (1024 * 1024)} MB.',
        );
      }
      return;
    }

    if (sizeBytes > maxVideoSizeBytes) {
      throw MediaValidationException(
        'Video is too large (${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB). '
        'Max is ${maxVideoSizeBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final controller = VideoPlayerController.file(file);
    try {
      try {
        await controller.initialize();
      } catch (_) {
        throw MediaValidationException(
          'This video could not be read. Try a different file.',
        );
      }

      final duration = controller.value.duration;
      if (duration > maxVideoDuration) {
        throw MediaValidationException(
          'Video is too long (${duration.inSeconds}s). '
          'Max is ${maxVideoDuration.inSeconds}s.',
        );
      }
    } finally {
      await controller.dispose();
    }
  }

  static Future<MediaItem> uploadMedia(String filePath, MediaType type) async {
    await validateMedia(filePath, type);

    final resourceType = type == MediaType.video ? 'video' : 'image';
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset;
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send().timeout(
      uploadTimeout,
      onTimeout:
          () =>
              throw MediaValidationException(
                'Upload timed out. Check your connection and try again.',
              ),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      String message = 'Upload failed. Please try again.';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = (body['error']?['message'] as String?) ?? message;
      } catch (_) {}
      throw MediaValidationException(message);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    String? thumbnailUrl;
    if (type == MediaType.video) {
      final publicId = data['public_id'] as String;
      thumbnailUrl =
          'https://res.cloudinary.com/$cloudName/video/upload/so_0/$publicId.jpg';
    }

    return MediaItem(
      url: data['secure_url'] as String,
      type: type,
      thumbnailUrl: thumbnailUrl,
      publicId: data['public_id'] as String?,
    );
  }
}
