class SupabaseOptions {
  static const url = 'https://zofrezlntcguprrqcpzm.supabase.co';
  static const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpvZnJlemxudGNndXBycnFjcHptIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MzEzMjQsImV4cCI6MjA5NTMwNzMyNH0.a2Bh4wZm81aLNai7tAfeJHnREEGcZbdWDZ7ektmLIrA';

  static bool get isConfigured =>
      !url.contains('YOUR_PROJECT_REF') && !anonKey.contains('YOUR_');
}
