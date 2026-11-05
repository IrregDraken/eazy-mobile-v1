import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/eazy_theme.dart';
import 'media_service.dart';

/// Shared native crop flow for profile photos and cover banners.
abstract final class EazyProfileImageEditor {
  static Future<MediaUploadDraft?> pickAndCrop({
    required BuildContext context,
    required String kind,
    required String title,
    required CropStyle cropStyle,
    required double aspectRatio,
  }) async {
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 3600,
      maxHeight: 3600,
      imageQuality: 96,
    );
    if (selected == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: selected.path,
      aspectRatio: CropAspectRatio(ratioX: aspectRatio, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      maxWidth: kind == 'cover' ? 2400 : 960,
      maxHeight: kind == 'cover' ? 1100 : 960,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: context.eazyAccent,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: context.eazyAccent,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          cropStyle: cropStyle,
          lockAspectRatio: true,
          showCropGrid: true,
        ),
        IOSUiSettings(
          title: title,
          cropStyle: cropStyle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return null;

    final bytes = await File(cropped.path).readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('The cropped image is empty. Choose another image.');
    }
    if (bytes.length > 25 * 1024 * 1024) {
      throw StateError('Choose an image smaller than 25 MB.');
    }

    return MediaUploadDraft(
      bytes: bytes,
      fileName: 'eazy-$kind.jpg',
      extension: 'jpg',
      contentType: 'image/jpeg',
      kind: kind,
      localPath: cropped.path,
    );
  }
}
