import { motion, type Variants, type HTMLMotionProps } from "framer-motion";
import { type ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Page-level animated container. Wraps any page content with a
 * fade + slide-up enter and a staggered child sequence. Drop in
 * <AnimatedPage>...</AnimatedPage> at the top of each page to get
 * the same transition curve everywhere.
 *
 * The child animation variants are exposed so individual <motion.div>
 * children can opt into the stagger by adding `variants={childVariants}`.
 */
const containerVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.06,
      delayChildren: 0.05,
      when: "beforeChildren",
    },
  },
};

const childVariants: Variants = {
  hidden: { opacity: 0, y: 12 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.36, ease: [0.21, 0.47, 0.32, 0.98] },
  },
};

interface AnimatedPageProps extends Omit<HTMLMotionProps<"div">, "variants" | "initial" | "animate"> {
  children: ReactNode;
}

/**
 * Top-level wrapper. Use this once per page.
 *
 * @example
 *   <AnimatedPage>
 *     <AnimatedItem>
 *       <h1>Dashboard</h1>
 *     </AnimatedItem>
 *     <AnimatedItem>
 *       <KpiCard ... />
 *     </AnimatedItem>
 *   </AnimatedPage>
 */
export function AnimatedPage({ children, className, ...rest }: AnimatedPageProps) {
  return (
    <motion.div
      initial="hidden"
      animate="visible"
      variants={containerVariants}
      className={cn("space-y-6", className)}
      {...rest}
    >
      {children}
    </motion.div>
  );
}

/**
 * Per-block wrapper. Use inside <AnimatedPage> to opt into the
 * staggered child animation. If a child is rendered outside
 * AnimatedPage, the motion library will simply animate on its own.
 */
export function AnimatedItem({ children, className, ...rest }: AnimatedPageProps) {
  return (
    <motion.div variants={childVariants} className={className} {...rest}>
      {children}
    </motion.div>
  );
}

export const animatedChildVariants = childVariants;
export const animatedContainerVariants = containerVariants;
