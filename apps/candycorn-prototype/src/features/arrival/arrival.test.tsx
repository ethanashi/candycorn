import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { afterEach, describe, expect, it } from 'vitest';
import { DemoStateProvider, useDemoState } from '@/core/demo-state';
import { routePaths } from '@/core/routes';
import type { MoodSnapshot } from '@/core/types';
import { CaptureScreen, CheckInScreen, TodayScreen, WelcomeScreen } from './screens';

afterEach(cleanup);

function LocationProbe() {
  const location = useLocation();
  return <output aria-label="Current path">{location.pathname}</output>;
}

function renderRoute(component: React.ReactNode, initialPath: string) {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <DemoStateProvider>
        <Routes>
          <Route path="*" element={<>{component}<LocationProbe /></>} />
        </Routes>
      </DemoStateProvider>
    </MemoryRouter>,
  );
}

function NullMoodToday() {
  const { actions } = useDemoState();
  const empty: MoodSnapshot = { mood: null, anxiety: null, energy: null, note: '', recordedAt: '2026-09-05T17:30:00-07:00' };
  return (
    <>
      <button type="button" onClick={() => actions.saveMood(empty)}>Clear check-in</button>
      <TodayScreen />
    </>
  );
}

describe('WelcomeScreen', () => {
  it('walks through four trust pages, supports Back, and creates the vault', async () => {
    const user = userEvent.setup();
    renderRoute(<WelcomeScreen />, routePaths.welcome);

    expect(screen.getByRole('heading', { name: 'Your care, remembered' })).toBeInTheDocument();
    expect(screen.getByLabelText('Step 1 of 4')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Continue' }));
    expect(screen.getByRole('heading', { name: 'Private by design' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Back' }));
    expect(screen.getByRole('heading', { name: 'Your care, remembered' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Continue' }));
    await user.click(screen.getByRole('button', { name: 'Continue' }));
    expect(screen.getByRole('heading', { name: 'AI stays your choice' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Continue' }));
    expect(screen.getByText('It is not a therapist or a crisis service.', { exact: false })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Create my vault' }));
    expect(screen.getByLabelText('Current path')).toHaveTextContent(routePaths.today);
  });
});

describe('TodayScreen', () => {
  it('renders the seeded mood and links all initial and continuity actions', () => {
    renderRoute(<TodayScreen />, routePaths.today);

    expect(screen.getByText('6/10')).toBeInTheDocument();
    expect(screen.getByText('7/10')).toBeInTheDocument();
    expect(screen.getByText('4/10')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Open quick mood check-in' })).toHaveAttribute('href', routePaths.checkIn);
    expect(screen.getByRole('link', { name: /Talk/ })).toHaveAttribute('href', routePaths.journalVoice);
    expect(screen.getByRole('link', { name: /Write/ })).toHaveAttribute('href', routePaths.journalWrite);
    expect(screen.getByRole('link', { name: /Record appointment/ })).toHaveAttribute('href', routePaths.recordAppointment);
    expect(screen.getByRole('link', { name: /Therapy with Dr. Elena Park/ })).toHaveAttribute('href', routePaths.appointments);
    expect(screen.getByRole('link', { name: 'See goals' })).toHaveAttribute('href', routePaths.goals);
    expect(screen.getByRole('link', { name: 'Open inbox' })).toHaveAttribute('href', routePaths.bringUp);
    expect(screen.getByRole('link', { name: /Football and feeling guilty/ })).toHaveAttribute('href', routePaths.journalDetail);
  });

  it('renders a neutral null mood without streak language', async () => {
    const user = userEvent.setup();
    renderRoute(<NullMoodToday />, routePaths.today);
    await user.click(screen.getByRole('button', { name: 'Clear check-in' }));

    expect(screen.getByText('No check-in yet')).toBeInTheDocument();
    expect(screen.getAllByText('Not logged')).toHaveLength(3);
    expect(screen.queryByText(/streak/i)).not.toBeInTheDocument();
  });
});

describe('CheckInScreen', () => {
  it('saves a changed band and note into Today', async () => {
    const user = userEvent.setup();
    render(
      <MemoryRouter initialEntries={[routePaths.checkIn]}>
        <DemoStateProvider>
          <Routes>
            <Route path={routePaths.checkIn} element={<CheckInScreen />} />
            <Route path={routePaths.today} element={<><TodayScreen /><LocationProbe /></>} />
          </Routes>
        </DemoStateProvider>
      </MemoryRouter>,
    );

    await user.click(screen.getByRole('button', { name: 'Mood, 6. Increase value' }));
    await user.clear(screen.getByLabelText('Optional note'));
    await user.type(screen.getByLabelText('Optional note'), 'A quieter afternoon.');
    await user.click(screen.getByRole('button', { name: 'Save check-in' }));
    expect(screen.getByLabelText('Current path')).toHaveTextContent(routePaths.today);
    expect(document.querySelector('.cc-mood-band--mood')).toHaveTextContent('7/10');
  });

  it('cancels without mutating shared mood state', async () => {
    const user = userEvent.setup();
    render(
      <MemoryRouter initialEntries={[routePaths.checkIn]}>
        <DemoStateProvider>
          <Routes>
            <Route path={routePaths.checkIn} element={<CheckInScreen />} />
            <Route path={routePaths.today} element={<TodayScreen />} />
          </Routes>
        </DemoStateProvider>
      </MemoryRouter>,
    );

    await user.click(screen.getByRole('button', { name: 'Mood, 6. Increase value' }));
    await user.click(screen.getByRole('link', { name: 'Cancel' }));
    expect(screen.getByText('6/10')).toBeInTheDocument();
    expect(screen.queryByText('8/10')).not.toBeInTheDocument();
  });
});

describe('CaptureScreen', () => {
  it('links every capture mode to its canonical route', () => {
    renderRoute(<CaptureScreen />, routePaths.capture);

    expect(screen.getByRole('link', { name: /Talk/ })).toHaveAttribute('href', routePaths.journalVoice);
    expect(screen.getByRole('link', { name: /Write/ })).toHaveAttribute('href', routePaths.journalWrite);
    expect(screen.getByRole('link', { name: /Photograph a journal page/ })).toHaveAttribute('href', routePaths.journalPhoto);
    expect(screen.getByRole('link', { name: /Quick mood check-in/ })).toHaveAttribute('href', routePaths.checkIn);
  });
});
