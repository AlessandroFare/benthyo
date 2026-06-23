import { type ReactNode } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

/**
 * A small status pill with a pulsing dot. Use for connection state,
 * trial status, sync progress, etc. The dot uses a framer-motion
 * keyframe scale to give it a subtle "live" feeling.
 */
export type StatusTone = "success" | "warning" | "error" | "info" | "neutral";

interface StatusPillProps {
  tone?: StatusTone;
  children: ReactNode;
  /** Show the pulsing dot. Default true. */
  pulse?: boolean;
  className?: string;
}

const TONE_STYLES: Record<StatusTone, { dot: string; bg: string; text: string }> = {
  success: { dot: "bg-emerald-400", bg: "bg-emerald-500/10", text: "text-emerald-300" },
  warning: { dot: "bg-amber-400",   bg: "bg-amber-500/10",   text: "text-amber-300" },
  error:   { dot: "bg-rose-400",    bg: "bg-rose-500/10",    text: "text-rose-300" },
  info:    { dot: "bg-sky-400",     bg: "bg-sky-500/10",     text: "text-sky-300" },
  neutral: { dot: "bg-muted-foreground/60", bg: "bg-muted", text: "text-muted-foreground" },
};

export function StatusPill({ tone = "neutral", children, pulse = true, className }: StatusPillProps) {
  const styles = TONE_STYLES[tone];
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-medium leading-none",
        styles.bg,
        styles.text,
        className,
      )}
    >
      <span className="relative flex h-1.5 w-1.5">
        {pulse && (
          <motion.span
            className={cn("absolute inline-flex h-full w-full rounded-full opacity-75", styles.dot)}
            animate={{ scale: [1, 2.2], opacity: [0.75, 0] }}
            transition={{ duration: 1.6, repeat: Infinity, ease: "easeOut" }}
          />
        )}
        <span className={cn("relative inline-flex h-1.5 w-1.5 rounded-full", styles.dot)} />
      </span>
      {children}
    </span>
  );
}
