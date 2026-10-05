import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class MediaUpload {
  const MediaUpload({required this.path, required this.contentType, required this.kind});
  final String path;
  final String contentType;
  final String kind;
}

class EazyMediaService {
  EazyMediaService(this.api);
  final ApiClient api;
  final ImagePicker picker = ImagePicker();

  Future<MediaUpload?> pickAndUpload({required String kind}) async {
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2400);
    if (file == null) return null;
    final extension = file.name.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => '',
    };
    if (contentType.isEmpty) {
      throw const ApiException('Choose a JPG, PNG, WebP or GIF image.', kind: ApiErrorKind.validation);
    }

    final result = await api.post(
      'media/upload-url',
      auth: true,
      body: {'contentType': contentType, 'extension': extension, 'kind': kind},
    );
    final signedUrl = result['signedUrl']?.toString();
    final path = result['path']?.toString();
    if (signedUrl == null || path == null || signedUrl.isEmpty || path.isEmpty) {
      throw const ApiException('Eazy could not prepare media storage.', kind: ApiErrorKind.provider);
    }

    final Uint8List bytes = await file.readAsBytes();
    await api.uploadBytes(signedUrl, bytes, contentType);
    return MediaUpload(path: path, contentType: contentType, kind: kind);
  }
}
