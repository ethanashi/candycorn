import { useRef, useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { KernelGlyph, MoodKernel, ProvenanceLine, ScreenLayout } from '@/components';
import { useDemoState } from '@/core/demo-state';
import { AppIcon, type AppIconName } from '@/core/icons';
import { routePaths } from '@/core/routes';
import { defineScreens } from '@/core/screen-registry';
import type { MoodSnapshot } from '@/core/types';
import './arrival.css';

const onboardingPages = [
  {
    title: 'Your care, remembered',
    copy: 'Keep the threads between journals, goals, and appointments in one private place.',
    detail: 'Candy Corn helps you carry what mattered into the next conversation.',
    voice: 'user',
  },
  {
    title: 'Private by design',
    copy: 'Your vault is designed to keep originals and recordings on your device.',
    detail: 'This prototype uses fictional data and does not create an account or upload anything.',
    voice: 'provider',
  },
  {
    title: 'AI stays your choice',
    copy: 'Turn organization off, or choose when a journal entry is sent to the cloud router.',
    detail: 'Your original stays readable even when AI is off.',
    voice: 'candy-corn',
  },
  {
    title: 'Support, with boundaries',
    copy: 'Candy Corn can help you remember and prepare. It is not a therapist or a crisis service.',
    detail: 'If you are in immediate danger, contact local emergency services or a crisis line.',
    voice: 'provider',
  },
] as const;

const captureChoices: readonly {
  title: string;
  detail: string;
  to: typeof routePaths.journalVoice | typeof routePaths.journalWrite | typeof routePaths.journalPhoto | typeof routePaths.checkIn;
  icon: AppIconName;
}[] = [
  { title: 'Talk', detail: 'Say it as it comes. Keep the audio or organize it later.', to: routePaths.journalVoice, icon: 'microphone' },
  { title: 'Write', detail: 'Start with your own words in a quiet text editor.', to: routePaths.journalWrite, icon: 'pencil' },
  { title: 'Photograph a journal page', detail: 'Keep the original page beside extracted text.', to: routePaths.journalPhoto, icon: 'camera' },
  { title: 'Quick mood check-in', detail: 'Log mood, anxiety, and energy from 1 to 10.', to: routePaths.checkIn, icon: 'checkCircle' },
];

function WelcomeProgress({ pageIndex }: { pageIndex: number }) {
  return (
    <div className="cc-arrival-progress" aria-label={`Step ${pageIndex + 1} of ${onboardingPages.length}`}>
      {onboardingPages.map((page, index) => (
        <span key={page.title} className={index <= pageIndex ? 'cc-arrival-progress__step cc-arrival-progress__step--complete' : 'cc-arrival-progress__step'} />
      ))}
    </div>
  );
}

export function WelcomeScreen() {
  const [pageIndex, setPageIndex] = useState(0);
  const navigate = useNavigate();
  const page = onboardingPages[pageIndex];
  if (page === undefined) throw new RangeError('Welcome page index is outside the onboarding flow.');
  const isFinalPage = pageIndex === onboardingPages.length - 1;

  function advance() {
    if (isFinalPage) {
      void navigate(routePaths.today);
      return;
    }
    setPageIndex((current) => Math.min(current + 1, onboardingPages.length - 1));
  }

  function goBack() {
    setPageIndex((current) => Math.max(current - 1, 0));
  }

  return (
    <section className="cc-welcome" aria-labelledby="cc-welcome-title">
      <WelcomeProgress pageIndex={pageIndex} />
      <div className="cc-welcome__body">
        <div className="cc-welcome__mark" aria-hidden="true">
          <KernelGlyph voice={page.voice} size={20} decorative />
        </div>
        <div className="cc-welcome__copy" aria-live="polite">
          <h1 id="cc-welcome-title">{page.title}</h1>
          <p>{page.copy}</p>
          <div className="cc-welcome__detail">
            <KernelGlyph voice={page.voice} size={18} decorative />
            <span>{page.detail}</span>
          </div>
        </div>
      </div>
      <div className="cc-welcome__actions">
        {pageIndex > 0 ? <button className="cc-button cc-welcome__back" type="button" onClick={goBack}>Back</button> : <span />}
        <button className="cc-button cc-button--primary" type="button" onClick={advance}>
          {isFinalPage ? 'Create my vault' : 'Continue'}
        </button>
      </div>
    </section>
  );
}

function TodayAction({ to, icon, label }: { to: string; icon: AppIconName; label: string }) {
  return (
    <Link className="cc-today-action" to={to}>
      <AppIcon name={icon} size={21} strokeWidth={2.2} />
      <span>{label}</span>
    </Link>
  );
}

function TodayLedger() {
  const { state } = useDemoState();
  const goal = state.goals.find((item) => item.cadence === 'today' && !item.completed) ?? state.goals[0];
  const talkingPoint = state.talkingPoints.find((item) => item.status === 'open') ?? state.talkingPoints[0];
  if (goal === undefined || talkingPoint === undefined) throw new Error('Seeded Today ledger requires a goal and talking point.');
  return (
    <div className="cc-today-ledger">
      <section aria-labelledby="cc-current-goal-heading">
        <div className="cc-section-heading">
          <h2 id="cc-current-goal-heading">Current goal</h2>
          <Link to={routePaths.goals}>See goals</Link>
        </div>
        <div className="cc-ledger-row">
          <div className="cc-ledger-row__title"><KernelGlyph voice={goal.provenance.voice} size={18} decorative /><Link to={routePaths.goals}>{goal.text}</Link></div>
          <ProvenanceLine provenance={goal.provenance} compact />
        </div>
      </section>
      <section aria-labelledby="cc-bring-up-heading">
        <div className="cc-section-heading">
          <h2 id="cc-bring-up-heading">Bring up next time</h2>
          <Link to={routePaths.bringUp}>Open inbox</Link>
        </div>
        <div className="cc-ledger-row">
          <div className="cc-ledger-row__title"><KernelGlyph voice={talkingPoint.provenance.voice} size={18} decorative /><Link to={routePaths.bringUp}>{talkingPoint.text}</Link></div>
          <ProvenanceLine provenance={talkingPoint.provenance} compact />
        </div>
      </section>
      <section aria-labelledby="cc-recent-memory-heading">
        <div className="cc-section-heading"><h2 id="cc-recent-memory-heading">Recent memory</h2></div>
        <div className="cc-ledger-row">
          <div className="cc-ledger-row__title"><KernelGlyph voice="user" size={18} decorative /><Link to={routePaths.journalDetail}>Football and feeling guilty</Link></div>
          <ProvenanceLine compact provenance={{ voice: 'user', label: 'You said this', detail: 'Journal, Sep 5 at 3:18 PM', sourcePath: routePaths.journalDetail }} />
        </div>
      </section>
    </div>
  );
}

export function TodayScreen() {
  const { state } = useDemoState();
  return (
    <div className="cc-screen cc-today">
      <div className="cc-today__context"><span>Saturday, Sep 5</span><strong>Jamie</strong></div>
      <h1>Today</h1>
      <section className="cc-today__mood" aria-labelledby="cc-today-mood-heading">
        <div className="cc-section-heading cc-section-heading--question"><h2 id="cc-today-mood-heading">How are you doing?</h2></div>
        {state.mood.mood === null && state.mood.anxiety === null && state.mood.energy === null ? <p className="cc-today__empty-mood">No check-in yet</p> : null}
        <Link className="cc-mood-link" to={routePaths.checkIn} aria-label="Open quick mood check-in"><MoodKernel value={state.mood} /></Link>
      </section>
      <nav className="cc-today-actions" aria-label="Capture something">
        <TodayAction to={routePaths.journalVoice} icon="microphone" label="Talk" />
        <TodayAction to={routePaths.journalWrite} icon="pencil" label="Write" />
        <TodayAction to={routePaths.recordAppointment} icon="calendar" label="Record appointment" />
      </nav>
      <section className="cc-next-appointment" aria-labelledby="cc-next-appointment-heading">
        <div className="cc-section-heading">
          <h2 id="cc-next-appointment-heading">Next appointment</h2>
          <span>Sep 9</span>
        </div>
        <Link className="cc-appointment-card" to={routePaths.appointments}>
          <strong>Therapy with Dr. Elena Park</strong>
          <span>Wednesday at 2:00 PM</span>
          <div><KernelGlyph voice="provider" size={16} decorative /><small>Provider appointment scheduled for Sep 9</small></div>
        </Link>
      </section>
      <TodayLedger />
    </div>
  );
}

export function CheckInScreen() {
  const { state, actions } = useDemoState();
  const navigate = useNavigate();
  const [draft, setDraft] = useState<MoodSnapshot>({ ...state.mood });
  const [saving, setSaving] = useState(false);
  const saveStarted = useRef(false);

  function updateMood(dimension: 'mood' | 'anxiety' | 'energy', value: number) {
    if (!Number.isSafeInteger(value) || value < 1 || value > 10) throw new RangeError('Mood values must be whole numbers from 1 through 10.');
    setDraft((current) => ({ ...current, [dimension]: value }));
  }

  function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saveStarted.current) return;
    saveStarted.current = true;
    setSaving(true);
    actions.saveMood({ ...draft, recordedAt: '2026-09-05T17:30:00-07:00' });
    void navigate(routePaths.today);
  }

  return (
    <ScreenLayout title="How are you doing?" subtitle="Tap each band to choose a value from 1 to 10." backTo={routePaths.today} backLabel="Cancel check-in" className="cc-check-in">
      <form onSubmit={save}>
        {draft.mood === null && draft.anxiety === null && draft.energy === null ? <p className="cc-check-in__empty">No check-in yet</p> : null}
        <MoodKernel value={draft} interactive onChange={updateMood} />
        <p className="cc-check-in__hint">Each tap moves the selected band up by one. After 10, it returns to 1.</p>
        <label className="cc-note-field">
          <span>Optional note</span>
          <textarea maxLength={180} rows={3} value={draft.note} onChange={(event) => setDraft((current) => ({ ...current, note: event.target.value }))} placeholder="What is shaping today?" />
        </label>
        <div className="cc-check-in__actions">
          <Link className="cc-button" to={routePaths.today}>Cancel</Link>
          <button className="cc-button cc-button--primary" type="submit" disabled={saving}>{saving ? 'Saving' : 'Save check-in'}</button>
        </div>
      </form>
    </ScreenLayout>
  );
}

