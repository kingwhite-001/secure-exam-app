import 'dart:io';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_embedder.dart';

enum FaceStatus { ok, noFace, multipleFaces, lookingAway, mismatch }

class FaceCheckResult {
  final FaceStatus status;
  final int faceCount;
  final double? similarity;
  final List<double>? embedding;

  const FaceCheckResult(
      this.status,
      this.faceCount, {
        this.similarity,
        this.embedding,
      });

  bool get isOk => status == FaceStatus.ok;

  /// True if the check should let the student continue.
  /// A mismatch only blocks when FaceService.enforceMatch is on.
  bool get passes =>
      isOk || (status == FaceStatus.mismatch && !FaceService.enforceMatch);

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
      case FaceStatus.mismatch:
        return 'Face does not match the registered student';
    }
  }
}

class FaceService {
  /// Placeholder. We set this from real test numbers.
  static const double matchThreshold = 0.60;

  /// false = monitor-only: match scores are recorded but never block or
  /// penalise anyone. Switch to true after calibrating on a real phone.
  static const bool enforceMatch = false;

  CameraController? controller;
  bool _busy = false;
  bool _disposed = false;
  final FaceEmbedder _embedder = FaceEmbedder();

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
  Future<FaceCheckResult?> check({
    double maxYaw = 40,
    List<double>? reference,
    bool wantEmbedding = false,
  }) async {
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

      final face = faces.first;
      final yaw = face.headEulerAngleY ?? 0;
      if (yaw.abs() > maxYaw) {
        return const FaceCheckResult(FaceStatus.lookingAway, 1);
      }

      if (reference == null && !wantEmbedding) {
        return const FaceCheckResult(FaceStatus.ok, 1);
      }

      List<double>? emb;
      try {
        emb = await _embedder.embed(shot.path, face.boundingBox);
      } catch (_) {
        // Enrolment or enforced matching: show the real error.
        if (reference == null || enforceMatch) rethrow;
        // Monitor-only: fall back to the plain presence check.
      }
      if (emb == null) return const FaceCheckResult(FaceStatus.ok, 1);

      if (reference != null) {
        final sim = FaceEmbedder.cosine(emb, reference);
        return FaceCheckResult(
          sim < matchThreshold ? FaceStatus.mismatch : FaceStatus.ok,
          1,
          similarity: sim,
          embedding: emb,
        );
      }
      return FaceCheckResult(FaceStatus.ok, 1, embedding: emb);
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
    _embedder.dispose();
    await _detector.close();
  }
}