import { forwardRef, type ReactNode } from "react";
import { motion, type HTMLMotionProps } from "framer-motion";
import { cn } from "@/lib/utils";

/**
 * Primary CTA with a subtle shimmer animation that runs every 4s
 * while idle. Use for the single most important action on a page
 * (e.g. "Save changes", "Invite member").
 *
 * Not for use in tight lists or as an inline form action — those
 * should use the regular <Button>.
 */
type ShimmerButtonProps = Omit<HTMLMotionProps<"button">, "children"> & {
  children: ReactNode;
  /** Tailwind class for the background. Default `bg-sky-500`. */
  colorClass?: string;
};

export const ShimmerButton = forwardRef<HTMLButtonElement, ShimmerButtonProps>(
  ({ className, children, colorClass = "bg-sky-500 hover:bg-sky-400", ...props }, ref) => {
    return (
      <motion.button
        ref={ref}
        whileHover={{ scale: 1.02 }}
        whileTap={{ scale: 0.97 }}
        transition={{ duration: 0.18, ease: "easeOut" }}
        className={cn(
          "group relative inline-flex items-center justify-center overflow-hidden rounded-md px-5 py-2.5 text-sm font-medium text-white shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400 focus-visible:ring-offset-2 focus-visible:ring-offset-[#0D1117] disabled:pointer-events-none disabled:opacity-50",
          colorClass,
          className,
        )}
        {...props}
      >
        <span className="relative z-10 inline-flex items-center gap-2">{children}</span>
        <span
          aria-hidden="true"
          className="pointer-events-none absolute inset-y-0 -left-1/3 w-1/3 -skew-x-12 bg-gradient-to-r from-transparent via-white/30 to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100"
        />
        <motion.span
          aria-hidden="true"
          className="pointer-events-none absolute inset-y-0 -left-1/3 w-1/3 -skew-x-12 bg-gradient-to-r from-transparent via-white/20 to-transparent"
          initial={{ x: "-120%" }}
          animate={{ x: "320%" }}
          transition={{ repeat: Infinity, repeatDelay: 4, duration: 1.4, ease: "easeInOut" }}
        />
      </motion.button>
    );
  },
);
ShimmerButton.displayName = "ShimmerButton";
