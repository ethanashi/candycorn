import { cleanup, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DemoStateProvider, useDemoState } from '@/core/demo-state';
import { routePaths } from '@/core/routes';
import {
  AiSettingsPanel,
  PrepareTherapyScreen,
  PrepareTmsScreen,
  screens,
  SettingsAiScreen,
  SettingsDataScreen,
  SettingsPrivacyScreen,
} from './screens';

function renderScreen(component: React.ReactNode) {
  return render(<MemoryRouter><DemoStateProvider>{component}</DemoStateProvider></MemoryRouter>);
}

function StateProbe() {
  const { state } = useDemoState();
  return <output aria-label="Demo state">{state.ai.mode}:{state.ai.provider}:{state.goals.filter((goal) => goal.completed).length}</output>;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(() => { throw new Error('Preparation and settings must not fetch.'); }));
});

describe('preparation and settings route registration', () => {
  it('registers the five canonical routes in their required positions', () => {
    expect(screens.map(({ path, order }) => [path, order])).toEqual([
      [routePaths.prepareTherapy, 18],
      [routePaths.prepareTms, 19],
      [routePaths.settingsPrivacy, 22],
      [routePaths.settingsAi, 23],
      [routePaths.settingsData, 24],
    ]);
  });
});

describe('PrepareTherapyScreen', () => {
  it('renders the waiting-room brief with provenance on every line', () => {
    const { container } = renderScreen(<PrepareTherapyScreen />);
    expect(screen.getByRole('heading', { name: 'Walk in knowing what matters' })).toBeInTheDocument();
    expect(screen.getByText(/finished the senior-year narrative/)).toBeInTheDocument();
    expect(screen.getByText(/do not show that exercise caused the change/)).toBeInTheDocument();
    expect(screen.getByText(/Keep noticing moving-forward guilt/)).toBeInTheDocument();
    expect(screen.getByText(/Last time we stopped at junior year/)).toBeInTheDocument();
    expect(container.querySelectorAll('.cc-brief-line')).toHaveLength(5);
    expect(container.querySelectorAll('.cc-brief-line .cc-provenance-line')).toHaveLength(5);
    expect(container.querySelectorAll('.cc-brief-line .cc-kernel-glyph')).toHaveLength(5);
  });

  it('saves edited prose and returns to reading mode', async () => {
    const user = userEvent.setup();
    renderScreen(<PrepareTherapyScreen />);
    await user.click(screen.getByRole('button', { name: 'Edit brief' }));
    const question = screen.getByLabelText('A question you pinned');
    await user.clear(question);
    await user.type(question, 'Can we talk about why feeling better brings up guilt?');
    await user.click(screen.getByRole('button', { name: 'Save brief' }));
    expect(screen.getByRole('heading', { name: 'Walk in knowing what matters' })).toBeInTheDocument();
    expect(screen.getByText('Can we talk about why feeling better brings up guilt?')).toBeInTheDocument();
  });

  it('cancels without replacing the saved brief and rejects blank sections', async () => {
    const user = userEvent.setup();
    renderScreen(<PrepareTherapyScreen />);
    await user.click(screen.getByRole('button', { name: 'Edit brief' }));
    const opening = screen.getByLabelText('A possible opening');
    await user.clear(opening);
    await user.click(screen.getByRole('button', { name: 'Save brief' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Keep a short note in every section');
    await user.type(opening, 'A replacement that should be cancelled.');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(screen.getByText(/I finished that part, and I realized/)).toBeInTheDocument();
    expect(screen.queryByText('A replacement that should be cancelled.')).not.toBeInTheDocument();
  });
});

describe('PrepareTmsScreen', () => {
  it('keeps user and provider voices distinct and makes no causal or treatment claim', () => {
    const { container } = renderScreen(<PrepareTmsScreen />);
    expect(screen.getByText('Distress was not recorded.', { exact: false })).toBeInTheDocument();
    expect(screen.getByText(/do not show that TMS caused a mood change/)).toBeInTheDocument();
    expect(screen.getByText(/does not create treatment provocations/)).toBeInTheDocument();
    expect(screen.getByText('Dr. Elena Park asked you to notice this')).toBeInTheDocument();
    expect(container.querySelector('[data-voice="provider"]')).toBeInTheDocument();
    expect(container.querySelectorAll('[data-voice="user"]').length).toBeGreaterThanOrEqual(2);
    expect(screen.getByRole('link', { name: 'Open pre-session capture' })).toHaveAttribute('href', routePaths.tmsPre);
    expect(screen.getByRole('link', { name: 'Open post-session capture' })).toHaveAttribute('href', routePaths.tmsPost);
  });
});

describe('SettingsPrivacyScreen', () => {
  it('states the device, upload, and retention truth plainly', () => {
    renderScreen(<SettingsPrivacyScreen />);
    expect(screen.getByText('Stored on this device')).toBeInTheDocument();
    expect(screen.getByText('Cloud upload: only when AI is on')).toBeInTheDocument();
    expect(screen.getByText('Raw audio retention: you decide')).toBeInTheDocument();
    expect(screen.getByText(/encrypted vault on this phone/)).toBeInTheDocument();
    expect(screen.getByText(/not a therapist, medical advice, or a crisis service/)).toBeInTheDocument();
  });
});

describe('SettingsAiScreen', () => {
  it('starts in Organizer with truthful first-version router status', () => {
    renderScreen(<SettingsAiScreen />);
    expect(screen.getByRole('tab', { name: 'Organizer' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('radio', { name: /Router/ })).toBeChecked();
    expect(screen.getByText('Journal intelligence: Cloud (router)')).toBeInTheDocument();
    expect(screen.getByText('Voice transcription: Cloud (router)')).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /On-device when available/ })).toBeDisabled();
  });

  it('moves through every active mode and provider state, with Off forcing provider Off', async () => {
    const user = userEvent.setup();
    renderScreen(<SettingsAiScreen />);
    await user.click(screen.getByRole('tab', { name: 'Off' }));
    expect(screen.getByRole('radio', { name: /Off No AI processing/ })).toBeChecked();
    expect(screen.getByText('Nothing is sent for AI processing.')).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Organizer' }));
    expect(screen.getByRole('radio', { name: /Off No AI processing/ })).toBeChecked();
    await user.click(screen.getByRole('radio', { name: /Router/ }));
    expect(screen.getByText(/Selected journal text and selected audio/)).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Reflection' }));
    expect(screen.getByText(/transcript excerpts/)).toBeInTheDocument();
    await user.click(screen.getByRole('radio', { name: /Off No AI processing/ }));
    expect(screen.getByText('Nothing is sent for AI processing.')).toBeInTheDocument();
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('shows the unavailable-router recovery while preserving originals', () => {
    renderScreen(<AiSettingsPanel routerAvailableOverride={false} />);
    expect(screen.getByRole('heading', { name: 'Cloud router unavailable' })).toBeInTheDocument();
    expect(screen.getByText(/original journals, transcripts, and audio remain available/)).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /Router/ })).toBeDisabled();
  });
});

describe('SettingsDataScreen', () => {
  it('selects retention locally and keeps export an honest preview', async () => {
    const user = userEvent.setup();
    const setItem = vi.spyOn(Storage.prototype, 'setItem');
    renderScreen(<SettingsDataScreen />);
    expect(screen.getByRole('radio', { name: /Ask every time/ })).toBeChecked();
    await user.click(screen.getByRole('radio', { name: /Delete after transcript verification/ }));
    expect(screen.getByRole('radio', { name: /Delete after transcript verification/ })).toBeChecked();
    expect(screen.getByText('Export builds a readable archive of your originals and notes.')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Preview archive contents' }));
    expect(screen.getByText('Original journals and organized copies')).toBeInTheDocument();
    expect(setItem).not.toHaveBeenCalled();
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('requires explicit confirmation before resetting shared demo state', async () => {
    const user = userEvent.setup();
    renderScreen(<><SettingsDataScreen /><StateProbe /></>);
    expect(screen.getByLabelText('Demo state')).toHaveTextContent('organizer:router:1');
    await user.click(screen.getByRole('button', { name: 'Reset demo' }));
    expect(screen.getByRole('group', { name: 'Confirm reset demo' })).toBeInTheDocument();
    await user.click(within(screen.getByRole('group', { name: 'Confirm reset demo' })).getByRole('button', { name: 'Cancel' }));
    expect(screen.queryByRole('group', { name: 'Confirm reset demo' })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Reset demo' }));
    await user.click(screen.getByRole('button', { name: 'Reset now' }));
    expect(screen.getByText('Seeded demo restored.')).toBeInTheDocument();
    expect(screen.getByLabelText('Demo state')).toHaveTextContent('organizer:router:1');
  });
});
