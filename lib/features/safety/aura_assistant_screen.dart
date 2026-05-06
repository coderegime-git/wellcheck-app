import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'dart:async';

class AuraAssistantScreen extends StatefulWidget {
  const AuraAssistantScreen({super.key});

  @override
  State<AuraAssistantScreen> createState() => _AuraAssistantScreenState();
}

class _AuraAssistantScreenState extends State<AuraAssistantScreen>
    with SingleTickerProviderStateMixin {
  String _currentState = 'Ready';
  String _displayText = 'How can I help protect the family today?';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _sendPromptToAura(String prompt) async {
    if (prompt.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _currentState = 'Processing...';
      _displayText = 'Thinking...';
    });

    _textController.clear();
    FocusScope.of(context).unfocus();

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'aura_ai',
        body: {
          'prompt': prompt,
          'context':
              'Well-Check V3 Flutter Application. User interacting via Aura Screen.',
        },
      );

      if (mounted) {
        setState(() {
          _currentState = 'Aura says:';
          _displayText = response.data['reply'] ?? 'No response received.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentState = 'Error';
          _displayText = 'Failed to reach Aura AI: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aura Intelligence'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: ShieldColors.nightIndigo,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isLoading ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  ShieldColors.activeTeal.withValues(
                                    alpha: 0.8,
                                  ),
                                  ShieldColors.activeTeal.withValues(
                                    alpha: 0.2,
                                  ),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ShieldColors.activeTeal.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isLoading ? Icons.hourglass_top : Icons.mic_none,
                              color: Colors.white,
                              size: 64,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 64),
                    Text(
                      _currentState.toUpperCase(),
                      style: const TextStyle(
                        color: ShieldColors.activeTeal,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _displayText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Input Area for MVP Prototyping
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Type your request to Aura...",
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      onSubmitted: _sendPromptToAura,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    onPressed: _isLoading
                        ? null
                        : () => _sendPromptToAura(_textController.text),
                    backgroundColor: ShieldColors.activeTeal,
                    elevation: 0,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
