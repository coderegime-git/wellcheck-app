import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

/// Realtime family chat screen — replaces the iMessage URL launcher
class FamilyChatScreen extends ConsumerStatefulWidget {
  const FamilyChatScreen({super.key});

  @override
  ConsumerState<FamilyChatScreen> createState() => _FamilyChatScreenState();
}

class _FamilyChatScreenState extends ConsumerState<FamilyChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  RealtimeChannel? channel;
@override
  void initState() {
  channel = Supabase.instance.client.channel('family-chat')
    ..onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'family_messages',
      callback: (payload) {
        setState(() {});
      },
    )
    ..subscribe();    super.initState();
  }
  @override
  void dispose() {
    channel?.unsubscribe();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      await Supabase.instance.client.from('family_messages').insert({
        'family_id': profile.familyId,
        'sender_id': profile.userId,
        'message': text,
        'message_type': 'text',
      });

      _msgController.clear();

      // Scroll to bottom after a short delay
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0, // newest at top with reverse: true
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      print(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      // 3. Send push
      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == profile.userId) continue;

        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "New Message",
              "body": "${profile.fullName ?? 'Someone'}: $text",
              "action": "chat_message",
            },
          );
        } catch (e) {
          print("Push failed: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      body: SafeArea(
       // padding: MediaQuery.viewInsetsOf(context),
        child: Container(
          decoration: const BoxDecoration(
            color: ShieldColors.backgroundWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(
          //  maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            children: [
              // Handle
              // Padding(
              //   padding: const EdgeInsets.only(top: 12),
              //   child: Container(
              //     width: 40,
              //     height: 4,
              //     decoration: BoxDecoration(
              //       color: Colors.grey.shade300,
              //       borderRadius: BorderRadius.circular(2),
              //     ),
              //   ),
              // ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Family Chat',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade400,
                              offset: Offset(0, 0),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.close, color: Colors.black, size: 16),
                      ),
                    ),

                  ],
                ),
              ),
              const Divider(),

              // Messages
              Expanded(
                child: profileAsync.when(
                  data: (profile) {
                    if (profile == null) {
                      return const Center(child: Text('No profile.'));
                    }

                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: Supabase.instance.client
                          .from('family_messages')
                          .stream(primaryKey: ['id'])
                          .eq('family_id', profile.familyId)
                          .order('created_at', ascending: false),
                      builder: (context, snapshot) {
                        // if (snapshot.connectionState == ConnectionState.waiting) {
                        //   return const Center(child: CircularProgressIndicator());
                        // }
       print("STREAM UPDATED");//
                        final messages = snapshot.data ?? [];
                        if (messages.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'No messages yet.\nSend the first one!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          // newest at bottom
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isMe = msg['sender_id'] == profile.userId;
                            return _ChatBubble(
                              message: msg['message'] as String? ?? '',
                              isMe: isMe,
                              senderId: msg['sender_id'] as String? ?? '',
                              createdAt: msg['created_at'] as String?,
                            );
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                ),
              ),

              // Input bar
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          decoration: InputDecoration(
                            hintText: 'Message your family...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: const BoxDecoration(
                          color: ShieldColors.activeTeal,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send, color: Colors.white),
                          onPressed: _isSending ? null : _sendMessage,
                        ),
                      ),
                    ],
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

class _ChatBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final String senderId;
  final String? createdAt;

  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.senderId,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    String timeStr = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt!);
        timeStr = DateFormat.jm().format(dt);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            CircleAvatar(
              radius: 14,
              backgroundColor: ShieldColors.activeTeal.withValues(alpha: 0.1),
              child: const Icon(
                Icons.person,
                size: 14,
                color: ShieldColors.activeTeal,
              ),
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? ShieldColors.activeTeal : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: isMe ? Colors.white : ShieldColors.textBody,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.grey,
                      fontSize: 10,
                    ),
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
