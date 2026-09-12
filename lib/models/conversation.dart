class Conversation {
  final String id;
  final String otherUserId;
  final String? otherUsername;
  final String? otherDisplayName;
  final String? otherAvatarUrl;
  final DateTime lastMessageAt;
  final String? lastMessagePreview;
  final bool lastMessageIsMine;
  final int unreadCount;

  const Conversation({
    required this.id,
    required this.otherUserId,
    this.otherUsername,
    this.otherDisplayName,
    this.otherAvatarUrl,
    required this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageIsMine = false,
    this.unreadCount = 0,
  });

  String get otherName => otherDisplayName?.trim().isNotEmpty == true
      ? otherDisplayName!
      : (otherUsername ?? 'Unknown');

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'],
        otherUserId: json['other_user_id'],
        otherUsername: json['other_username'],
        otherDisplayName: json['other_display_name'],
        otherAvatarUrl: json['other_avatar_url'],
        lastMessageAt: DateTime.parse(json['last_message_at']).toLocal(),
        lastMessagePreview: json['last_message_preview'],
        lastMessageIsMine: json['last_message_is_mine'] ?? false,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;
  final bool isMine;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.readAt,
    required this.isMine,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        conversationId: json['conversation_id'],
        senderId: json['sender_id'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at']).toLocal() : null,
        isMine: json['is_mine'] ?? false,
      );
}
