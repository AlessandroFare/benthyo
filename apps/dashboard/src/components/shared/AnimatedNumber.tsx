import { useEffect, useRef, useState } from "react";
import { motion, useInView } from "framer-motion";
import { cn } from "@/lib/utils";

interface AnimatedNumberProps {
  /** Final value. */
  value: number;
  /** Animation duration in ms. Default 900. */
  duration?: number;
  /** Decimal places to render. Default 0. */
  decimals?: number;
  /** Locale for `Intl.NumberFormat`. Default "en-US". */
  locale?: string;
  /** Optional prefix (e.g. "$"). */
  prefix?: string;
  /** Optional suffix (e.g. "%"). */
  suffix?: string;
  /** Re-trigger the animation when this key changes. */
  triggerKey?: string | number;
  className?: string;
}

/**
 * Counts up from 0 to `value` the first time the element scrolls into
 * view. Useful for KPI tiles so a value change after a route
 * transition re-runs the count rather than snapping.
 */
export function AnimatedNumber({
  value,
  duration = 900,
  decimals = 0,
  locale = "en-US",
  prefix = "",
  suffix = "",
  triggerKey,
  className,
}: AnimatedNumberProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const isInView = useInView(ref, { once: true, amount: 0.5 });
  const [display, setDisplay] = useState(0);

  useEffect(() => {
    if (!isInView) return;

    const start = performance.now();
    const from = 0;
    const to = value;
    let raf = 0;

    const step = (now: number) => {
      const elapsed = now - start;
      const t = Math.min(1, elapsed / duration);
      // easeOutQuart
      const eased = 1 - Math.pow(1 - t, 4);
      setDisplay(from + (to - from) * eased);
      if (t < 1) raf = requestAnimationFrame(step);
      else setDisplay(to);
    };

    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [isInView, value, duration, triggerKey]);

  const formatted = new Intl.NumberFormat(locale, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(display);

  return (
    <motion.span
      ref={ref}
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.32, ease: "easeOut" }}
      className={cn("tabular-nums", className)}
    >
      {prefix}
      {formatted}
      {suffix}
    </motion.span>
  );
}
