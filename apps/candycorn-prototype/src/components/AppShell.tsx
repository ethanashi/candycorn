import { useEffect, useRef, type ReactNode } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { BottomNav } from '@/components/BottomNav';
import type { PrototypeScreenDefinition } from '@/core/screen-registry';

interface AppShellProps {
  children: ReactNode;
  screens: readonly PrototypeScreenDefinition[];
  activeScreen?: PrototypeScreenDefinition | undefined;
}

export function AppShell({ children, screens, activeScreen }: AppShellProps) {
  const location = useLocation();
  const mainRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const main = mainRef.current;
    if (main === null) return;
    main.scrollTop = 0;
    main.focus({ preventScroll: true });
    document.title = activeScreen ? `${activeScreen.title} | Candy Corn` : 'Candy Corn';
  }, [location.pathname, activeScreen]);

  return (
    <div className="cc-review-shell">
      <aside className="cc-review-rail" aria-label="Prototype screen index">
        <div className="cc-review-rail__heading">
          <span className="cc-review-rail__mark" aria-hidden="true" />
          <div>
            <strong>Candy Corn</strong>
            <span>Patient prototype</span>
          </div>
        </div>
        <nav>
          {screens.map((screen) => (
            <NavLink key={screen.id} to={screen.path}>
              <span>{String(screen.order).padStart(2, '0')}</span>
              {screen.reviewLabel}
            </NavLink>
          ))}
        </nav>
      </aside>
      <div className="cc-stage-wrap">
        <div className="cc-phone-stage">
          <main
            ref={mainRef}
            className={`cc-app-main${activeScreen?.showBottomNav ? ' cc-app-main--with-nav' : ''}`}
            tabIndex={-1}
          >
            {children}
          </main>
          {activeScreen?.showBottomNav ? <BottomNav activeSection={activeScreen.primarySection} /> : null}
        </div>
      </div>
    </div>
  );
}
