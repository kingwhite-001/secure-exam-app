import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'face_embedder.dart';
import 'face_service.dart';

class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  final FaceService _face = FaceService();
  bool _starting = true;
  bool _busy = false;
  String? _error;
  List<double>? _template;
  String _message =
      'Sit in good light, look straight at the camera, then tap Capture.';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final raw = doc.data()?['faceTemplate'];
        if (raw is List && raw.isNotEmpty) {
          _template = raw.map((e) => (e as num).toDouble()).toList();
        }
      }
      await _face.init();
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Camera unavailable. Allow camera permission and try again.\n\n$e';
        });
      }
    }
  }

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _message = 'Hold still...';
    });
    try {
      final shots = <List<double>>[];
      for (var i = 0; i < 3; i++) {
        if (!mounted) return;
        setState(() => _message = 'Capturing ${i + 1} of 3. Hold still.');
        final r = await _face.check(maxYaw: 20, wantEmbedding: true);
        if (!mounted) return;
        if (r == null || !r.isOk || r.embedding == null) {
          setState(() {
            _busy = false;
            _message = '${r?.message ?? 'Camera busy'}. Please try again.';
          });
          return;
        }
        shots.add(r.embedding!);
        await Future.delayed(const Duration(milliseconds: 800));
      }

      final template = FaceEmbedder.average(shots);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'faceTemplate': template,
        'faceEnrolledAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _template = template;
        _busy = false;
        _message = 'Face saved. Tap "Test match" to see how well it recognises you.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Could not save your face: $e';
        });
      }
    }
  }

  Future<void> _testMatch() async {
    final t = _template;
    if (t == null) return;
    setState(() {
      _busy = true;
      _message = 'Testing...';
    });
    try {
      final r = await _face.check(maxYaw: 40, reference: t);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (r == null) {
          _message = 'Camera busy. Try again.';
        } else if (r.similarity != null) {
          _message =
          'Similarity: ${r.similarity!.toStringAsFixed(2)}\n'
              '${r.isOk ? 'MATCH' : 'NO MATCH'} (threshold ${FaceService.matchThreshold})';
        } else {
          _message = '${r.message}. Try again.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Test failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _face.dispose();
    super.dispose();
  }

  Widget _preview() {
    if (_starting) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red.shade800),
        ),
      );
    }
    final c = _face.controller!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 260,
        child: AspectRatio(
          aspectRatio: 1 / c.value.aspectRatio,
          child: CameraPreview(c),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_starting && _error == null && !_busy;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Face Enrolment'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _template != null
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _template != null ? 'Face enrolled' : 'Not enrolled yet',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _template != null
                        ? Colors.green.shade800
                        : Colors.orange.shade900,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _preview(),
              const SizedBox(height: 16),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: ready ? _capture : null,
                  icon: const Icon(Icons.face),
                  label: Text(_template == null
                      ? 'Capture & Save My Face'
                      : 'Re-capture My Face'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (ready && _template != null) ? _testMatch : null,
                  icon: const Icon(Icons.compare),
                  label: const Text('Test match'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}