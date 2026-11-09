import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'face_service.dart';

class ExamTakingScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final int durationMinutes;
  final List<dynamic> questions;
  final String courseId;
  final String courseName;
  final List<double>? reference;

  const ExamTakingScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.durationMinutes,
    required this.questions,
    required this.courseId,
    required this.courseName,
    this.reference,
  });

  @override
  State<ExamTakingScreen> createState() => _ExamTakingScreenState();
}

class _ExamTakingScreenState extends State<ExamTakingScreen>
    with WidgetsBindingObserver {
  static const int _maxStrikes = 3;
  static const Duration _checkInterval = Duration(seconds: 20);

  int _currentIndex = 0;
  final Map<int, String> _selectedAnswers = {};
  late int _remainingSeconds;
  Timer? _timer;
  Timer? _monitorTimer;
  bool _isSubmitting = false;
  bool _examSubmitted = false;

  // Monitoring
  final FaceService _face = FaceService();
  bool _cameraReady = false;
  int _strikes = 0;
  int _cameraFailures = 0;
  final List<String> _flags = [];
  final List<double> _similarities = [];
  String? _warning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remainingSeconds = widget.durationMinutes * 60;
    _startTimer();
    _startMonitoring();
  }

  // ---------------- TIMER ----------------
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _submitExam(autoSubmit: true);
      } else {
        if (mounted) setState(() => _remainingSeconds--);
      }
    });
  }

  String get _timerDisplay {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    if (_remainingSeconds <= 60) return Colors.red;
    if (_remainingSeconds <= 300) return Colors.orange;
    return Colors.white;
  }

  // ---------------- MONITORING ----------------
  Future<void> _startMonitoring() async {
    _monitorTimer = Timer.periodic(_checkInterval, (_) => _runFaceCheck());
    try {
      await _face.init();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      _registerStrike('Camera could not be started');
    }
  }

  Future<void> _runFaceCheck() async {
    if (_examSubmitted || _isSubmitting || !mounted) return;

    if (!_face.isReady) {
      _cameraFailures++;
      if (_cameraFailures >= 2) {
        _cameraFailures = 0;
        _registerStrike('Camera unavailable');
      }
      return;
    }

    try {
      final result =
      await _face.check(maxYaw: 40, reference: widget.reference);
      if (result == null) return;
      _cameraFailures = 0;
      if (result.similarity != null) _similarities.add(result.similarity!);

      if (result.status == FaceStatus.mismatch) {
        if (FaceService.enforceMatch) {
          _registerStrike(result.message, similarity: result.similarity);
        } else {
          _logEvent(
            'Face match below threshold (monitor-only)',
            similarity: result.similarity,
            countsAsStrike: false,
          );
        }
      } else if (!result.isOk) {
        _registerStrike(result.message);
      }
    } catch (_) {
      _cameraFailures++;
      if (_cameraFailures >= 2) {
        _cameraFailures = 0;
        _registerStrike('Camera unavailable');
      }
    }
  }

  void _registerStrike(String reason, {double? similarity}) {
    if (_examSubmitted || _isSubmitting || !mounted) return;
    _strikes++;
    _flags.add(reason);
    _logEvent(reason, similarity: similarity);
    setState(() => _warning = 'Warning $_strikes of $_maxStrikes: $reason');
    if (_strikes >= _maxStrikes) {
      _submitExam(autoSubmit: true, terminated: true);
    }
  }

  Future<void> _logEvent(
      String reason, {
        double? similarity,
        bool countsAsStrike = true,
      }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('exam_events').add({
        'studentId': user.uid,
        'examId': widget.examId,
        'examTitle': widget.examTitle,
        'courseId': widget.courseId,
        'reason': reason,
        'strike': countsAsStrike ? _strikes : 0,
        'countsAsStrike': countsAsStrike,
        'similarity': similarity,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _registerStrike('Left the exam app');
    }
  }

  // ---------------- SUBMIT ----------------
  Future<void> _submitExam({
    bool autoSubmit = false,
    bool terminated = false,
  }) async {
    if (_isSubmitting || _examSubmitted) return;

    if (!autoSubmit) {
      final unanswered = widget.questions.length - _selectedAnswers.length;
      if (unanswered > 0) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Submit Exam?'),
            content: Text(
              '$unanswered question(s) unanswered. Are you sure you want to submit?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        if (_isSubmitting || _examSubmitted) return;
      }
    }

    _timer?.cancel();
    _monitorTimer?.cancel();
    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      int correct = 0;
      for (int i = 0; i < widget.questions.length; i++) {
        final q = widget.questions[i] as Map<String, dynamic>;
        final selected = _selectedAnswers[i];
        final answer = q['correctAnswer']?.toString().trim().toUpperCase();
        if (selected != null && selected == answer) correct++;
      }

      final total = widget.questions.length;
      final percentage = total > 0 ? (correct / total * 100).round() : 0;
      final timeTaken = widget.durationMinutes * 60 - _remainingSeconds;

      double? simMin;
      double? simAvg;
      if (_similarities.isNotEmpty) {
        simMin = _similarities.reduce((a, b) => a < b ? a : b);
        simAvg = _similarities.reduce((a, b) => a + b) / _similarities.length;
      }

      await FirebaseFirestore.instance.collection('exam_results').add({
        'examId': widget.examId,
        'examTitle': widget.examTitle,
        'courseId': widget.courseId,
        'courseName': widget.courseName,
        'studentId': user.uid,
        'score': correct,
        'total': total,
        'percentage': percentage,
        'timeTakenSeconds': timeTaken,
        'answers': _selectedAnswers.map((k, v) => MapEntry(k.toString(), v)),
        'submittedAt': FieldValue.serverTimestamp(),
        'autoSubmitted': autoSubmit,
        'strikes': _strikes,
        'flags': _flags,
        'terminatedForViolations': terminated,
        'faceChecks': _similarities.length,
        'faceMatchMin': simMin,
        'faceMatchAvg': simAvg,
        'faceMatchEnforced': FaceService.enforceMatch,
      });

      if (mounted) {
        setState(() {
          _examSubmitted = true;
          _isSubmitting = false;
        });
        _showResultScreen(correct, total, percentage, terminated);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting exam: $e')),
        );
      }
    }
  }

  void _showResultScreen(
      int correct, int total, int percentage, bool terminated) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          terminated ? 'Exam Ended' : 'Exam Submitted!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (terminated) ...[
              Text(
                'Your exam was submitted automatically after $_maxStrikes integrity warnings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: percentage >= 50 ? const Color(0xFF2E7D32) : Colors.red,
              ),
              child: Center(
                child: Text(
                  '$percentage%',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('$correct out of $total correct',
                style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              ),
              child: const Text('Back to Dashboard'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _monitorTimer?.cancel();
    _face.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------
  Widget _statusStrip() {
    final clean = _strikes == 0;
    return Container(
      width: double.infinity,
      color: clean ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.videocam,
              size: 16, color: _cameraReady ? Colors.green : Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _warning ??
                  (_cameraReady
                      ? 'Camera monitoring active'
                      : 'Starting camera...'),
              style: TextStyle(
                fontSize: 12,
                color: clean ? Colors.green.shade800 : Colors.orange.shade900,
              ),
            ),
          ),
          Text(
            'Warnings $_strikes/$_maxStrikes',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.questions;

    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Exam'),
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('This exam has no questions.')),
      );
    }

    final q = questions[_currentIndex] as Map<String, dynamic>;
    final options = {
      'A': q['optionA']?.toString() ?? '',
      'B': q['optionB']?.toString() ?? '',
      'C': q['optionC']?.toString() ?? '',
      'D': q['optionD']?.toString() ?? '',
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave Exam?'),
            content: const Text(
                'If you leave now your progress is lost and you will NOT be able to retake this exam. Are you sure?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (leave == true && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.examTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              Text(widget.courseName,
                  style:
                  const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _timerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer, color: _timerColor, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _timerDisplay,
                    style: TextStyle(
                      color: _timerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _statusStrip(),
            LinearProgressIndicator(
              value: (_currentIndex + 1) / questions.length,
              backgroundColor: Colors.grey.shade300,
              valueColor:
              const AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
              minHeight: 4,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Question ${_currentIndex + 1} of ${questions.length}',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${_selectedAnswers.length} answered',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        q['question']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...options.entries.map((entry) {
                      final isSelected =
                          _selectedAnswers[_currentIndex] == entry.key;
                      return GestureDetector(
                        onTap: () => setState(
                                () => _selectedAnswers[_currentIndex] = entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF1565C0)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF1565C0)
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF1565C0)
                                      .withValues(alpha: 0.1),
                                ),
                                child: Center(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(questions.length, (i) {
                        final answered = _selectedAnswers.containsKey(i);
                        final isCurrent = i == _currentIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _currentIndex = i),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCurrent
                                  ? const Color(0xFF1565C0)
                                  : answered
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey.shade300,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: (isCurrent || answered)
                                      ? Colors.white
                                      : Colors.black54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (_currentIndex > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _currentIndex--),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  if (_currentIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _currentIndex < questions.length - 1
                        ? ElevatedButton.icon(
                      onPressed: () => setState(() => _currentIndex++),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                        : ElevatedButton.icon(
                      onPressed:
                      _isSubmitting ? null : () => _submitExam(),
                      icon: _isSubmitting
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                          : const Icon(Icons.check_circle),
                      label: Text(
                          _isSubmitting ? 'Submitting...' : 'Submit Exam'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}