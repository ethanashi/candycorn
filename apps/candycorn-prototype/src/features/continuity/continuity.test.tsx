import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DemoStateProvider, useDemoState } from '@/core/demo-state';
import { routePaths } from '@/core/routes';
import type { MoodSnapshot } from '@/core/types';
import { BringUpScreen, GoalsScreen, HistoryScreen, screens, SearchScreen } from './screens';

function renderScreen(component: React.ReactNode) {
  return render(<MemoryRouter><DemoStateProvider>{component}</DemoStateProvider></MemoryRouter>);
}

afterEach(cleanup);
beforeEach(() => { vi.stubGlobal('fetch', vi.fn(() => { throw new Error('Continuity views must not fetch.'); })); });

describe('continuity route registration', () => {
  it('registers the four canonical routes in their required positions', () => {
    expect(screens.map(({ path, order }) => [path, order])).toEqual([
      [routePaths.goals, 10],
      [routePaths.bringUp, 11],
      [routePaths.history, 20],
      [routePaths.search, 21],
    ]);
  });
});

describe('GoalsScreen', () => {
  it('keeps cadence order, exact counts, and provenance on every goal', () => {
    renderScreen(<GoalsScreen />);
    const sections = screen.getAllByRole('button', { expanded: true }).map((button) => button.textContent);
    expect(sections).toEqual(['Today1', 'This week1', 'This month0', 'Ongoing1', 'Homework1']);
    expect(screen.getAllByText(/You chose this|Candy Corn suggested this|Therapist assigned this/)).toHaveLength(4);
    expect(screen.getByText('Therapy on Sep 2 at 42:18')).toBeInTheDocument();
  });

  it('collapses without changing counts and toggles completion accessibly', async () => {
    const user = userEvent.setup();
    renderScreen(<GoalsScreen />);
    await user.click(screen.getByRole('button', { name: /Today 1/ }));
    expect(screen.queryByText('Notice when moving-forward guilt appears')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Today 1/ })).toHaveAttribute('aria-expanded', 'false');
    await user.click(screen.getByRole('button', { name: /Today 1/ }));
    const complete = screen.getByRole('button', { name: 'Mark complete: Notice when moving-forward guilt appears' });
    await user.click(complete);
    expect(screen.getByRole('button', { name: 'Mark incomplete: Notice when moving-forward guilt appears' })).toHaveAttribute('aria-pressed', 'true');
  });
});

describe('BringUpScreen', () => {
  it('shows therapy and TMS items, updates status, and guards an empty manual add', async () => {
    const user = userEvent.setup();
    renderScreen(<BringUpScreen />);
    expect(await screen.findByText('Share sleep and headache notes before the next TMS visit')).toBeInTheDocument();
    expect(screen.getAllByText('Therapy with Dr. Elena Park, Sep 9', { exact: false }).length).toBeGreaterThan(0);
    const discussed = screen.getByRole('button', { name: /Mark discussed: Is needing proof/ });
    await user.click(discussed);
    expect(screen.queryByText('Is needing proof that I could have played the part that keeps me stuck?')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Add to inbox' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Write what you want to bring up first.');
  });

  it('adds one manual user item and prevents a duplicate entry form', async () => {
    const user = userEvent.setup();
    renderScreen(<BringUpScreen />);
    await user.type(screen.getByLabelText('What do you want to remember?'), 'Ask whether exercise belongs in the plan');
    await user.click(screen.getByRole('button', { name: 'Add to inbox' }));
    expect(screen.getAllByText('Ask whether exercise belongs in the plan')).toHaveLength(1);
    expect(screen.getByText('You added this')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add to inbox' })).not.toBeInTheDocument();
  });
});

function EmptyMoodControl() {
  const { actions } = useDemoState();
  const emptyMood: MoodSnapshot = { mood: null, anxiety: null, energy: null, note: '', recordedAt: '2026-09-05T17:30:00-07:00' };
  return <button type="button" onClick={() => actions.saveMood(emptyMood)}>Remove mood record</button>;
}

describe('HistoryScreen', () => {
  it('filters all five categories locally and keeps matching route links', async () => {
    const user = userEvent.setup();
    renderScreen(<HistoryScreen />);
    const filters = screen.getByRole('tablist', { name: 'Filter history' });
    expect(within(filters).getAllByRole('tab')).toHaveLength(5);
    await user.click(within(filters).getByRole('tab', { name: 'Journal' }));
    expect(screen.getByRole('link', { name: /Football and feeling guilty/ })).toHaveAttribute('href', routePaths.journalDetail);
    await user.click(within(filters).getByRole('tab', { name: 'Mood' }));
    expect(screen.getByRole('link', { name: /Mood check-in/ })).toHaveAttribute('href', routePaths.checkIn);
    await user.click(within(filters).getByRole('tab', { name: 'Therapy' }));
    expect(screen.getByRole('link', { name: /Therapy with Dr. Elena Park/ })).toHaveAttribute('href', routePaths.therapySession);
    await user.click(within(filters).getByRole('tab', { name: 'TMS' }));
    expect(screen.getByRole('link', { name: /TMS post-session note/ })).toHaveAttribute('href', routePaths.tmsPost);
    await user.click(within(filters).getByRole('tab', { name: 'All' }));
    expect(screen.getAllByRole('link')).toHaveLength(5);
  });

  it('shows an honest empty filter when its shared mood record is absent', async () => {
    const user = userEvent.setup();
    render(<MemoryRouter><DemoStateProvider><EmptyMoodControl /><HistoryScreen /></DemoStateProvider></MemoryRouter>);
    await user.click(screen.getByRole('button', { name: 'Remove mood record' }));
    await user.click(screen.getByRole('tab', { name: 'Mood' }));
    expect(screen.getByRole('heading', { name: 'No mood entries yet' })).toBeInTheDocument();
  });
});

describe('SearchScreen', () => {
  it('matches football across journal, therapy, and talking points without fetching', async () => {
    const user = userEvent.setup();
    renderScreen(<SearchScreen />);
    expect(screen.getByText('Search runs on this device.')).toBeInTheDocument();
    await user.type(screen.getByRole('searchbox', { name: 'Search your thread' }), 'football');
    expect(screen.getByRole('link', { name: /Football and feeling guilty/ })).toHaveAttribute('href', routePaths.journalDetail);
    expect(screen.getByRole('link', { name: /Senior-year football in therapy/ })).toHaveAttribute('href', routePaths.therapySession);
    expect(screen.getByRole('link', { name: /Is needing proof that I could have played/ })).toHaveAttribute('href', routePaths.bringUp);
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('shows a real no-results state and clearing restores the prompt', () => {
    renderScreen(<SearchScreen />);
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'watermelon satellite' } });
    expect(screen.getByRole('heading', { name: 'No seeded memories match “watermelon satellite”' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Clear search' }));
    expect(screen.getByText('Search runs on this device.')).toBeInTheDocument();
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });
});
