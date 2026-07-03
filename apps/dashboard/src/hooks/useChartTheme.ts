import { useTheme } from "@/contexts/ThemeContext";

/**
 * Returns theme-aware styling values for Recharts components so charts
 * look correct in both light and dark modes without per-component boilerplate.
 */
export function useChartTheme() {
  const { resolvedTheme } = useTheme();
  const isDark = resolvedTheme === "dark";

  return {
    isDark,
    gridStroke: isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.06)",
    tickFill: isDark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.45)",
    tooltipStyle: {
      backgroundColor: isDark ? "hsl(213, 22%, 12%)" : "hsl(0, 0%, 100%)",
      border: isDark
        ? "1px solid rgba(255,255,255,0.08)"
        : "1px solid rgba(0,0,0,0.08)",
      borderRadius: 12,
      color: isDark ? "#fff" : "#111",
      boxShadow: "0 8px 24px rgba(0,0,0,0.12)",
    } as React.CSSProperties,
    tooltipLabelStyle: {
      color: isDark ? "rgba(255,255,255,0.6)" : "rgba(0,0,0,0.5)",
    } as React.CSSProperties,
  };
}
