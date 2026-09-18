import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ExamTakingScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final int durationMinutes;
  final List<dynamic> questions;
  final String courseId;
  final String courseName;

  const ExamTakingScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.durationMinutes,
    required this.questions,
    required this.courseId,
    required this.courseName,
  });

  @override
  State<ExamTakingScreen> createState() => _ExamTakingScreenState();
}

class _ExamTakingScreenState extends State<ExamTakingScreen> {
  int _currentIndex = 0;
  Map<int, String> _selectedAnswers = {};
  late int _remainingSeconds;
  Timer? _timer;
  bool _isSubmitting = false;
  bool _examSubmitted = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.durationMinutes * 60;
    _startTimer();
  }

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
    return const Color(0xFF1565C0);
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
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
      }
    }

    _timer?.cancel();
    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Calculate score
      int correct = 0;
      for (int i = 0; i < widget.questions.length; i++) {
        final q = widget.questions[i] as Map<String, dynamic>;
        final selected = _selectedAnswers[i];
        final answer = q['correctAnswer']?.toString().toUpperCase();
        if (selected != null && selected == answer) correct++;
      }

      final total = widget.questions.length;
      final percentage = total > 0 ? (correct / total * 100).round() : 0;
      final timeTaken = widget.durationMinutes * 60 - _remainingSeconds;

      // Save result to Firestore
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
        'answers': _selectedAnswers.map(
              (k, v) => MapEntry(k.toString(), v),
        ),
        'submittedAt': FieldValue.serverTimestamp(),
        'autoSubmitted': autoSubmit,
      });

      if (mounted) {
        setState(() {
          _examSubmitted = true;
          _isSubmitting = false;
        });
        _showResultScreen(correct, total, percentage);
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

  void _showResultScreen(int correct, int total, int percentage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Exam Submitted!',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: percentage >= 50
                    ? const Color(0xFF2E7D32)
                    : Colors.red,
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
            Text(
              '$correct out of $total correct',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              percentage >= 70
                  ? '🎉 Excellent work!'
                  : percentage >= 50
                  ? '👍 Good effort!'
                  : '📚 Keep studying!',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // go back to dashboard
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
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.questions;
    final q = questions[_currentIndex] as Map<String, dynamic>;
    final options = {
      'A': q['optionA']?.toString() ?? '',
      'B': q['optionB']?.toString() ?? '',
      'C': q['optionC']?.toString() ?? '',
      'D': q['optionD']?.toString() ?? '',
    };

    return WillPopScope(
      onWillPop: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave Exam?'),
            content: const Text(
              'If you leave now your progress will be lost. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        return confirm ?? false;
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
              Text(
                widget.examTitle,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                widget.courseName,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            // Timer
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _timerColor.withOpacity(0.2),
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
            // Progress bar
            LinearProgressIndicator(
              value: (_currentIndex + 1) / questions.length,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1565C0)),
              minHeight: 4,
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question counter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Question ${_currentIndex + 1} of ${questions.length}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_selectedAnswers.length} answered',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Question text
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
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
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Options
                    ...options.entries.map((entry) {
                      final isSelected =
                          _selectedAnswers[_currentIndex] == entry.key;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAnswers[_currentIndex] = entry.key;
                          });
                        },
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
                            boxShadow: [
                              BoxShadow(
                                color:
                                Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
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
                                      .withOpacity(0.1),
                                ),
                                child: Center(
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? const Color(0xFF1565C0)
                                          : const Color(0xFF1565C0),
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

                    // Question navigator dots
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(questions.length, (i) {
                        final answered = _selectedAnswers.containsKey(i);
                        final isCurrent = i == _currentIndex;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _currentIndex = i),
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

            // Bottom navigation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Previous
                  if (_currentIndex > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(
                                () => _currentIndex--),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (_currentIndex > 0) const SizedBox(width: 12),

                  // Next or Submit
                  Expanded(
                    child: _currentIndex < questions.length - 1
                        ? ElevatedButton.icon(
                      onPressed: () => setState(
                              () => _currentIndex++),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(10),
                        ),
                      ),
                    )
                        : ElevatedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _submitExam(),
                      icon: _isSubmitting
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.check_circle),
                      label: Text(_isSubmitting
                          ? 'Submitting...'
                          : 'Submit Exam'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(10),
                        ),
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