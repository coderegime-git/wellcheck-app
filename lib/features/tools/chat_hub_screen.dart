import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/tools_repository.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ChatHubScreen extends ConsumerStatefulWidget {
  const ChatHubScreen({super.key});

  @override
  ConsumerState<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends ConsumerState<ChatHubScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  // Cache of sender profiles: userId -> name
  Map<String, String> _senderNames = {};

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;
      await ref
          .read(toolsRepositoryProvider)
          .sendMessage(profile.familyId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: ShieldColors.urgentRed,
          ),
        );
      }
    }
  }

  Future<void> _loadSenderNames(String familyId) async {
    if (_senderNames.isNotEmpty) return; // Already loaded
    try {
      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id, profiles(full_name)')
          .eq('family_id', familyId);

      final map = <String, String>{};
      for (final m in members) {
        final userId = m['user_id'] as String;
        final name = m['profiles']?['full_name'] as String? ?? 'Member';
        map[userId] = name;
      }
      if (mounted) {
        setState(() => _senderNames = map);
      }
    } catch (_) {}
  }

  String _getSenderName(String? senderId) {
    if (senderId == null) return 'Unknown';
    return _senderNames[senderId] ?? 'Member';
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return DateFormat.E().format(dt); // "Mon"
      return DateFormat.MMMd().format(dt); // "Mar 24"
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return const Scaffold(
            body: Center(child: Text('No profile. Please sign in.')),
          );
        }

        final currentUserId = profile.userId;
        final familyId = profile.familyId;

        // Load sender names once
        _loadSenderNames(familyId);

        final chatStream = ref
            .watch(toolsRepositoryProvider)
            .streamChatMessages(familyId);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Family Shield Chat'),
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: chatStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error loading chat: ${snapshot.error}'),
                      );
                    }

                    final messages = snapshot.data ?? [];

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'No messages yet',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Start the conversation with your family!',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg =
                            messages.reversed.toList()[index];
                        final senderId = msg['sender_id'] as String?;
                        final isSender = senderId == currentUserId;
                        final senderName =
                            isSender ? 'You' : _getSenderName(senderId);
                        final time =
                            _formatTime(msg['created_at'] as String?);

                        return _buildMessageBubble(
                          msg['content'] ?? '',
                          isSender,
                          senderName,
                          time,
                        );
                      },
                    );
                  },
                ),
              ),
              // Input area
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          onSubmitted: (_) => _handleSend(),
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: ShieldDesign.roundedTwelve,
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: ShieldColors.softMint,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: ShieldColors.activeTeal,
                        child: IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _handleSend,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildMessageBubble(
    String text,
    bool isSender,
    String senderName,
    String time,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              senderName,
              style: TextStyle(
                fontSize: 12,
                color: isSender
                    ? ShieldColors.activeTeal
                    : Colors.grey,
                fontWeight:
                    isSender ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSender
                  ? ShieldColors.activeTeal
                  : ShieldColors.softMint,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isSender
                    ? const Radius.circular(16)
                    : const Radius.circular(4),
                bottomRight: isSender
                    ? const Radius.circular(4)
                    : const Radius.circular(16),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isSender ? Colors.white : ShieldColors.textBody,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              time,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
