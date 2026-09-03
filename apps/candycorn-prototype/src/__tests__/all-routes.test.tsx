import { cleanup, render, screen, within } from '@testing-library/react';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it } from 'vitest';
import { App } from '@/App';
import { DemoStateProvider } from '@/core/demo-state';
import { collectScreens, type PrimarySection, type PrototypeScreenModule } from '@/core/screen-registry';
import { routePaths, type ScreenId, type ScreenPath } from '@/core/routes';
import { screens as arrivalScreens } from '@/features/arrival/screens';
import { screens as careScreens } from '@/features/care/screens';
import { screens as continuityScreens } from '@/features/continuity/screens';
import { screens as journalScreens } from '@/features/journal/screens';
import { screens as preparationSettingsScreens } from '@/features/preparation-settings/screens';

afterEach(cleanup);

interface ExpectedScreen {
  id: ScreenId;
  path: ScreenPath;
  order: number;
  primarySection: PrimarySection;
}

const expectedScreens: readonly ExpectedScreen[] = [
  { id: 'welcome', path: routePaths.welcome, order: 1, primarySection: null },
  { id: 'today', path: routePaths.today, order: 2, primarySection: 'today' },
  { id: 'checkIn', path: routePaths.checkIn, order: 3, primarySection: 'today' },
  { id: 'capture', path: routePaths.capture, order: 4, primarySection: 'journal' },
  { id: 'journalVoice', path: routePaths.journalVoice, order: 5, primarySection: 'journal' },
  { id: 'journalWrite', path: routePaths.journalWrite, order: 6, primarySection: 'journal' },
  { id: 'journalPhoto', path: routePaths.journalPhoto, order: 7, primarySection: 'journal' },
  { id: 'journalDetail', path: routePaths.journalDetail, order: 8, primarySection: 'journal' },
  { id: 'journalSuggestions', path: routePaths.journalSuggestions, order: 9, primarySection: 'journal' },
  { id: 'goals', path: routePaths.goals, order: 10, primarySection: 'today' },
  { id: 'bringUp', path: routePaths.bringUp, order: 11, primarySection: 'today' },
  { id: 'appointments', path: routePaths.appointments, order: 12, primarySection: 'today' },
  { id: 'recordAppointment', path: routePaths.recordAppointment, order: 13, primarySection: null },
  { id: 'activeAppointment', path: routePaths.activeAppointment, order: 14, primarySection: null },
  { id: 'therapySession', path: routePaths.therapySession, order: 15, primarySection: 'history' },
  { id: 'tmsPre', path: routePaths.tmsPre, order: 16, primarySection: 'prepare' },
  { id: 'tmsPost', path: routePaths.tmsPost, order: 17, primarySection: 'history' },
  { id: 'prepareTherapy', path: routePaths.prepareTherapy, order: 18, primarySection: 'prepare' },
  { id: 'prepareTms', path: routePaths.prepareTms, order: 19, primarySection: 'prepare' },
  { id: 'history', path: routePaths.history, order: 20, primarySection: 'history' },
  { id: 'search', path: routePaths.search, order: 21, primarySection: 'history' },
  { id: 'settingsPrivacy', path: routePaths.settingsPrivacy, order: 22, primarySection: 'settings' },
  { id: 'settingsAi', path: routePaths.settingsAi, order: 23, primarySection: 'settings' },
  { id: 'settingsData', path: routePaths.settingsData, order: 24, primarySection: 'settings' },
] as const;

const modules: Readonly<Record<string, PrototypeScreenModule>> = {
  arrival: { screens: arrivalScreens },
  care: { screens: careScreens },
  continuity: { screens: continuityScreens },
  journal: { screens: journalScreens },
  preparationSettings: { screens: preparationSettingsScreens },
};

describe('complete prototype route inventory', () => {
  it('discovers exactly the canonical 24 screens with unique registry metadata', () => {
    const discovered = collectScreens(modules);
    const actual = discovered.map(({ id, path, order, primarySection }) => ({ id, path, order, primarySection }));

    expect(Object.keys(routePaths)).toHaveLength(24);
    expect(discovered).toHaveLength(24);
    expect(actual).toEqual(expectedScreens);
    expect(new Set(discovered.map(({ id }) => id)).size).toBe(24);
    expect(new Set(discovered.map(({ path }) => path)).size).toBe(24);
    expect(new Set(discovered.map(({ order }) => order)).size).toBe(24);
    expect(discovered.every(({ component }) => typeof component === 'function')).toBe(true);
  });

  it.each(expectedScreens)('renders $id at $path', ({ id }) => {
    const definition = collectScreens(modules).find((candidate) => candidate.id === id);
    expect(definition).toBeDefined();
    if (definition === undefined) throw new Error(`Missing screen definition for ${id}.`);

    const view = render(
      <MemoryRouter>
        <DemoStateProvider>{createElement(definition.component)}</DemoStateProvider>
      </MemoryRouter>,
    );
    expect(view.container.querySelector('h1')).not.toBeNull();
  });

  it('lists every discovered screen once in the desktop review rail', () => {
    render(
      <MemoryRouter initialEntries={[routePaths.today]}>
        <DemoStateProvider><App /></DemoStateProvider>
      </MemoryRouter>,
    );
    const rail = screen.getByRole('complementary', { name: 'Prototype screen index' });
    const links = within(rail).getAllByRole('link');

    expect(links).toHaveLength(24);
    expectedScreens.forEach(({ path }, index) => {
      expect(links[index]).toHaveAttribute('href', path);
      expect(links[index]).toHaveTextContent(String(index + 1).padStart(2, '0'));
    });
  });
});
