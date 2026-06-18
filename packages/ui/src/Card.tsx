import type { HTMLAttributes, ReactNode } from 'react';

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  title?: string;
  description?: string;
  footer?: ReactNode;
  children?: ReactNode;
}

export function Card({
  title,
  description,
  footer,
  children,
  className = '',
  ...props
}: CardProps) {
  return (
    <div
      className={[
        'rounded-lg border border-slate-200 bg-white shadow-sm',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      {...props}
    >
      {(title || description) && (
        <div className="border-b border-slate-100 px-4 py-3">
          {title && <h3 className="text-base font-semibold text-slate-900">{title}</h3>}
          {description && (
            <p className="mt-1 text-sm text-slate-600">{description}</p>
          )}
        </div>
      )}
      {children && <div className="px-4 py-4">{children}</div>}
      {footer && (
        <div className="border-t border-slate-100 px-4 py-3 text-sm text-slate-600">
          {footer}
        </div>
      )}
    </div>
  );
}
