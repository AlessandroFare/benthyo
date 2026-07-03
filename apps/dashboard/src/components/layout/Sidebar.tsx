import { NavLink } from "react-router-dom";
import {
  Anchor,
  BarChart3,
  CalendarDays,
  CalendarRange,
  Fish,
  MapPin,
  Package,
  Settings,
  ShieldCheck,
  Store,
  Users,
  Waves,
} from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { useOperator } from "@/hooks/useOperator";

const navGroups: {
  heading: string | null;
  items: { to: string; label: string; icon: typeof MapPin; end?: boolean }[];
}[] = [
  {
    heading: null,
    items: [{ to: "/", label: "Today", icon: CalendarDays, end: true }],
  },
  {
    heading: "Operations",
    items: [
      { to: "/customers", label: "Customers", icon: Users },
      { to: "/slots", label: "Trip slots", icon: CalendarRange },
      { to: "/rental-gear", label: "Rental gear", icon: Package },
      { to: "/analytics", label: "Analytics", icon: BarChart3 },
    ],
  },
  {
    heading: "Catalog",
    items: [
      { to: "/sites", label: "Sites", icon: MapPin },
      { to: "/species", label: "Species", icon: Fish },
      { to: "/marketplace", label: "Marketplace", icon: Store },
    ],
  },
  {
    heading: "Compliance",
    items: [{ to: "/corrections", label: "Corrections", icon: ShieldCheck }],
  },
  {
    heading: null,
    items: [{ to: "/settings", label: "Settings", icon: Settings }],
  },
];

function SidebarBody({
  forceLabels = false,
  onNavigate,
}: {
  forceLabels?: boolean;
  onNavigate?: () => void;
}) {
  const { data: operator } = useOperator();
  const labelClass = forceLabels ? "block" : "hidden xl:block";

  return (
    <>
      {/* Brand header */}
      <div className="flex h-16 items-center justify-center border-b border-white/10 px-3 xl:justify-start xl:gap-3 xl:px-5">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-ocean-500 shadow-lg shadow-ocean-500/20">
          <Waves className="h-5 w-5" />
        </div>
        <div className={cn("min-w-0", labelClass)}>
          <p className="truncate text-sm font-semibold tracking-wide">Benthyo</p>
          <p className="truncate text-xs text-white/60">Operator</p>
        </div>
      </div>

      {/* Nav items */}
      <nav className="flex flex-1 flex-col gap-1 overflow-y-auto p-3" aria-label="Primary navigation">
        {navGroups.map((group, gi) => (
          <div key={group.heading ?? `group-${gi}`} className="flex flex-col gap-0.5">
            {group.heading && (
              <p
                className={cn(
                  "mt-3 px-3 text-[10px] font-semibold uppercase tracking-wider text-white/50",
                  labelClass,
                )}
              >
                {group.heading}
              </p>
            )}
            {group.items.map(({ to, label, icon: Icon, end }) => (
              <NavLink
                key={to}
                to={to}
                end={end}
                title={label}
                onClick={onNavigate}
                className={({ isActive }) =>
                  cn(
                    "group relative flex items-center justify-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all duration-150 xl:justify-start",
                    isActive
                      ? "text-white"
                      : "text-white/65 hover:text-white",
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    {/* Animated background pill with layoutId */}
                    <AnimatePresence>
                      {isActive && (
                        <motion.span
                          layoutId="sidebar-active-pill"
                          className="absolute inset-0 rounded-xl bg-white/10"
                          initial={false}
                          transition={{ type: "spring", stiffness: 500, damping: 40 }}
                        />
                      )}
                    </AnimatePresence>
                    {/* Hover background (only when not active) */}
                    {!isActive && (
                      <span className="absolute inset-0 rounded-xl opacity-0 transition-opacity duration-150 group-hover:opacity-100 bg-white/5" />
                    )}
                    <Icon
                      className={cn(
                        "relative z-10 h-5 w-5 shrink-0 transition-colors",
                        isActive ? "text-white" : "text-white/65 group-hover:text-white",
                      )}
                    />
                    <span className={cn("relative z-10 truncate", labelClass)}>
                      {label}
                    </span>
                    {isActive && (
                      <motion.span
                        layoutId="sidebar-active-dot"
                        className={cn(
                          "relative z-10 ml-auto hidden h-1.5 w-1.5 rounded-full bg-ocean-400",
                          forceLabels ? "block" : "hidden xl:block",
                        )}
                        initial={{ scale: 0 }}
                        animate={{ scale: 1 }}
                        transition={{ delay: 0.1 }}
                      />
                    )}
                  </>
                )}
              </NavLink>
            ))}
          </div>
        ))}
      </nav>

      {/* Operator footer */}
      <div className="border-t border-white/10 p-3">
        <div className="flex items-center justify-center gap-3 rounded-xl bg-white/5 px-3 py-2.5 xl:justify-start">
          <Anchor className="h-4 w-4 shrink-0 text-ocean-300" />
          <div className={cn("hidden min-w-0", labelClass)}>
            <p className="truncate text-xs font-medium text-white">
              {operator?.name ?? "Dive Center"}
            </p>
            <p className="truncate text-[10px] text-white/50">B2B Portal</p>
          </div>
        </div>
      </div>
    </>
  );
}

interface SidebarProps {
  mobileOpen: boolean;
  onNavigate?: () => void;
}

export function Sidebar({ mobileOpen, onNavigate }: SidebarProps) {
  return (
    <>
      {/* Desktop rail */}
      <aside className="hidden h-full w-[76px] shrink-0 flex-col border-r border-white/10 bg-[#0A2342] text-white sm:flex xl:w-64">
        <SidebarBody onNavigate={onNavigate} />
      </aside>

      {/* Mobile backdrop */}
      <div
        className={cn(
          "fixed inset-0 z-40 bg-black/60 backdrop-blur-sm transition-opacity duration-300 sm:hidden",
          mobileOpen ? "opacity-100" : "pointer-events-none opacity-0",
        )}
        onClick={onNavigate}
        aria-hidden="true"
      />

      {/* Mobile drawer */}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col border-r border-white/10 bg-[#0A2342] text-white shadow-2xl transition-transform duration-300 ease-out sm:hidden",
          mobileOpen ? "translate-x-0" : "-translate-x-full",
        )}
        aria-label="Primary navigation"
        aria-hidden={!mobileOpen}
      >
        <SidebarBody forceLabels onNavigate={onNavigate} />
      </aside>
    </>
  );
}
