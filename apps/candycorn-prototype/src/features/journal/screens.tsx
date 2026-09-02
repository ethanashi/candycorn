import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  KernelGlyph,
  ProvenanceLine,
  ScreenLayout,
  SelectableTabs,
  StatusNotice,
} from '@/components';
import { useDemoState } from '@/core/demo-state';
import { AppIcon } from '@/core/icons';
import { routePaths } from '@/core/routes';
import { defineScreens } from '@/core/screen-registry';
import { seededJournalEntries } from '@/core/seeded-data';
import type { DemoActions, DemoState, Goal, JournalEntry, TalkingPoint } from '@/core/types';
import journalPageUrl from '@/assets/journal-page.svg';
import './journal.css';

const recordingStartSeconds = 137;
const waveformBars = [22, 46, 64, 38, 76, 31, 58, 82, 54, 42, 70, 33, 61, 48, 78, 39, 66, 51, 72, 29, 59, 44, 81, 52, 68, 35, 63, 47, 75, 40, 57, 71];
const matchingJournalEntry = seededJournalEntries.find((entry) => entry.id === 'football-and-guilt');

if (matchingJournalEntry === undefined || matchingJournalEntry.original.length === 0) {
  throw new Error('The journal feature requires the football-and-guilt fixture.');
}

const journalEntry: JournalEntry = matchingJournalEntry;
const rawWriting = journalEntry.original;
const photoText = 'I keep thinking about senior year. I wanted the chance to prove I could have played. Exercise helped me get unstuck today, but then feeling better brought up guilt.';

const suggestionProvenance = {
  voice: 'candy-corn' as const,
  label: 'Candy Corn suggested this',
  detail: 'Based on your Sep 5 journal. Nothing is added until you choose it.',
  occurredAt: '2026-09-05T15:20:00-07:00',
  sourcePath: routePaths.journalDetail,
};

const talkingPointCandidates: readonly TalkingPoint[] = [
  {
    id: 'journal-proof-question',
    text: 'What would it mean now to stop needing proof that I could have played?',
    target: 'therapy',
    priority: 'important',
    status: 'open',
    provenance: suggestionProvenance,
  },
  {
    id: 'journal-better-guilt-question',
    text: 'Why can feeling better bring up guilt about moving forward?',
    target: 'therapy',
    priority: 'normal',
    status: 'open',
    provenance: suggestionProvenance,
  },
];

const goalCandidate: Goal = {
  id: 'journal-note-guilt-after-relief',
  text: 'Notice one moment when relief is followed by guilt',
  cadence: 'this-week',
  completed: false,
  provenance: suggestionProvenance,
};

