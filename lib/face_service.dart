import 'dart:io';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum FaceStatus { ok, noFace, multipleFaces, lookingAway }

class FaceCheckResult {
  final FaceStatus status;
  final int faceCount;

  const FaceCheckResult(this.status, this.faceCount);

  bool get isOk => status == FaceStatus.ok;

  String get message {
    switch (status) {
      case FaceStatus.ok:
        return 'Face check passed';
      case FaceStatus.noFace:
        return 'No face detected';
      case FaceStatus.multipleFaces:
        return 'More than one face detected';
      case FaceStatus.lookingAway:
        return 'Face turned away from the screen';
    }
  }
}

class FaceService {
  CameraController? controller;
  bool _busy = false;
  bool _disposed = false;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
  );

  bool get isReady => controller?.value.isInitialized ?? false;

  Future<void> init() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No camera found on this device');
    }
    final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final c = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await c.initialize();
    controller = c;
  }

  /// Takes one snapshot, analyses it on the device, then deletes it.
  /// Returns null if a previous check is still running.
  Future<FaceCheckResult?> check({double maxYaw = 40}) async {
    if (!isReady || _busy) return null;
    _busy = true;
    XFile? shot;
    try {
      shot = await controller!.takePicture();
      final faces = await _detector
          .processImage(InputImage.fromFilePath(shot.path));

      if (faces.isEmpty) {
        return const FaceCheckResult(FaceStatus.noFace, 0);
      }
      if (faces.length > 1) {
        return FaceCheckResult(FaceStatus.multipleFaces, faces.length);
      }
      final yaw = faces.first.headEulerAngleY ?? 0;
      if (yaw.abs() > maxYaw) {
        return const FaceCheckResult(FaceStatus.lookingAway, 1);
      }
      return const FaceCheckResult(FaceStatus.ok, 1);
    } finally {
      if (shot != null) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
      _busy = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await controller?.dispose();
    controller = null;
    await _detector.close();
  }
}