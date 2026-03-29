class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String author;
  final String text;
  final DateTime timestamp;
}
