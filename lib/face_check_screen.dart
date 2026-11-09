import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'exam_taking_screen.dart';
import 'face_enroll_screen.dart';
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
  bool _needsEnrol = false;
  String? _error;
  List<double>? _template;
  String _message =
      'Look straight at the camera, keep your face inside the frame, then tap the button.';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final db = FirebaseFirestore.instance;

      // One attempt per exam.
      final attempt = await db
          .collection('exam_attempts')
          .doc('${user.uid}_${widget.examId}')
          .get();
      final done = await db
          .collection('exam_results')
          .where('studentId', isEqualTo: user.uid)
          .where('examId', isEqualTo: widget.examId)
          .limit(1)
          .get();
      if (attempt.exists || done.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _starting = false;
            _error =
            'You have already started or completed this exam. Only one attempt is allowed. '
                'If something went wrong, contact your lecturer.';
          });
        }
        return;
      }

      // Saved face template (if the student has enrolled).
      final profile = await db.collection('users').doc(user.uid).get();
      final raw = profile.data()?['faceTemplate'];
      if (raw is List && raw.isNotEmpty) {
        _template = raw.map((e) => (e as num).toDouble()).toList();
      }

      if (FaceService.enforceMatch && _template == null) {
        if (mounted) {
          setState(() {
            _starting = false;
            _needsEnrol = true;
          });
        }
        return;
      }

      await _face.init();
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error =
          'Could not start the identity check. Check your internet and camera permission, then go back and try again.\n\n$e';
        });
      }
    }
  }

  Future<void> _enrolNow() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FaceEnrollScreen()),
    );
    if (!mounted) return;
    setState(() {
      _starting = true;
      _needsEnrol = false;
      _error = null;
    });
    await _initCamera();
  }

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _message = 'Checking...';
    });

    try {
      final result = await _face.check(maxYaw: 25, reference: _template);
      if (!mounted) return;

      if (result == null || !result.passes) {
        setState(() {
          _checking = false;
          _message = result == null
              ? 'Please try again.'
              : '${result.message}. Please try again.';
        });
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      // Lock the attempt before the exam opens.
      await FirebaseFirestore.instance
          .collection('exam_attempts')
          .doc('${user.uid}_${widget.examId}')
          .set({
        'studentId': user.uid,
        'examId': widget.examId,
        'startedAt': FieldValue.serverTimestamp(),
        'startSimilarity': result.similarity,
      });

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
            reference: _template,
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
    if (_needsEnrol) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              'You have not enrolled your face yet. Enrol once, then you can take exams.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange.shade900),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _enrolNow,
              icon: const Icon(Icons.face),
              label: const Text('Enrol my face'),
            ),
          ],
        ),
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
    final ready = !_starting && _error == null && !_needsEnrol;

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
              if (ready && _template == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Tip: enrol your face from the menu (Face Enrolment) to switch on identity matching.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ],
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
                  label:
                  Text(_checking ? 'Checking...' : 'Verify & Start Exam'),
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
                'You have ONE attempt at this exam. During the exam the camera takes a snapshot '
                    'every 20 seconds. Snapshots are analysed on your phone and deleted immediately; '
                    'they are never uploaded. You get 3 warnings; after that the exam is submitted automatically.',
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