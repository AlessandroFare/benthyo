import { NavLink } from "react-router-dom";
import {
  Anchor,
  BarChart3,
  Fish,
  LayoutDashboard,
  MapPin,
  Package,
  Settings,
  ShieldCheck,
  Store,
  Users,
  Waves,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useOperator } from "@/hooks/useOperator";

const navItems = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard, end: true },
  { to: "/sites", label: "Sites", icon: MapPin },
  { to: "/customers", label: "Customers", icon: Users },
  { to: "/analytics", label: "Analytics", icon: BarChart3 },
  { to: "/species", label: "Species", icon: Fish },
  { to: "/corrections", label: "Corrections", icon: ShieldCheck },
  { to: "/rental-gear", label: "Rental gear", icon: Package },
  { to: "/marketplace", label: "Marketplace", icon: Store },
  { to: "/settings", label: "Settings", icon: Settings },
];

export function Sidebar() {
  const { data: operator } = useOperator();

  return (
    <aside className="flex h-full w-[76px] flex-col border-r border-white/5 bg-[#0A2342] text-white xl:w-64">
      <div className="flex h-16 items-center justify-center border-b border-white/10 px-3 xl:justify-start xl:gap-3 xl:px-5">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-ocean-500 shadow-lg shadow-ocean-500/20">
          <Waves className="h-5 w-5" />
        </div>
        <div className="hidden min-w-0 xl:block">
          <p className="truncate text-sm font-semibold tracking-wide">OceanLog</p>
          <p className="truncate text-xs text-white/50">Operator</p>
        </div>
      </div>

      <nav className="flex flex-1 flex-col gap-1 p-3">
        {navItems.map(({ to, label, icon: Icon, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            title={label}
            className={({ isActive }) =>
              cn(
                "flex items-center justify-center gap-3 rounded-xl px-3 py-3 text-sm font-medium transition-colors xl:justify-start",
                isActive
                  ? "bg-white/10 text-white shadow-inner"
                  : "text-white/55 hover:bg-white/5 hover:text-white",
              )
            }
          >
            <Icon className="h-5 w-5 shrink-0" />
            <span className="hidden xl:inline">{label}</span>
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-white/10 p-3">
        <div className="flex items-center justify-center gap-3 rounded-xl bg-white/5 px-3 py-3 xl:justify-start">
          <Anchor className="h-4 w-4 shrink-0 text-ocean-300" />
          <div className="hidden min-w-0 xl:block">
            <p className="truncate text-xs font-medium">
              {operator?.name ?? "Dive Center"}
            </p>
            <p className="truncate text-xs text-white/45">B2B Portal</p>
          </div>
        </div>
      </div>
    </aside>
  );
}
