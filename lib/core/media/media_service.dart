import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class MediaUpload {
  const MediaUpload({
    required this.path,
    required this.contentType,
    required this.kind,
    required this.byteSize,
    required this.fileName,
    this.localPath,
  });
  final String path;
  final String contentType;
  final String kind;
  final int byteSize;
  final String fileName;
  final String? localPath;
}

class EazyMediaService {
  EazyMediaService(this.api);
  final ApiClient api;
  final ImagePicker picker = ImagePicker();

  Future<MediaUpload?> pickAndUploadVideo({required String kind}) async {
    final file = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (file == null) return null;
    final extension = file.name.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'mov' => 'video/quicktime',
      'mp4' || 'm4v' => 'video/mp4',
      _ => '',
    };
    if (contentType.isEmpty) {
      throw const ApiException(
        'Choose an MP4 or MOV video.',
        kind: ApiErrorKind.validation,
      );
    }
    final result = await api.post(
      'media/upload-url',
      auth: true,
      body: {'contentType': contentType, 'extension': extension, 'kind': kind},
    );
    final signedUrl = result['signedUrl']?.toString();
    final path = result['path']?.toString();
    if (signedUrl == null ||
        path == null ||
        signedUrl.isEmpty ||
        path.isEmpty) {
      throw const ApiException(
        'Eazy could not prepare media storage.',
        kind: ApiErrorKind.provider,
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      throw const ApiException(
        'Choose a file smaller than 25 MB.',
        kind: ApiErrorKind.validation,
      );
    }
    await api.uploadBytes(signedUrl, bytes, contentType);
    return MediaUpload(
      path: path,
      contentType: contentType,
      kind: kind,
      byteSize: bytes.length,
      fileName: file.name,
    );
  }

  Future<MediaUpload?> pickAndUpload({required String kind, ImageSource source = ImageSource.gallery}) async {
    final file = await picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
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
      throw const ApiException(
        'Choose a JPG, PNG, WebP or GIF image.',
        kind: ApiErrorKind.validation,
      );
    }

    final result = await api.post(
      'media/upload-url',
      auth: true,
      body: {'contentType': contentType, 'extension': extension, 'kind': kind},
    );
    final signedUrl = result['signedUrl']?.toString();
    final path = result['path']?.toString();
    if (signedUrl == null ||
        path == null ||
        signedUrl.isEmpty ||
        path.isEmpty) {
      throw const ApiException(
        'Eazy could not prepare media storage.',
        kind: ApiErrorKind.provider,
      );
    }

    final Uint8List bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      throw const ApiException(
        'Choose a file smaller than 25 MB.',
        kind: ApiErrorKind.validation,
      );
    }
    await api.uploadBytes(signedUrl, bytes, contentType);
    return MediaUpload(
      path: path,
      contentType: contentType,
      kind: kind,
      byteSize: bytes.length,
      fileName: file.name,
      localPath: file.path,
    );
  }

  Future<MediaUpload?> pickAndUploadDocument({required String kind}) async {
    const group = XTypeGroup(
      label: 'Documents and files',
      extensions: ['pdf', 'txt', 'csv', 'doc', 'docx'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    final extension = file.name.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => '',
    };
    if (contentType.isEmpty) {
      throw const ApiException(
        'Choose a PDF, TXT, CSV, DOC or DOCX file.',
        kind: ApiErrorKind.validation,
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      throw const ApiException(
        'Choose a file smaller than 25 MB.',
        kind: ApiErrorKind.validation,
      );
    }
    final result = await api.post(
      'media/upload-url',
      auth: true,
      body: {'contentType': contentType, 'extension': extension, 'kind': kind},
    );
    final signedUrl = result['signedUrl']?.toString();
    final path = result['path']?.toString();
    if (signedUrl == null ||
        path == null ||
        signedUrl.isEmpty ||
        path.isEmpty) {
      throw const ApiException(
        'Eazy could not prepare file storage.',
        kind: ApiErrorKind.provider,
      );
    }
    await api.uploadBytes(signedUrl, bytes, contentType);
    return MediaUpload(
      path: path,
      contentType: contentType,
      kind: kind,
      byteSize: bytes.length,
      fileName: file.name,
    );
  }
}
