import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'exam_taking_screen.dart';
import 'face_service.dart';

class FaceCheckScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final int durationMinutes;
  final List<dynamic> questions;
  final String courseId;
  final String courseName;

  const FaceCheckScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.durationMinutes,
    required this.questions,
    required this.courseId,
    required this.courseName,
  });

  @override
  State<FaceCheckScreen> createState() => _FaceCheckScreenState();
}

class _FaceCheckScreenState extends State<FaceCheckScreen> {
  final FaceService _face = FaceService();
  bool _starting = true;
  bool _checking = false;
  String? _error;
  String _message =
      'Look straight at the camera, keep your face inside the frame, then tap the button.';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _face.init();
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error =
          'Camera unavailable. Allow camera permission, then go back and try again.\n\n$e';
        });
      }
    }
  }

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _message = 'Checking...';
    });

    try {
      final result = await _face.check(maxYaw: 25);
      if (!mounted) return;

      if (result == null || !result.isOk) {
        setState(() {
          _checking = false;
          _message = result == null
              ? 'Please try again.'
              : '${result.message}. Please try again.';
        });
        return;
      }

      // Release the camera so the exam screen can use it.
      await _face.dispose();
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ExamTakingScreen(
            examId: widget.examId,
            examTitle: widget.examTitle,
            durationMinutes: widget.durationMinutes,
            questions: widget.questions,
            courseId: widget.courseId,
            courseName: widget.courseName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _message = 'Could not check your face: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _face.dispose();
    super.dispose();
  }

  Widget _buildPreview() {
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
    final ready = !_starting && _error == null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Identity Check'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                widget.examTitle,
                textAlign: TextAlign.center,
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.courseName,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              _buildPreview(),
              const SizedBox(height: 16),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (ready && !_checking) ? _verify : null,
                  icon: _checking
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : const Icon(Icons.verified_user),
                  label: Text(_checking ? 'Checking...' : 'Verify & Start Exam'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'During the exam the camera takes a snapshot every 20 seconds. '
                    'Snapshots are analysed on your phone and deleted immediately. '
                    'They are never uploaded. You get 3 warnings; after that the exam is submitted automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}