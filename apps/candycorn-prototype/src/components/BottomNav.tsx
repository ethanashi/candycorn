import { NavLink } from 'react-router-dom';
import { AppIcon, type AppIconName } from '@/core/icons';
import { routePaths } from '@/core/routes';
import type { PrimarySection } from '@/core/screen-registry';

const destinations: readonly {
  section: Exclude<PrimarySection, null>;
  label: string;
  path: string;
  icon: AppIconName;
}[] = [
  { section: 'today', label: 'Today', path: routePaths.today, icon: 'home' },
  { section: 'journal', label: 'Journal', path: routePaths.capture, icon: 'journal' },
  { section: 'prepare', label: 'Prepare', path: routePaths.prepareTherapy, icon: 'prepare' },
  { section: 'history', label: 'History', path: routePaths.history, icon: 'history' },
  { section: 'settings', label: 'Settings', path: routePaths.settingsPrivacy, icon: 'settings' },
];

export function BottomNav({ activeSection }: { activeSection: PrimarySection }) {
  return (
    <nav className="cc-bottom-nav" aria-label="Primary navigation">
      {destinations.map((destination) => (
        <NavLink
          key={destination.section}
          to={destination.path}
          className={`cc-bottom-nav__item${activeSection === destination.section ? ' cc-bottom-nav__item--active' : ''}`}
          aria-current={activeSection === destination.section ? 'page' : undefined}
        >
          <AppIcon name={destination.icon} size={20} strokeWidth={activeSection === destination.section ? 2.4 : 1.8} />
          <span>{destination.label}</span>
        </NavLink>
      ))}
    </nav>
  );
}
