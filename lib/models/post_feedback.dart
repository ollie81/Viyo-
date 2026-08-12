class PostFeedback {
  final String whatWorked;
  final String whatToImprove;
  final List<String> contentIdeas;
  final String engagementTip;

  PostFeedback({
    required this.whatWorked,
    required this.whatToImprove,
    required this.contentIdeas,
    required this.engagementTip,
  });

  factory PostFeedback.fromAiResponse(Map<String, dynamic> json) => PostFeedback(
        whatWorked: json['what_worked'],
        whatToImprove: json['what_to_improve'],
        contentIdeas: List<String>.from(json['content_ideas']),
        engagementTip: json['engagement_tip'],
      );

  factory PostFeedback.fromDb(Map<String, dynamic> json) => PostFeedback(
        whatWorked: json['what_worked'],
        whatToImprove: json['what_to_improve'],
        contentIdeas: List<String>.from(json['content_ideas'] ?? []),
        engagementTip: json['engagement_tip'],
      );

  Map<String, dynamic> toDbRow({required String postId, required String userId}) => {
        'post_id': postId,
        'user_id': userId,
        'what_worked': whatWorked,
        'what_to_improve': whatToImprove,
        'content_ideas': contentIdeas,
        'engagement_tip': engagementTip,
      };
}
