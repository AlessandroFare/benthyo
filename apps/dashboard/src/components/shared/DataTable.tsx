import {
  type ReactNode,
  useMemo,
  useState,
  type Key,
  type CSSProperties,
} from "react";
import { motion } from "framer-motion";
import { ArrowDown, ArrowUp, ArrowUpDown, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cn } from "@/lib/utils";

/**
 * Generic, animated data table.
 *
 * - Column-level sorting (clickable headers).
 * - Quick filter (top-right search input).
 * - Rows animate in on mount with a 25 ms stagger.
 * - No row-enter animation when `data` is the same reference between
 *   renders, so re-fetches don't replay the dance on every poll.
 *
 * Generic constraints:
 *   - T must be a record with a stable `id` field (any value type).
 *   - `id` is used as the React key.
 *
 * @example
 *   <DataTable<Species>
 *     data={species}
 *     columns={[
 *       { key: "scientific_name", header: "Name", cell: (s) => s.scientific_name, sortable: true },
 *       { key: "sighting_count",  header: "Sightings", cell: (s) => s.sighting_count, sortable: true, align: "right" },
 *     ]}
 *     searchPlaceholder="Search species..."
 *     emptyState={<EmptyState ... />}
 *     rowClassName={(s) => s.conservation_status === "CR" ? "text-rose-300" : undefined}
 *   />
 */

export interface DataTableColumn<T> {
  /** Unique key for React + sort bookkeeping. */
  key: string;
  /** Header label. */
  header: string;
  /** Renderer for the cell value. */
  cell: (row: T) => ReactNode;
  /** Make this column clickable for sort. Default false. */
  sortable?: boolean;
  /** Custom value extractor for sorting. Defaults to the rendered cell. */
  sortValue?: (row: T) => string | number | null | undefined;
  /** Tailwind class for the cell (alignment, width, etc.). */
  className?: string;
  /** Header alignment. */
  align?: "left" | "right" | "center";
  /** Header width. */
  width?: string;
}

export interface DataTableProps<T> {
  data: readonly T[];
  columns: DataTableColumn<T>[];
  /** Row identifier extractor. Defaults to `row.id`. */
  rowKey?: (row: T) => Key;
  /** Placeholder for the search input. If absent, no search is shown. */
  searchPlaceholder?: string;
  /** Initial search value. */
  initialSearch?: string;
  /** Number of items to render per page. 0 = no pagination. */
  pageSize?: number;
  /** Rendered inside the card body when there's no data. */
  emptyState?: ReactNode;
  /** Class name for the wrapping div. */
  className?: string;
  /** Class name for the `<tr>` element. */
  rowClassName?: (row: T) => string | undefined;
}

type SortDir = "asc" | "desc" | null;

const rowVariants = {
  hidden: { opacity: 0, y: 4 },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: { delay: i * 0.025, duration: 0.22, ease: "easeOut" },
  }),
};

export function DataTable<T extends { id?: Key }>({
  data,
  columns,
  rowKey,
  searchPlaceholder,
  initialSearch = "",
  pageSize = 0,
  emptyState,
  className,
  rowClassName,
}: DataTableProps<T>) {
  const [search, setSearch] = useState(initialSearch);
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDir>(null);

  const keyExtractor = useMemo(
    () => rowKey ?? ((row: T) => (row.id as Key) ?? Math.random()),
    [rowKey],
  );

  const processed = useMemo(() => {
    let rows: T[] = [...data];
    if (search.trim()) {
      const needle = search.trim().toLowerCase();
      rows = rows.filter((r) =>
        columns.some((c) => {
          const v = c.sortValue ? c.sortValue(r) : c.cell(r);
          return v != null && String(v).toLowerCase().includes(needle);
        }),
      );
    }
    if (sortKey && sortDir) {
      const col = columns.find((c) => c.key === sortKey);
      if (col) {
        const extractor = col.sortValue ?? ((r: T) => col.cell(r) as unknown);
        rows = [...rows].sort((a, b) => {
          const av = extractor(a) as string | number | null | undefined;
          const bv = extractor(b) as string | number | null | undefined;
          if (av == null && bv == null) return 0;
          if (av == null) return 1;
          if (bv == null) return -1;
          if (typeof av === "number" && typeof bv === "number") {
            return sortDir === "asc" ? av - bv : bv - av;
          }
          const aStr = String(av).toLowerCase();
          const bStr = String(bv).toLowerCase();
          if (aStr < bStr) return sortDir === "asc" ? -1 : 1;
          if (aStr > bStr) return sortDir === "asc" ? 1 : -1;
          return 0;
        });
      }
    }
    if (pageSize > 0) {
      rows = rows.slice(0, pageSize);
    }
    return rows;
  }, [data, columns, search, sortKey, sortDir, pageSize]);

  function onHeaderClick(col: DataTableColumn<T>) {
    if (!col.sortable) return;
    if (sortKey !== col.key) {
      setSortKey(col.key);
      setSortDir("asc");
      return;
    }
    if (sortDir === "asc") setSortDir("desc");
    else if (sortDir === "desc") {
      setSortDir(null);
      setSortKey(null);
    } else setSortDir("asc");
  }

  return (
    <div className={cn("space-y-3", className)}>
      {searchPlaceholder && (
        <div className="relative w-full sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder={searchPlaceholder}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            aria-label={searchPlaceholder}
            className="h-9 pl-8 text-sm"
          />
        </div>
      )}

      {processed.length === 0 ? (
        emptyState ?? (
          <div className="rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
            No data
          </div>
        )
      ) : (
        <Table>
          <TableHeader>
            <TableRow className="border-border hover:bg-transparent">
              {columns.map((c) => {
                const isSorted = sortKey === c.key && sortDir != null;
                const align = c.align ?? "left";
                return (
                  <TableHead
                    key={c.key}
                    aria-sort={c.sortable ? (isSorted ? (sortDir === "asc" ? "ascending" : "descending") : "none") : undefined}
                    className={cn(
                      "text-muted-foreground",
                      align === "right" && "text-right",
                      align === "center" && "text-center",
                      c.sortable && "cursor-pointer select-none transition-colors hover:text-foreground",
                      c.className,
                    )}
                    style={c.width ? ({ width: c.width } as CSSProperties) : undefined}
                    onClick={() => onHeaderClick(c)}
                  >
                    <span className="inline-flex items-center gap-1">
                      {c.header}
                      {c.sortable && (
                        isSorted ? (
                          sortDir === "asc" ? (
                            <ArrowUp className="h-3 w-3" />
                          ) : (
                            <ArrowDown className="h-3 w-3" />
                          )
                        ) : (
                          <ArrowUpDown className="h-3 w-3 opacity-30" />
                        )
                      )}
                    </span>
                  </TableHead>
                );
              })}
            </TableRow>
          </TableHeader>
          <TableBody>
            {processed.map((row, i) => (
              <motion.tr
                key={keyExtractor(row)}
                custom={i}
                initial="hidden"
                animate="visible"
                variants={rowVariants}
                className={cn("border-border transition-colors", rowClassName?.(row))}
              >
                {columns.map((c) => {
                  const align = c.align ?? "left";
                  return (
                    <TableCell
                      key={c.key}
                      className={cn(
                        align === "right" && "text-right",
                        align === "center" && "text-center",
                        c.className,
                      )}
                    >
                      {c.cell(row)}
                    </TableCell>
                  );
                })}
              </motion.tr>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
