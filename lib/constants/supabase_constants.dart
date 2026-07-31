/// Fill these in from your Supabase project settings:
/// Project Settings -> API -> Project URL / anon public key.
///
/// Do NOT commit real keys to a public repo — use --dart-define or
/// a .env approach (flutter_dotenv) for production builds.
class SupabaseConstants {
  // CORRECTED: removed /rest/v1/ and fixed project ID spelling
  static const String url = 'https://myvkkmwmofeoaavjuueb.supabase.co';
  
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im15dmtrbXdtb2Zlb2Fhdmp1dWViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUzMTk1OTQsImV4cCI6MjEwMDg5NTU5NH0.DzowxkfUNh9-OhN4vjzeZUM32egWx_PsBQ1uDnILvkg';

  static const String postsBucket = 'posts-media';
  static const String avatarsBucket = 'avatars';
}

/// Base URL of the FastAPI AI backend (see /backend folder).
class AiBackendConstants {
  static const String baseUrl = 'https://viyoai-production.up.railway.app';
  // For local testing on an Android emulator, use:
  // static const String baseUrl = 'http://10.0.2.2:8000';
}
