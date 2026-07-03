import { useState } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { motion } from "framer-motion";
import { Fish } from "lucide-react";
import { resendSignupConfirmation, signInWithEmail, signInWithGoogle } from "@/lib/auth";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export function LoginPage() {
  const { session } = useAuth();
  const location = useLocation();
  const from =
    (location.state as { from?: { pathname: string } })?.from?.pathname ?? "/";

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [showResend, setShowResend] = useState(false);

  if (session) {
    return <Navigate to={from} replace />;
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setInfo(null);
    setShowResend(false);
    setLoading(true);

    const result = await signInWithEmail(email, password);
    if (result.error) {
      setError(result.error);
      setShowResend(true);
    }
    setLoading(false);
  }

  async function handleGoogle() {
    setError(null);
    setLoading(true);
    const result = await signInWithGoogle();
    if (result.error) setError(result.error);
    setLoading(false);
  }

  async function handleResend() {
    setError(null);
    setInfo(null);
    setLoading(true);
    const result = await resendSignupConfirmation(email);
    if (result.error) {
      setError(result.error);
    } else {
      setInfo("Confirmation email sent. Check your inbox and spam folder.");
    }
    setLoading(false);
  }

  return (
    <div className="relative flex min-h-full items-center justify-center overflow-hidden bg-gradient-to-br from-[#061629] via-[#0A2342] to-[#0c4a6e] p-4">
      {/* Animated background bubbles. Pure CSS, no canvas, no
          perf hit. Each bubble is a different size + delay so the
          loop doesn't look mechanical. */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden">
        {Array.from({ length: 18 }).map((_, i) => (
          <motion.div
            key={i}
            className="absolute rounded-full bg-white/8"
            style={{
              left: `${(i * 53) % 100}%`,
              width: 8 + (i % 5) * 6,
              height: 8 + (i % 5) * 6,
              top: `${(i * 31) % 100}%`,
            }}
            initial={{ y: 0, opacity: 0 }}
            animate={{
              y: [-20, -120],
              opacity: [0, 0.4, 0],
            }}
            transition={{
              duration: 6 + (i % 4),
              delay: i * 0.3,
              repeat: Infinity,
              ease: "easeOut",
            }}
          />
        ))}
      </div>

      <motion.div
        initial={{ opacity: 0, y: 20, scale: 0.96 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.45, ease: "easeOut" }}
        className="relative z-10 w-full max-w-md"
      >
        <Card className="w-full shadow-2xl">
          <CardHeader className="space-y-4 text-center">
            <motion.div
              initial={{ scale: 0, rotate: -90 }}
              animate={{ scale: 1, rotate: 0 }}
              transition={{
                delay: 0.2,
                type: "spring",
                stiffness: 200,
                damping: 12,
              }}
              className="mx-auto"
            >
              <img
                src="/logo-mark.svg"
                alt="Benthyo"
                className="h-14 w-14 rounded-xl"
              />
            </motion.div>
            <div>
              <CardTitle className="text-2xl">Benthyo</CardTitle>
              <CardDescription>
                Sign in to your dive center dashboard
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-4">
              <motion.div
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.3 }}
                className="space-y-2"
              >
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="operator@divecenter.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  autoComplete="email"
                />
              </motion.div>
              <motion.div
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.4 }}
                className="space-y-2"
              >
                <Label htmlFor="password">Password</Label>
                <Input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                />
              </motion.div>
              {error && (
                <motion.p
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="text-sm text-destructive"
                  role="alert"
                >
                  {error}
                </motion.p>
              )}
              {info && (
                <motion.p
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  className="text-sm text-emerald-600"
                  role="status"
                >
                  {info}
                </motion.p>
              )}
              {showResend && (
                <Button
                  type="button"
                  variant="link"
                  className="h-auto p-0 text-sm"
                  onClick={handleResend}
                  disabled={loading || !email}
                >
                  Resend confirmation email
                </Button>
              )}
              <motion.div
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.5 }}
                className="space-y-2"
              >
                <Button type="submit" className="w-full" disabled={loading}>
                  {loading ? (
                    <span className="flex items-center gap-2">
                      <Fish className="h-4 w-4 animate-pulse" />
                      Signing in…
                    </span>
                  ) : (
                    "Sign in"
                  )}
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  className="w-full"
                  disabled={loading}
                  onClick={handleGoogle}
                >
                  Continue with Google
                </Button>
              </motion.div>
            </form>
          </CardContent>
        </Card>
      </motion.div>
    </div>
  );
}
