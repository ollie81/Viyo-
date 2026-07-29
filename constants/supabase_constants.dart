/// Fill these in from your Supabase project settings:
/// Project Settings -> API -> Project URL / anon public key.
///
/// Do NOT commit real keys to a public repo — use --dart-define or
/// a .env approach (flutter_dotenv) for production builds.
class SupabaseConstants {
  static const String url = 'https://YOUR_PROJECT_REF.supabase.co';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';

  static const String postsBucket = 'posts-media';
  static const String avatarsBucket = 'avatars';
}

/// Base URL of the FastAPI AI backend (see /backend folder).
class AiBackendConstants {
  static const String baseUrl = 'https://your-fastapi-host.example.com';
  // For local testing on an Android emulator, use:
  // static const String baseUrl = 'http://10.0.2.2:8000';
}
