import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { CheckCircle2, AlertCircle, Info, X, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Lightweight toast system built on framer-motion. No external deps.
 *
 * Usage:
 *   const { toast } = useToast();
 *   toast({ title: "Site added", description: "Linked to your account.", variant: "success" });
 *
 * Variants: "info" (default), "success", "error".
 * Auto-dismiss after 4.5 s. Stack grows from the top-right corner.
 */

type ToastVariant = "info" | "success" | "error";

interface Toast {
  id: string;
  title: string;
  description?: string;
  variant: ToastVariant;
  durationMs: number;
}

interface ToastOptions {
  title: string;
  description?: string;
  variant?: ToastVariant;
  /** Override the default 4.5 s auto-dismiss. */
  durationMs?: number;
}

interface ToastContextValue {
  toast: (opts: ToastOptions) => void;
  dismiss: (id: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

const VARIANT_ICON: Record<ToastVariant, LucideIcon> = {
  info: Info,
  success: CheckCircle2,
  error: AlertCircle,
};

const VARIANT_BORDER: Record<ToastVariant, string> = {
  info: "border-sky-500/40",
  success: "border-emerald-500/40",
  error: "border-rose-500/40",
};

const VARIANT_TEXT: Record<ToastVariant, string> = {
  info: "text-sky-300",
  success: "text-emerald-300",
  error: "text-rose-300",
};

const DEFAULT_DURATION = 4500;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((current) => current.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback((opts: ToastOptions) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const next: Toast = {
      id,
      title: opts.title,
      description: opts.description,
      variant: opts.variant ?? "info",
      durationMs: opts.durationMs ?? DEFAULT_DURATION,
    };
    setToasts((current) => [...current, next]);
  }, []);

  // Auto-dismiss timers. We track them in a ref so we can cancel on unmount.
  useEffect(() => {
    if (toasts.length === 0) return;
    const timeouts = toasts.map((t) =>
      setTimeout(() => {
        dismiss(t.id);
      }, t.durationMs),
    );
    return () => {
      timeouts.forEach(clearTimeout);
    };
  }, [toasts, dismiss]);

  return (
    <ToastContext.Provider value={{ toast, dismiss }}>
      {children}
      <div className="pointer-events-none fixed right-4 top-4 z-[60] flex w-[calc(100vw-2rem)] max-w-sm flex-col gap-2">
        <AnimatePresence initial={false}>
          {toasts.map((t) => {
            const Icon = VARIANT_ICON[t.variant];
            return (
              <motion.div
                key={t.id}
                layout
                initial={{ opacity: 0, x: 32, scale: 0.96 }}
                animate={{ opacity: 1, x: 0, scale: 1 }}
                exit={{ opacity: 0, x: 32, scale: 0.96 }}
                transition={{ type: "spring", stiffness: 320, damping: 26 }}
                className={cn(
                  "pointer-events-auto relative flex items-start gap-3 rounded-lg border bg-popover/95 p-3 pr-8 text-popover-foreground shadow-lg backdrop-blur",
                  VARIANT_BORDER[t.variant],
                )}
                role="status"
              >
                <Icon className={cn("mt-0.5 h-4 w-4 shrink-0", VARIANT_TEXT[t.variant])} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium leading-snug">{t.title}</p>
                  {t.description && (
                    <p className="mt-0.5 text-xs text-muted-foreground">{t.description}</p>
                  )}
                </div>
                <button
                  onClick={() => dismiss(t.id)}
                  className="absolute right-1.5 top-1.5 rounded p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                  aria-label="Dismiss"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </motion.div>
            );
          })}
        </AnimatePresence>
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    // Safe no-op fallback so the dashboard doesn't blow up if the
    // provider is missing in a test harness.
    return {
      toast: () => undefined,
      dismiss: () => undefined,
    };
  }
  return ctx;
}
