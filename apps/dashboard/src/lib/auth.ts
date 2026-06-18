import { createClient, type Session, type User } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL ?? "";
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY ?? "";

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: "pkce",
  },
});

export type AuthSession = Session;
export type AuthUser = User;

export function friendlyAuthMessage(error: { message: string; code?: string }): string {
  const code = error.code?.toLowerCase() ?? "";
  const message = error.message.toLowerCase();

  if (code === "email_not_confirmed" || message.includes("email not confirmed")) {
    return "Confirm your email before signing in. Check your inbox for the confirmation link.";
  }

  if (code === "invalid_credentials" || message.includes("invalid login credentials")) {
    return "Incorrect email or password. If you just registered, confirm your email first, then sign in with the same password.";
  }

  if (error.message && !error.message.startsWith("Auth")) {
    return error.message;
  }

  return "Sign in failed. Please try again.";
}

export async function getSession(): Promise<Session | null> {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export async function getAccessToken(): Promise<string | null> {
  const session = await getSession();
  return session?.access_token ?? null;
}

export async function signInWithEmail(
  email: string,
  password: string,
): Promise<{ error: string | null }> {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  return { error: error ? friendlyAuthMessage(error) : null };
}

export async function signInWithGoogle(): Promise<{ error: string | null }> {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: {
      redirectTo: window.location.origin,
    },
  });
  return { error: error ? friendlyAuthMessage(error) : null };
}

export async function resendSignupConfirmation(
  email: string,
): Promise<{ error: string | null }> {
  const { error } = await supabase.auth.resend({
    type: "signup",
    email,
    options: { emailRedirectTo: window.location.origin },
  });
  return { error: error ? friendlyAuthMessage(error) : null };
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}

export function onAuthStateChange(
  callback: (session: Session | null) => void,
): () => void {
  const {
    data: { subscription },
  } = supabase.auth.onAuthStateChange((_event, session) => {
    callback(session);
  });
  return () => subscription.unsubscribe();
}
