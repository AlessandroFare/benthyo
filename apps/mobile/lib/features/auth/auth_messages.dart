import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps Supabase auth errors to user-facing copy (never raw exceptions).
String friendlyAuthMessage(Object error) {
  if (error is AuthException) {
    final code = error.code?.toLowerCase() ?? '';
    final message = error.message.toLowerCase();

    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Confirm your email before signing in. Check your inbox for the link we sent when you registered.';
    }

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'Incorrect email or password. If you just registered, open the confirmation link in your email first, then sign in with the same password you chose.';
    }

    if (code == 'user_already_registered' ||
        message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with this email already exists. Sign in instead, or use “Resend confirmation email” if you have not verified yet.';
    }

    if (code == 'signup_disabled' || message.contains('signups not allowed')) {
      return 'New sign-ups are disabled for this project. Contact support if you need access.';
    }

    if (code == 'over_email_send_rate_limit' ||
        message.contains('rate limit')) {
      return 'Too many emails sent. Wait a few minutes before requesting another confirmation link.';
    }

    if (message.contains('password') && message.contains('weak')) {
      return 'Choose a stronger password (at least 6 characters).';
    }

    if (message.contains('invalid api key')) {
      return 'Supabase URL and API key do not match. For local dev, run '
          '`supabase status` and use the same project URL + anon/publishable key '
          'via `flutter run --dart-define-from-file=dart_defines.local.json`.';
    }

    if (message.contains('database error querying schema') ||
        message.contains('database error')) {
      return 'Supabase database is unavailable or migrations are missing. '
          'Run `supabase start` and `supabase db reset`, or free disk space if Docker is full.';
    }

    if (error.message.isNotEmpty && !error.message.startsWith('Auth')) {
      return error.message;
    }
  }

  return 'Something went wrong. Please try again.';
}

bool isEmailNotConfirmedError(Object error) {
  if (error is! AuthException) return false;
  final code = error.code?.toLowerCase() ?? '';
  final message = error.message.toLowerCase();
  return code == 'email_not_confirmed' ||
      message.contains('email not confirmed');
}

bool isInvalidCredentialsError(Object error) {
  if (error is! AuthException) return false;
  final code = error.code?.toLowerCase() ?? '';
  final message = error.message.toLowerCase();
  return code == 'invalid_credentials' ||
      message.contains('invalid login credentials');
}
