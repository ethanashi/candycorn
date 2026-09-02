import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { AppIcon } from '@/core/icons';
import type { ScreenPath } from '@/core/routes';

interface ScreenLayoutProps {
  title: string;
  children: ReactNode;
  subtitle?: string;
  backTo?: ScreenPath;
  backLabel?: string;
  trailing?: ReactNode;
  className?: string;
}

export function ScreenLayout({
  title,
  children,
  subtitle,
  backTo,
  backLabel = 'Back',
  trailing,
  className = '',
}: ScreenLayoutProps) {
  return (
    <div className={`cc-screen ${className}`.trim()}>
      {backTo || trailing ? (
        <div className="cc-screen__topline">
          {backTo ? (
            <Link className="cc-icon-link" to={backTo} aria-label={backLabel}>
              <AppIcon name="back" size={22} />
            </Link>
          ) : <span />}
          {trailing}
        </div>
      ) : null}
      <header className="cc-screen__header">
        <h1>{title}</h1>
        {subtitle ? <p>{subtitle}</p> : null}
      </header>
      {children}
    </div>
  );
}
