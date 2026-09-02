import { createElement } from 'react';
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { AppShell, KernelGlyph } from '@/components';
import { routePaths } from '@/core/routes';
import {
  collectScreens,
  type PrototypeScreenDefinition,
  type PrototypeScreenModule,
} from '@/core/screen-registry';

const featureModules = import.meta.glob<PrototypeScreenModule>('./features/*/screens.tsx', { eager: true });
const discoveredScreens = collectScreens(featureModules);

function EmptyFoundation() {
  return (
    <div className="cc-system-message">
      <KernelGlyph voice="candy-corn" size={20} />
      <h1>The prototype foundation is ready</h1>
      <p>Feature screens appear here automatically as their modules are added.</p>
    </div>
  );
}

function NotFound({ screens }: { screens: readonly PrototypeScreenDefinition[] }) {
  return (
    <div className="cc-system-message">
      <KernelGlyph voice="candy-corn" size={20} />
      <h1>This screen is not in the prototype</h1>
      <p>The address may have changed. Your demo data is still here.</p>
      <div className="cc-system-message__actions">
        <Link className="cc-button cc-button--primary" to={routePaths.today}>Go to Today</Link>
        <details id="screen-index" className="cc-screen-index">
          <summary>Open screen index</summary>
          <nav aria-label="Available screens">
            {screens.map((screen) => <Link key={screen.id} to={screen.path}>{screen.reviewLabel}</Link>)}
          </nav>
        </details>
      </div>
    </div>
  );
}

export function App() {
  const location = useLocation();
  const activeScreen = discoveredScreens.find((screen) => screen.path === location.pathname);
  if (discoveredScreens.length === 0) {
    return <AppShell screens={discoveredScreens}><EmptyFoundation /></AppShell>;
  }
  const firstPath = discoveredScreens[0]?.path;
  if (firstPath === undefined) {
    throw new Error('Discovered screen collection became empty during render.');
  }
  return (
    <AppShell screens={discoveredScreens} activeScreen={activeScreen}>
      <Routes>
        <Route path="/" element={<Navigate replace to={firstPath} />} />
        {discoveredScreens.map((screen) => (
          <Route key={screen.id} path={screen.path} element={createElement(screen.component)} />
        ))}
        <Route path="*" element={<NotFound screens={discoveredScreens} />} />
      </Routes>
    </AppShell>
  );
}
