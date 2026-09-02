import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DemoStateProvider } from '@/core/demo-state';
import { routePaths } from '@/core/routes';
import { createInitialDemoState, seededJournalEntries } from '@/core/seeded-data';
import type { DemoActions, DemoState } from '@/core/types';
import {
  JournalDetailScreen,
  JournalSuggestionsScreen,
  JournalSuggestionsView,
  PhotoJournalScreen,
  TextJournalScreen,
  VoiceJournalScreen,
} from '@/features/journal/screens';

afterEach(cleanup);

function renderRoute(element: React.ReactNode, path: string) {
  if (!path.startsWith('/')) throw new Error('Test routes must use canonical absolute paths.');
  return render(
    <MemoryRouter initialEntries={[path]}>
      <DemoStateProvider>
        <Routes>
          <Route path={path} element={element} />
          <Route path="*" element={<p>Navigation destination</p>} />
        </Routes>
      </DemoStateProvider>
    </MemoryRouter>,
  );
}

function createActions(): DemoActions {
  return {
    saveMood: vi.fn(),
    addGoal: vi.fn(),
    toggleGoal: vi.fn(),
    addTalkingPoint: vi.fn(),
    updateTalkingPointStatus: vi.fn(),
    setAiMode: vi.fn(),
    setAiProvider: vi.fn(),
    setConsentAcknowledged: vi.fn(),
    resetDemo: vi.fn(),
  };
}

function renderSavedWriting() {
  const view = renderRoute(<TextJournalScreen />, routePaths.journalWrite);
  fireEvent.click(screen.getByRole('button', { name: 'Save original' }));
  expect(screen.getByRole('heading', { name: 'Your words are saved' })).toBeInTheDocument();
  return view;
}

describe('voice journal', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: vi.fn() } });
  });

  afterEach(() => vi.useRealTimers());

  it('advances deterministically and clears its timer on unmount', () => {
    const clearIntervalSpy = vi.spyOn(window, 'clearInterval');
    const view = renderRoute(<VoiceJournalScreen />, routePaths.journalVoice);
    expect(screen.getByLabelText('Recording duration')).toHaveTextContent('02:17');
    act(() => vi.advanceTimersByTime(2_000));
    expect(screen.getByLabelText('Recording duration')).toHaveTextContent('02:19');
    view.unmount();
    expect(clearIntervalSpy).toHaveBeenCalled();
  });

  it('stops into a saved state without microphone access', () => {
    renderRoute(<VoiceJournalScreen />, routePaths.journalVoice);
    fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
    expect(screen.getByRole('heading', { name: 'Saved on this device' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Transcribe' })).toBeInTheDocument();
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
  });
});

describe('text journal', () => {
  it('guards an empty editor with a visible reason', () => {
    renderRoute(<TextJournalScreen />, routePaths.journalWrite);
    fireEvent.change(screen.getByLabelText('Your journal'), { target: { value: '   ' } });
    expect(screen.getByRole('button', { name: 'Save original' })).toBeDisabled();
    expect(screen.getByText('Write something before saving. Nothing has been lost.')).toBeVisible();
  });

  it('preserves the exact original and offers a separate rewrite', () => {
    renderSavedWriting();
    const original = seededJournalEntries[0]?.original;
    if (original === undefined) throw new Error('The journal fixture is required for this test.');
    expect(screen.getByText(original)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Rewrite clearly' }));
    expect(screen.getByRole('heading', { name: 'Clearer version' })).toBeInTheDocument();
    expect(screen.getByText(original)).toBeInTheDocument();
  });

  it('shows a deterministic summary without replacing the original', () => {
    renderSavedWriting();
    fireEvent.click(screen.getByRole('button', { name: 'Summarize' }));
    expect(screen.getByRole('heading', { name: 'Short summary' })).toBeInTheDocument();
    expect(screen.getByText('Your original above has not changed.')).toBeVisible();
  });

  it.each(['Find talking points', 'Leave it alone'])('navigates for the %s choice', (label) => {
    renderSavedWriting();
    fireEvent.click(screen.getByRole('button', { name: label }));
    expect(screen.getByText('Navigation destination')).toBeInTheDocument();
  });
});

describe('photo journal', () => {
  beforeEach(() => {
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: vi.fn() } });
  });

  it('retains the source while extracted text is edited, then supports retake', () => {
    renderRoute(<PhotoJournalScreen />, routePaths.journalPhoto);
    fireEvent.click(screen.getByRole('button', { name: 'Use photo' }));
    const original = screen.getByRole('img', { name: 'Original photographed journal page about senior year football' });
    const originalSource = original.getAttribute('src');
    fireEvent.change(screen.getByLabelText('Extracted text'), { target: { value: 'Corrected transcription.' } });
    expect(screen.getByDisplayValue('Corrected transcription.')).toBeInTheDocument();
    expect(original).toHaveAttribute('src', originalSource);
    fireEvent.click(screen.getByRole('button', { name: 'Retake' }));
    expect(screen.getByRole('button', { name: 'Use photo' })).toBeInTheDocument();
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
  });
});

describe('journal detail', () => {
  it('keeps Original as the default and supports keyboard tab changes', () => {
    renderRoute(<JournalDetailScreen />, routePaths.journalDetail);
    const originalTab = screen.getByRole('tab', { name: 'Original' });
    expect(originalTab).toHaveAttribute('aria-selected', 'true');
    fireEvent.keyDown(originalTab, { key: 'ArrowRight' });
    const cleanedTab = screen.getByRole('tab', { name: 'Cleaned' });
    expect(cleanedTab).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('This version organizes your wording. The Original tab remains unchanged.')).toBeVisible();
    fireEvent.keyDown(cleanedTab, { key: 'ArrowRight' });
    expect(screen.getByRole('tab', { name: 'Summary' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('Feeling better was followed by guilt.')).toBeVisible();
  });
});

describe('journal suggestions', () => {
  it('explains AI Off while preserving a route to the original', () => {
    const state: DemoState = { ...createInitialDemoState(), ai: { mode: 'off', provider: 'off', routerAvailable: true } };
    render(<MemoryRouter><JournalSuggestionsView state={state} actions={createActions()} /></MemoryRouter>);
    expect(screen.getByRole('heading', { name: 'Organizing is off' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Read original' })).toHaveAttribute('href', routePaths.journalDetail);
  });

  it('keeps the original safe when the router is unavailable and retries harmlessly', () => {
    const retry = vi.fn();
    const state: DemoState = { ...createInitialDemoState(), ai: { mode: 'organizer', provider: 'router', routerAvailable: false } };
    render(<MemoryRouter><JournalSuggestionsView state={state} actions={createActions()} onRetry={retry} /></MemoryRouter>);
    expect(screen.getByText('Your original is safe.')).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(screen.getByRole('button', { name: 'Still unavailable' })).toBeInTheDocument();
    expect(retry).toHaveBeenCalledTimes(1);
  });

  it('adds each deterministic candidate once and settles the control safely', () => {
    renderRoute(<JournalSuggestionsScreen />, routePaths.journalSuggestions);
    const addButtons = screen.getAllByRole('button', { name: /Add to next appointment|Add as a goal/ });
    expect(addButtons).toHaveLength(3);
    fireEvent.click(addButtons[0]!);
    expect(screen.getByRole('button', { name: 'Added' })).toBeDisabled();
    expect(screen.getAllByText('What would it mean now to stop needing proof that I could have played?')).toHaveLength(1);
  });
});