export function CaptureScreen() {
  return (
    <ScreenLayout title="What feels easiest?" subtitle="Choose one way to get it out. You can organize it later." backTo={routePaths.today} className="cc-capture">
      <nav className="cc-capture-list" aria-label="Capture choices">
        {captureChoices.map((choice) => (
          <Link key={choice.title} className="cc-capture-choice" to={choice.to}>
            <span className="cc-capture-choice__icon"><AppIcon name={choice.icon} size={22} /></span>
            <span className="cc-capture-choice__copy"><strong>{choice.title}</strong><span>{choice.detail}</span></span>
            <AppIcon name="chevronRight" size={20} />
          </Link>
        ))}
      </nav>
      <div className="cc-capture__privacy"><KernelGlyph voice="user" size={18} decorative /><span>Nothing is recorded or photographed until you choose an action on the next screen.</span></div>
    </ScreenLayout>
  );
}

export const screens = defineScreens([
  { id: 'welcome', path: routePaths.welcome, title: 'Welcome', reviewLabel: 'Welcome and privacy', order: 1, primarySection: null, showBottomNav: false, component: WelcomeScreen },
  { id: 'today', path: routePaths.today, title: 'Today', reviewLabel: 'Today', order: 2, primarySection: 'today', showBottomNav: true, component: TodayScreen },
  { id: 'checkIn', path: routePaths.checkIn, title: 'Quick mood check-in', reviewLabel: 'Quick mood check-in', order: 3, primarySection: 'today', showBottomNav: false, component: CheckInScreen },
  { id: 'capture', path: routePaths.capture, title: 'Capture', reviewLabel: 'Capture choice', order: 4, primarySection: 'journal', showBottomNav: false, component: CaptureScreen },
]);
