class InspirationItem {
  final String quote;
  final String author;
  InspirationItem(this.quote, this.author);
}

class InspirationService {
  static final List<InspirationItem> quotes = [
    InspirationItem(
        'Consistency beats talent when talent doesn\'t show up every day.',
        'Unknown'),
    InspirationItem('Your future self is watching. Make them proud.', 'Viyo'),
    InspirationItem(
        'Create for the one person who needs your message today.',
        'Creator wisdom'),
    InspirationItem(
        'Small daily progress leads to massive results over time.',
        'James Clear'),
    InspirationItem(
        'The best time to plant a tree was 20 years ago. The second best time is now.',
        'Chinese Proverb'),
    InspirationItem('Don\'t wait for perfect. Ship it and improve.', 'Indie Maker'),
    InspirationItem(
        'Your content is a gift. Give it freely and keep creating.', 'Viyo'),
  ];

  static final List<String> ideas = [
    'Share a behind-the-scenes of your creative process',
    'Post a quick tip that helped you this week',
    'Reply to 5 comments on your latest post',
    'Create a short \'day in the life\' story',
    'Collaborate idea: tag a creator you admire',
    'Repurpose an old post with a new angle',
    'Ask your audience one powerful question',
  ];

  static InspirationItem getTodayQuote() {
    final day = DateTime.now().day;
    return quotes[day % quotes.length];
  }

  static String getTodayIdea() {
    final day = DateTime.now().day;
    return ideas[day % ideas.length];
  }
}