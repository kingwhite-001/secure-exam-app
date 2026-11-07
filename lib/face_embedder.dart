import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Runs in a background isolate: read photo, crop the face, resize to 112x112.
Float32List _prepareFace(Map<String, dynamic> args) {
  final String path = args['path'] as String;
  final double left = args['left'] as double;
  final double top = args['top'] as double;
  final double width = args['width'] as double;
  final double height = args['height'] as double;

  var photo = img.decodeImage(File(path).readAsBytesSync());
  if (photo == null) throw Exception('Could not read the photo');
  photo = img.bakeOrientation(photo);

  final cx = left + width / 2;
  final cy = top + height / 2;
  var side = (math.max(width, height) * 1.2).round();
  side = math.min(side, math.min(photo.width, photo.height));
  final x = (cx - side / 2).round().clamp(0, photo.width - side).toInt();
  final y = (cy - side / 2).round().clamp(0, photo.height - side).toInt();

  final face = img.copyResize(
    img.copyCrop(photo, x: x, y: y, width: side, height: side),
    width: 112,
    height: 112,
    interpolation: img.Interpolation.linear,
  );

  final out = Float32List(112 * 112 * 3);
  var i = 0;
  for (var py = 0; py < 112; py++) {
    for (var px = 0; px < 112; px++) {
      final p = face.getPixel(px, py);
      out[i++] = (p.r - 127.5) / 128.0;
      out[i++] = (p.g - 127.5) / 128.0;
      out[i++] = (p.b - 127.5) / 128.0;
    }
  }
  return out;
}

class FaceEmbedder {
  Interpreter? _interpreter;

  Future<void> _load() async {
    _interpreter ??=
    await Interpreter.fromAsset('assets/models/mobile_face_net.tflite');
  }

  /// Turns the face inside [box] on the photo at [photoPath] into 192 numbers.
  Future<List<double>> embed(String photoPath, Rect box) async {
    await _load();
    final pixels = await compute(_prepareFace, <String, dynamic>{
      'path': photoPath,
      'left': box.left,
      'top': box.top,
      'width': box.width,
      'height': box.height,
    });

    final input = [
      List.generate(
        112,
            (y) => List.generate(112, (x) {
          final i = (y * 112 + x) * 3;
          return [pixels[i], pixels[i + 1], pixels[i + 2]];
        }),
      ),
    ];
    final output = [List<double>.filled(192, 0.0)];
    _interpreter!.run(input, output);
    return normalize(output[0]);
  }

  static List<double> normalize(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  /// Both inputs must already be normalised. 1.0 = identical, 0 = unrelated.
  static double cosine(List<double> a, List<double> b) {
    var dot = 0.0;
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  static List<double> average(List<List<double>> items) {
    final sum = List<double>.filled(items.first.length, 0.0);
    for (final e in items) {
      for (var i = 0; i < sum.length; i++) {
        sum[i] += e[i];
      }
    }
    return normalize(sum);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}