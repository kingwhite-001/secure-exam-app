import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ExamTakingScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ExamTakingScreen({
    super.key,
    required this.exam,
  });

  @override
  State<ExamTakingScreen> createState() => _ExamTakingScreenState();
}

class _ExamTakingScreenState extends State<ExamTakingScreen> {
  late List<Map<String, dynamic>> _questions;

  final Map<int, String> _answers = {};

  int _currentQuestion = 0;
  int _remainingSeconds = 0;

  Timer? _timer;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();

    final rawQuestions = widget.exam['questions'] as List? ?? [];

    _questions = rawQuestions.map<Map<String, dynamic>>((question) {
      return Map<String, dynamic>.from(question as Map);
    }).toList();

    final duration = widget.exam['durationMinutes'] ?? 30;

    _remainingSeconds = (duration is int)
        ? duration * 60
        : (int.tryParse(duration.toString()) ?? 30) * 60;

    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _submitExam(autoSubmit: true);
        return;
      }

      setState(() {
        _remainingSeconds--;
      });
    });
  }

  String _formatTime() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _selectAnswer(String answer) {
    setState(() {
      _answers[_currentQuestion] = answer;
    });
  }

  void _nextQuestion() {
    if (_currentQuestion < _questions.length - 1) {
      setState(() {
        _currentQuestion++;
      });
    }
  }

  void _previousQuestion() {
    if (_currentQuestion > 0) {
      setState(() {
        _currentQuestion--;
      });
    }
  }

  void _goToQuestion(int index) {
    setState(() {
      _currentQuestion = index;
    });
  }

  Future<void> _confirmSubmit() async {
    final unanswered =
        _questions.length - _answers.length;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Submit Exam?'),
          content: Text(
            unanswered > 0
                ? 'You have $unanswered unanswered question(s). Are you sure you want to submit?'
                : 'You have answered all questions. Are you ready to submit?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continue Exam'),
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
        );
      },
    );

    if (shouldSubmit == true) {
      await _submitExam();
    }
  }

  Future<void> _submitExam({
    bool autoSubmit = false,
  }) async {
    if (_isSubmitting) return;

    _isSubmitting = true;
    _timer?.cancel();

    int score = 0;

    for (int i = 0; i < _questions.length; i++) {
      final question = _questions[i];

      final correctAnswer =
      question['correctAnswer']?.toString().trim().toUpperCase();

      final selectedAnswer =
      _answers[i]?.trim().toUpperCase();

      if (correctAnswer != null &&
          selectedAnswer != null &&
          correctAnswer == selectedAnswer) {
        score++;
      }
    }

    final totalQuestions = _questions.length;

    final percentage = totalQuestions == 0
        ? 0
        : ((score / totalQuestions) * 100).round();

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await FirebaseFirestore.instance.collection('results').add({
          'studentId': user.uid,
          'examId': widget.exam['examId'],
          'examTitle': widget.exam['title'] ?? 'Untitled Exam',
          'courseId': widget.exam['courseId'],
          'courseName': widget.exam['courseName'],
          'score': score,
          'totalQuestions': totalQuestions,
          'percentage': percentage,
          'answers': _answers.map(
                (key, value) => MapEntry(key.toString(), value),
          ),
          'submittedAt': FieldValue.serverTimestamp(),
          'autoSubmitted': autoSubmit,
        });
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  autoSubmit
                      ? 'Time Up!'
                      : 'Exam Submitted',
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Text(
                  '$score / $totalQuestions',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your result has been submitted.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          );
        },
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _isSubmitting = false;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not submit exam: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildTimer() {
    final isLowTime = _remainingSeconds <= 60;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isLowTime
            ? Colors.red.shade50
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 20,
            color: isLowTime ? Colors.red : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            _formatTime(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isLowTime ? Colors.red : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionNumberGrid() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          _questions.length,
              (index) {
            final isCurrent =
                index == _currentQuestion;

            final isAnswered =
            _answers.containsKey(index);

            return GestureDetector(
              onTap: () => _goToQuestion(index),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? const Color(0xFF1565C0)
                      : isAnswered
                      ? Colors.green.shade100
                      : Colors.grey.shade100,
                  borderRadius:
                  BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent
                        ? const Color(0xFF1565C0)
                        : isAnswered
                        ? Colors.green
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCurrent
                        ? Colors.white
                        : isAnswered
                        ? Colors.green.shade800
                        : Colors.black87,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOption({
    required String letter,
    required String text,
  }) {
    final selected =
        _answers[_currentQuestion] == letter;

    return GestureDetector(
      onTap: () => _selectAnswer(letter),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE3F2FD)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF1565C0)
                : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1565C0)
                    : Colors.grey.shade200,
                borderRadius:
                BorderRadius.circular(8),
              ),
              child: Text(
                letter,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF1565C0),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Exam'),
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'This exam has no questions.',
          ),
        ),
      );
    }

    final question = _questions[_currentQuestion];

    final questionText =
        question['question']?.toString() ?? '';

    final optionA =
        question['optionA']?.toString() ?? '';

    final optionB =
        question['optionB']?.toString() ?? '';

    final optionC =
        question['optionC']?.toString() ?? '';

    final optionD =
        question['optionD']?.toString() ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) async {
        if (didPop) return;

        final leave = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Leave Exam?'),
              content: const Text(
                'Your exam is currently in progress. '
                    'Leaving may cause you to lose your progress.',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: const Text('Stay'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, true),
                  child: const Text('Leave'),
                ),
              ],
            );
          },
        );

        if (leave == true && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Text(
            widget.exam['title'] ??
                'Exam',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding:
              const EdgeInsets.only(right: 12),
              child: _buildTimer(),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding:
                  const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Question ${_currentQuestion + 1} of ${_questions.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color:
                          Color(0xFF1565C0),
                        ),
                      ),

                      const SizedBox(height: 8),

                      LinearProgressIndicator(
                        value:
                        (_currentQuestion + 1) /
                            _questions.length,
                        minHeight: 6,
                        borderRadius:
                        BorderRadius.circular(10),
                        backgroundColor:
                        Colors.grey.shade300,
                        valueColor:
                        const AlwaysStoppedAnimation<
                            Color>(
                          Color(0xFF1565C0),
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildQuestionNumberGrid(),

                      const SizedBox(height: 24),

                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                          BorderRadius.circular(14),
                          border: Border.all(
                            color:
                            Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          questionText,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight:
                            FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildOption(
                        letter: 'A',
                        text: optionA,
                      ),

                      _buildOption(
                        letter: 'B',
                        text: optionB,
                      ),

                      _buildOption(
                        letter: 'C',
                        text: optionC,
                      ),

                      _buildOption(
                        letter: 'D',
                        text: optionD,
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color:
                      Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset:
                      const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                        _currentQuestion > 0
                            ? _previousQuestion
                            : null,
                        icon: const Icon(
                          Icons.arrow_back,
                        ),
                        label:
                        const Text('Previous'),
                        style:
                        OutlinedButton.styleFrom(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            vertical: 13,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    if (_currentQuestion ==
                        _questions.length - 1)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : _confirmSubmit,
                          icon: const Icon(
                            Icons.send,
                          ),
                          label:
                          const Text('Submit'),
                          style: ElevatedButton
                              .styleFrom(
                            backgroundColor:
                            const Color(
                                0xFF2E7D32),
                            foregroundColor:
                            Colors.white,
                            padding:
                            const EdgeInsets
                                .symmetric(
                              vertical: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                          _nextQuestion,
                          icon: const Icon(
                            Icons.arrow_forward,
                          ),
                          label:
                          const Text('Next'),
                          iconAlignment:
                          IconAlignment.end,
                          style: ElevatedButton
                              .styleFrom(
                            backgroundColor:
                            const Color(
                                0xFF1565C0),
                            foregroundColor:
                            Colors.white,
                            padding:
                            const EdgeInsets
                                .symmetric(
                              vertical: 13,
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
      ),
    );
  }
}