function formatTimer(totalSeconds: number): string {
  if (!Number.isSafeInteger(totalSeconds) || totalSeconds < 0) {
    throw new RangeError('Recording time must be a non-negative whole number.');
  }
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function Waveform({ still = false }: { still?: boolean }) {
  if (waveformBars.length < 2 || waveformBars.length > 64) {
    throw new RangeError('The simulated waveform must stay within its fixed visual bounds.');
  }
  return (
    <div className={`cc-journal-waveform${still ? ' cc-journal-waveform--still' : ''}`} aria-label="Simulated audio waveform">
      {waveformBars.map((height, index) => (
        <span key={`${height}-${index}`} style={{ height: `${height}%`, animationDelay: `${index * -24}ms` }} />
      ))}
    </div>
  );
}

export function VoiceJournalScreen() {
  const navigate = useNavigate();
  const [status, setStatus] = useState<'recording' | 'saved'>('recording');
  const [seconds, setSeconds] = useState(recordingStartSeconds);
  const stoppedRef = useRef(false);

  useEffect(() => {
    if (status !== 'recording') return undefined;
    const intervalId = window.setInterval(() => setSeconds((value) => value + 1), 1_000);
    return () => window.clearInterval(intervalId);
  }, [status]);

  function stopRecording() {
    if (stoppedRef.current) return;
    stoppedRef.current = true;
    setStatus('saved');
  }

  if (status === 'saved') {
    return (
      <ScreenLayout title="Saved on this device" subtitle="Your simulated audio stays intact until you choose what happens next." backTo={routePaths.capture}>
        <div className="cc-journal-saved-audio">
          <KernelGlyph voice="user" size={20} />
          <div><strong>{formatTimer(seconds)}</strong><span>Voice journal, Sep 5</span></div>
          <button type="button" className="cc-journal-icon-button" aria-label="Play saved audio"><AppIcon name="play" size={20} /></button>
        </div>
        <div className="cc-journal-action-stack">
          <button type="button" className="cc-button cc-button--primary" onClick={() => navigate(routePaths.journalDetail)}>Transcribe</button>
          <button type="button" className="cc-button" onClick={() => navigate(routePaths.history, { state: { savedAudio: true } })}>Keep audio only</button>
        </div>
        <p className="cc-journal-privacy-copy">This prototype did not use your microphone or upload audio.</p>
      </ScreenLayout>
    );
  }

  return (
    <div className="cc-journal-recording" aria-label="Voice journal recording">
      <div className="cc-journal-recording__topline">
        <Link to={routePaths.capture} aria-label="Cancel recording"><AppIcon name="close" size={24} /></Link>
        <span>Cancel</span>
      </div>
      <header><h1>What’s going on?</h1><p>Private journal recording</p></header>
      <div className="cc-journal-recording__stage">
        <p>Simulated recording</p>
        <output aria-label="Recording duration">{formatTimer(seconds)}</output>
        <Waveform />
        <button type="button" className="cc-journal-stop" onClick={stopRecording}><AppIcon name="stop" size={18} />Stop</button>
      </div>
      <p className="cc-journal-privacy-copy">This prototype does not use your microphone. Audio is saved before any organization begins in the real app.</p>
    </div>
  );
}

type WritingResult = 'none' | 'rewrite' | 'summary';

export function TextJournalScreen() {
  const navigate = useNavigate();
  const [text, setText] = useState(rawWriting);
  const [savedOriginal, setSavedOriginal] = useState<string | null>(null);
  const [result, setResult] = useState<WritingResult>('none');
  const isEmpty = text.trim().length === 0;

  function saveOriginal() {
    if (isEmpty || savedOriginal !== null) return;
    setSavedOriginal(text);
    setResult('none');
  }

  if (savedOriginal !== null) {
    return (
      <ScreenLayout title="Your words are saved" subtitle="The original stays exactly as you wrote it." backTo={routePaths.capture}>
        <section className="cc-journal-original-block" aria-label="Saved original">
          <ProvenanceLine provenance={{ voice: 'user', label: 'You wrote this', detail: 'Journal, Sep 5 at 3:18 PM' }} />
          <p>{savedOriginal}</p>
        </section>
        <h2 className="cc-journal-section-title">What would help?</h2>
        <div className="cc-journal-choice-grid">
          <button type="button" onClick={() => setResult('rewrite')}>Rewrite clearly</button>
          <button type="button" onClick={() => setResult('summary')}>Summarize</button>
          <button type="button" onClick={() => navigate(routePaths.journalSuggestions)}>Find talking points</button>
          <button type="button" onClick={() => navigate(routePaths.journalDetail)}>Leave it alone</button>
        </div>
        {result === 'rewrite' ? <StatusNotice title="Clearer version"><p>{journalEntry.cleaned}</p><p>Your original above has not changed.</p></StatusNotice> : null}
        {result === 'summary' ? <StatusNotice title="Short summary"><p>{journalEntry.summary.join(' ')}</p><p>Your original above has not changed.</p></StatusNotice> : null}
      </ScreenLayout>
    );
  }

  return (
    <ScreenLayout title="Write it down" subtitle="Messy is welcome. This stays local in the prototype." backTo={routePaths.capture}>
      <label className="cc-journal-editor-label" htmlFor="journal-writing">Your journal</label>
      <textarea id="journal-writing" className="cc-journal-editor" value={text} onChange={(event) => setText(event.target.value)} autoFocus />
      {isEmpty ? <p className="cc-journal-inline-reason">Write something before saving. Nothing has been lost.</p> : null}
      <div className="cc-journal-editor-actions">
        <Link className="cc-button" to={routePaths.capture}>Cancel</Link>
        <button type="button" className="cc-button cc-button--primary" disabled={isEmpty} onClick={saveOriginal}>Save original</button>
      </div>
    </ScreenLayout>
  );
}

export function PhotoJournalScreen() {
  const navigate = useNavigate();
  const [captured, setCaptured] = useState(false);
  const [extractedText, setExtractedText] = useState(photoText);

  function retake() {
    if (!captured) return;
    setCaptured(false);
    setExtractedText(photoText);
  }

  if (captured) {
    return (
      <ScreenLayout title="Keep the original" subtitle="Edit the extracted words if needed. The photo will stay unchanged." backTo={routePaths.capture}>
        <div className="cc-journal-photo-comparison">
          <figure><img src={journalPageUrl} alt="Original photographed journal page about senior year football" /><figcaption>Original photo</figcaption></figure>
          <div><label htmlFor="extracted-journal">Extracted text</label><textarea id="extracted-journal" value={extractedText} onChange={(event) => setExtractedText(event.target.value)} /></div>
        </div>
        <div className="cc-journal-editor-actions">
          <button type="button" className="cc-button" onClick={retake}>Retake</button>
          <button type="button" className="cc-button cc-button--primary" onClick={() => navigate(routePaths.journalDetail)}>Keep this page</button>
        </div>
      </ScreenLayout>
    );
  }

  return (
    <ScreenLayout title="Photograph a page" subtitle="A simulation only. No camera permission is requested." backTo={routePaths.capture}>
      <div className="cc-journal-camera-frame">
        <span className="cc-journal-camera-frame__corner" aria-hidden="true" />
        <img src={journalPageUrl} alt="Journal page positioned inside a simulated camera frame" />
        <span>Line up the whole page</span>
      </div>
      <button type="button" className="cc-button cc-button--primary cc-journal-full-button" onClick={() => setCaptured(true)}><AppIcon name="camera" size={20} />Use photo</button>
    </ScreenLayout>
  );
}

type JournalTab = 'original' | 'cleaned' | 'summary';
const journalTabs = [
  { value: 'original', label: 'Original' },
  { value: 'cleaned', label: 'Cleaned' },
  { value: 'summary', label: 'Summary' },
] as const;

function JournalTabContent({ tab, entry }: { tab: JournalTab; entry: JournalEntry }) {
  if (tab === 'original') return <p className="cc-journal-prose">{entry.original}</p>;
  if (tab === 'cleaned') return <><p className="cc-journal-prose">{entry.cleaned}</p><p className="cc-journal-preservation-note">This version organizes your wording. The Original tab remains unchanged.</p></>;
  return <ul className="cc-journal-summary-list">{entry.summary.map((item) => <li key={item}><KernelGlyph voice="candy-corn" size={16} decorative /><span>{item}</span></li>)}</ul>;
}

export function JournalDetailScreen() {
  const [tab, setTab] = useState<JournalTab>('original');
  const provenance = tab === 'summary'
    ? { ...suggestionProvenance, detail: 'Organized from your Sep 5 voice journal.' }
    : { voice: 'user' as const, label: tab === 'original' ? 'You said this' : 'Your words, organized', detail: 'Voice journal, Sep 5 at 3:18 PM' };

  return (
    <ScreenLayout title="Football and guilt" backTo={routePaths.history} backLabel="Back to history" trailing={<Link className="cc-journal-more-link" to={routePaths.journalSuggestions}>More</Link>}>
      <SelectableTabs<JournalTab> items={journalTabs} value={tab} onChange={setTab} ariaLabel="Journal versions" />
      <section className="cc-journal-detail-panel" role="tabpanel" aria-label={`${journalTabs.find((item) => item.value === tab)?.label} journal version`}>
        <JournalTabContent tab={tab} entry={journalEntry} />
        <ProvenanceLine provenance={provenance} />
      </section>
      <Link className="cc-journal-suggestions-link" to={routePaths.journalSuggestions}>
        <KernelGlyph voice="candy-corn" size={18} decorative />
        <span><strong>Review possible next steps</strong><small>Suggestions stay separate until you add them.</small></span>
        <AppIcon name="chevronRight" size={20} />
      </Link>
    </ScreenLayout>
  );
}

interface SuggestionViewProps {
  state: DemoState;
  actions: DemoActions;
  onRetry?: () => void;
}

function SuggestionRow({ item, added, onAdd, actionLabel }: { item: TalkingPoint | Goal; added: boolean; onAdd: () => void; actionLabel: string }) {
  return (
    <li className="cc-journal-suggestion-row">
      <ProvenanceLine provenance={item.provenance} />
      <p>{item.text}</p>
      <button type="button" className="cc-journal-add-button" disabled={added} aria-pressed={added} onClick={onAdd}>{added ? <><AppIcon name="check" size={18} />Added</> : actionLabel}</button>
    </li>
  );
}

export function JournalSuggestionsView({ state, actions, onRetry }: SuggestionViewProps) {
  const [retryComplete, setRetryComplete] = useState(false);
  const addedPointIds = useMemo(() => new Set(state.talkingPoints.map((point) => point.id)), [state.talkingPoints]);
  const addedGoalIds = useMemo(() => new Set(state.goals.map((goal) => goal.id)), [state.goals]);

  if (state.ai.mode === 'off') {
    return <StatusNotice title="Organizing is off"><p>Your original journal is still readable and safe.</p><div className="cc-journal-notice-links"><Link to={routePaths.journalDetail}>Read original</Link><Link to={routePaths.settingsAi}>Open AI settings</Link></div></StatusNotice>;
  }
  if (!state.ai.routerAvailable) {
    return <StatusNotice title="Organization is unavailable"><p>Your original is safe.</p><button type="button" className="cc-journal-add-button" onClick={() => { setRetryComplete(true); onRetry?.(); }}>{retryComplete ? 'Still unavailable' : 'Try again'}</button><div className="cc-journal-notice-links"><Link to={routePaths.journalDetail}>Read original</Link></div></StatusNotice>;
  }

  return (
    <section className="cc-journal-suggestion-region" aria-label="Candy Corn suggestions">
      <h2>Possible next steps</h2>
      <p>These are suggestions, not advice. Add only what feels useful.</p>
      <ul>
        {talkingPointCandidates.map((candidate) => <SuggestionRow key={candidate.id} item={candidate} added={addedPointIds.has(candidate.id)} onAdd={() => actions.addTalkingPoint(candidate)} actionLabel="Add to next appointment" />)}
        <SuggestionRow item={goalCandidate} added={addedGoalIds.has(goalCandidate.id)} onAdd={() => actions.addGoal(goalCandidate)} actionLabel="Add as a goal" />
      </ul>
    </section>
  );
}

export function JournalSuggestionsScreen() {
  const { state, actions } = useDemoState();
  return (
    <ScreenLayout title="Suggestions" subtitle="Nothing here changes your original." backTo={routePaths.journalDetail}>
      <JournalSuggestionsView state={state} actions={actions} />
    </ScreenLayout>
  );
}

export const screens = defineScreens([
  { id: 'journalVoice', path: routePaths.journalVoice, title: 'Voice journal', reviewLabel: 'Voice journal', order: 5, primarySection: 'journal', showBottomNav: false, component: VoiceJournalScreen },
  { id: 'journalWrite', path: routePaths.journalWrite, title: 'Write a journal', reviewLabel: 'Text journal', order: 6, primarySection: 'journal', showBottomNav: false, component: TextJournalScreen },
  { id: 'journalPhoto', path: routePaths.journalPhoto, title: 'Photograph a journal page', reviewLabel: 'Photo journal', order: 7, primarySection: 'journal', showBottomNav: false, component: PhotoJournalScreen },
  { id: 'journalDetail', path: routePaths.journalDetail, title: 'Football and guilt', reviewLabel: 'Journal detail', order: 8, primarySection: 'journal', showBottomNav: true, component: JournalDetailScreen },
  { id: 'journalSuggestions', path: routePaths.journalSuggestions, title: 'Journal suggestions', reviewLabel: 'AI suggestions', order: 9, primarySection: 'journal', showBottomNav: true, component: JournalSuggestionsScreen },
]);
