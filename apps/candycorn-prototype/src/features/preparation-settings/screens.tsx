import { useState, type FormEvent, type ReactNode } from 'react';
import { Link, NavLink } from 'react-router-dom';
import {
  KernelGlyph,
  MoodKernel,
  ProvenanceLine,
  ScreenLayout,
  SelectableTabs,
  StatusNotice,
} from '@/components';
import { useDemoState } from '@/core/demo-state';
import { AppIcon } from '@/core/icons';
import { routePaths } from '@/core/routes';
import { defineScreens } from '@/core/screen-registry';
import type { AiMode, AiProvider, Provenance } from '@/core/types';
import './preparation-settings.css';

interface BriefDraft {
  whereLeftOff: string;
  pattern: string;
  pinnedQuestion: string;
  goals: string;
  opening: string;
}

type BriefKey = keyof BriefDraft;

interface BriefSection {
  key: BriefKey;
  heading: string;
  provenance: Provenance;
}

const initialBrief: BriefDraft = {
  whereLeftOff: 'Last time, you stopped the football story at the end of junior year. Dr. Park asked you to finish the senior-year timeline and notice guilt when moving forward feels possible.',
  pattern: 'You finished the senior-year narrative. Exercise helped for several hours, then guilt followed. Your notes do not show that exercise caused the change.',
  pinnedQuestion: 'Is needing proof that I could have played the part that keeps me stuck?',
  goals: 'Keep noticing moving-forward guilt, write down one example when it appears, and use exercise when thoughts feel stuck.',
  opening: 'Last time we stopped at junior year. I finished that part, and I realized I may need proof that I could have played more than I need to play again.',
};

const briefSections: readonly BriefSection[] = [
  {
    key: 'whereLeftOff',
    heading: 'Where you left off',
    provenance: {
      voice: 'provider',
      label: 'Therapist assigned this',
      detail: 'Therapy, Sep 2 at 42:18',
      occurredAt: '2026-09-02T14:42:18-07:00',
      sourcePath: routePaths.therapySession,
    },
  },
  {
    key: 'pattern',
    heading: 'What changed',
    provenance: {
      voice: 'user',
      label: 'You wrote this',
      detail: 'Journals, Sep 3 and Sep 5',
      occurredAt: '2026-09-05T15:20:00-07:00',
      sourcePath: routePaths.journalDetail,
    },
  },
  {
    key: 'pinnedQuestion',
    heading: 'A question you pinned',
    provenance: {
      voice: 'user',
      label: 'You pinned this',
      detail: 'Journal, Sep 5 at 3:18 PM',
      occurredAt: '2026-09-05T15:18:00-07:00',
      sourcePath: routePaths.bringUp,
    },
  },
  {
    key: 'goals',
    heading: 'What you are carrying forward',
    provenance: {
      voice: 'user',
      label: 'From your current goals',
      detail: 'Reviewed Sep 5',
      occurredAt: '2026-09-05T17:30:00-07:00',
      sourcePath: routePaths.goals,
    },
  },
  {
    key: 'opening',
    heading: 'A possible opening',
    provenance: {
      voice: 'candy-corn',
      label: 'Candy Corn suggested this wording',
      detail: 'Built from your saved brief, Sep 5',
      occurredAt: '2026-09-05T17:32:00-07:00',
    },
  },
];

const settingsLinks = [
  { to: routePaths.settingsPrivacy, label: 'Privacy' },
  { to: routePaths.settingsAi, label: 'AI' },
  { to: routePaths.settingsData, label: 'Data' },
] as const;

const aiModes: readonly { value: AiMode; label: string }[] = [
  { value: 'off', label: 'Off' },
  { value: 'organizer', label: 'Organizer' },
  { value: 'reflection', label: 'Reflection' },
];

function highlightedCopy(value: string): ReactNode {
  const phrase = 'proof that I could have played';
  const start = value.toLowerCase().indexOf(phrase);
  if (start < 0) return value;
  const end = start + phrase.length;
  return <>{value.slice(0, start)}<mark>{value.slice(start, end)}</mark>{value.slice(end)}</>;
}

function BriefReading({ brief }: { brief: BriefDraft }) {
  return (
    <div className="cc-prepare-brief">
      {briefSections.map((section) => (
        <section className="cc-brief-line" key={section.key}>
          <h2>{section.heading}</h2>
          <p>{section.key === 'opening' ? <>“{highlightedCopy(brief[section.key])}”</> : highlightedCopy(brief[section.key])}</p>
          <ProvenanceLine provenance={section.provenance} />
        </section>
      ))}
    </div>
  );
}

function BriefEditor({ draft, error, onChange, onSave, onCancel }: {
  draft: BriefDraft;
  error: string;
  onChange(key: BriefKey, value: string): void;
  onSave(event: FormEvent<HTMLFormElement>): void;
  onCancel(): void;
}) {
  return (
    <form className="cc-brief-editor" onSubmit={onSave} noValidate>
      {briefSections.map((section) => (
        <label key={section.key} htmlFor={`brief-${section.key}`}>
          <span>{section.heading}</span>
          <textarea
            id={`brief-${section.key}`}
            rows={section.key === 'pinnedQuestion' ? 3 : 5}
            maxLength={700}
            value={draft[section.key]}
            onChange={(event) => onChange(section.key, event.target.value)}
          />
        </label>
      ))}
      {error ? <p className="cc-prep-field-error" role="alert">{error}</p> : null}
      <div className="cc-prepare-actions cc-prepare-actions--editing">
        <button className="cc-button" type="button" onClick={onCancel}>Cancel</button>
        <button className="cc-button cc-button--primary" type="submit">Save brief</button>
      </div>
    </form>
  );
}

export function PrepareTherapyScreen() {
  const [savedBrief, setSavedBrief] = useState<BriefDraft>(initialBrief);
  const [draft, setDraft] = useState<BriefDraft>(initialBrief);
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState('');

  function beginEditing() {
    setDraft(savedBrief);
    setError('');
    setEditing(true);
  }

  function cancelEditing() {
    setDraft(savedBrief);
    setError('');
    setEditing(false);
  }

  function saveBrief(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const hasBlankSection = briefSections.some((section) => draft[section.key].trim().length === 0);
    if (hasBlankSection) {
      setError('Keep a short note in every section or cancel your edits.');
      return;
    }
    const nextBrief = { ...draft };
    setSavedBrief(nextBrief);
    setDraft(nextBrief);
    setError('');
    setEditing(false);
  }

  function updateDraft(key: BriefKey, value: string) {
    setDraft((current) => ({ ...current, [key]: value }));
    setError('');
  }

  return (
    <ScreenLayout
      title={editing ? 'Edit your therapy brief' : 'Walk in knowing what matters'}
      subtitle={editing ? 'Change the wording without changing your original journals or session.' : 'A brief for Jamie Rivera to read before therapy with Dr. Elena Park on Sep 9.'}
      backTo={routePaths.today}
      className="cc-prepare cc-prepare--therapy"
    >
      {editing ? (
        <BriefEditor draft={draft} error={error} onChange={updateDraft} onSave={saveBrief} onCancel={cancelEditing} />
      ) : (
        <>
          <BriefReading brief={savedBrief} />
          <div className="cc-prepare-actions">
            <button className="cc-button cc-button--primary" type="button" onClick={beginEditing}>
              <AppIcon name="pencil" size={19} />
              Edit brief
            </button>
          </div>
        </>
      )}
    </ScreenLayout>
  );
}

function TmsBriefLine({ heading, children, provenance }: {
  heading: string;
  children: ReactNode;
  provenance: Provenance;
}) {
  return (
    <section className="cc-brief-line">
      <h2>{heading}</h2>
      <div className="cc-tms-line-copy">{children}</div>
      <ProvenanceLine provenance={provenance} />
    </section>
  );
}

export function PrepareTmsScreen() {
  const { state } = useDemoState();
  const moodLabel = state.mood.mood === null ? 'not logged' : `${state.mood.mood} of 10`;
  const anxietyLabel = state.mood.anxiety === null ? 'not logged' : `${state.mood.anxiety} of 10`;
  return (
    <ScreenLayout title="Prepare for TMS" subtitle="Saved observations for the next Riverbend TMS visit." backTo={routePaths.today} className="cc-prepare cc-prepare--tms">
      <section className="cc-tms-mood" aria-labelledby="cc-tms-current-heading">
        <h2 id="cc-tms-current-heading">How you are doing now</h2>
        <MoodKernel value={state.mood} compact />
        <p>Mood {moodLabel}. Anxiety {anxietyLabel}. Distress was not recorded.</p>
      </section>
      <div className="cc-prepare-brief">
        <TmsBriefLine heading="Before and after notes" provenance={{ voice: 'user', label: 'You recorded these observations', detail: 'TMS, Sep 5 before and after the visit', sourcePath: routePaths.tmsPost }}>
          <p>Before the visit, you noted low energy and worry about the day. Afterward, you noted a quieter morning and a mild headache. These observations do not show that TMS caused a mood change.</p>
        </TmsBriefLine>
        <TmsBriefLine heading="A question for the team" provenance={{ voice: 'user', label: 'You saved this question', detail: 'TMS pre-session, Sep 5 at 9:18 AM', sourcePath: routePaths.tmsPre }}>
          <p>Should I keep tracking the headache if it is still mild later today?</p>
        </TmsBriefLine>
        <TmsBriefLine heading="Provider-approved focus" provenance={{ voice: 'provider', label: 'Dr. Elena Park asked you to notice this', detail: 'Therapy, Sep 2 at 38:44', sourcePath: routePaths.therapySession }}>
          <p>Notice when moving-forward guilt appears. Do not change your treatment plan based on this app.</p>
        </TmsBriefLine>
      </div>
      <StatusNotice title="Your treatment stays with your care team">
        <p>Candy Corn organizes saved items. It does not create treatment provocations or tell you how to change treatment.</p>
      </StatusNotice>
      <nav className="cc-tms-capture-links" aria-label="TMS capture links">
        <Link className="cc-button" to={routePaths.tmsPre}>Open pre-session capture</Link>
        <Link className="cc-button" to={routePaths.tmsPost}>Open post-session capture</Link>
      </nav>
    </ScreenLayout>
  );
}

function SettingsNav() {
  return (
    <nav className="cc-settings-nav" aria-label="Settings sections">
      {settingsLinks.map((item) => (
        <NavLink key={item.to} to={item.to} className={({ isActive }) => isActive ? 'cc-settings-nav__link cc-settings-nav__link--active' : 'cc-settings-nav__link'}>
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}

function StatusRow({ status, detail, voice = 'candy-corn' }: {
  status: string;
  detail: string;
  voice?: Provenance['voice'];
}) {
  return (
    <li className="cc-settings-status-row">
      <ProvenanceLine provenance={{ voice, label: status, detail }} />
    </li>
  );
}

export function SettingsPrivacyScreen() {
  return (
    <ScreenLayout title="Privacy" subtitle="Your private record should stay understandable and under your control." className="cc-settings-screen">
      <SettingsNav />
      <section className="cc-settings-section" aria-labelledby="cc-privacy-status-heading">
        <h2 id="cc-privacy-status-heading">Privacy status</h2>
        <ul className="cc-settings-status-ledger">
          <StatusRow status="Stored on this device" detail="The intended app keeps your originals in a private local vault. This prototype keeps only in-memory demo changes." voice="user" />
          <StatusRow status="Cloud upload: only when AI is on" detail="You see what is selected before processing." />
          <StatusRow status="Raw audio retention: you decide" detail="Choose a retention rule in Data and export." voice="user" />
          <StatusRow status="No accounts or analytics" detail="This prototype has no sign-in, advertising, or tracking." />
        </ul>
      </section>
      <StatusNotice title="Static prototype limits">
        <p>Reloading restores fictional seeded data. Encrypted storage, device permissions, cloud routing, and export are not active in Phase 0.</p>
      </StatusNotice>
      <section className="cc-settings-about" aria-labelledby="cc-about-heading">
        <KernelGlyph voice="provider" size={18} decorative />
        <div>
          <h2 id="cc-about-heading">About and limitations</h2>
          <p>Candy Corn helps you organize your own care record. It is not a therapist, medical advice, or a crisis service. Contact local emergency or crisis support when you need immediate help.</p>
        </div>
      </section>
      <Link className="cc-settings-next" to={routePaths.settingsAi}>Review AI and processing<AppIcon name="chevronRight" size={18} /></Link>
    </ScreenLayout>
  );
}

function processingStatus(mode: AiMode, provider: AiProvider): { journal: string; voice: string } {
  if (mode === 'off' || provider === 'off') return { journal: 'Journal intelligence: Off', voice: 'Voice transcription: Off' };
  if (provider === 'router') return { journal: 'Journal intelligence: Cloud (router)', voice: 'Voice transcription: Cloud (router)' };
  return { journal: 'Journal intelligence: Waiting for on-device availability', voice: 'Voice transcription: Waiting for on-device availability' };
}

function leavesDeviceCopy(mode: AiMode, provider: AiProvider): string {
  if (mode === 'off' || provider === 'off') return 'Nothing is sent for AI processing.';
  if (provider === 'on-device-when-available') return 'Nothing is sent until a supported on-device provider is available and selected in the native app.';
  if (mode === 'organizer') return 'Selected journal text and selected audio for transcription may be sent through the cloud router.';
  return 'Selected journal text, transcript excerpts, and selected audio for transcription may be sent through the cloud router.';
}

interface AiSettingsPanelProps { routerAvailableOverride?: boolean }

export function AiSettingsPanel({ routerAvailableOverride }: AiSettingsPanelProps) {
  const { state, actions } = useDemoState();
  const routerAvailable = routerAvailableOverride ?? state.ai.routerAvailable;
  const status = processingStatus(state.ai.mode, state.ai.provider);

  function changeProvider(provider: AiProvider) {
    if (provider === 'on-device-when-available') return;
    if (provider === 'router' && !routerAvailable) return;
    actions.setAiProvider(provider);
  }

  return (
    <>
      <section className="cc-settings-section" aria-labelledby="cc-processing-heading">
        <h2 id="cc-processing-heading">Processing status</h2>
        <ul className="cc-settings-status-ledger">
          <StatusRow status={status.journal} detail={state.ai.mode === 'off' ? 'Your original journal stays readable.' : 'First-version language tasks use the hosted router.'} />
          <StatusRow status={status.voice} detail={state.ai.mode === 'off' ? 'Saved originals remain available.' : 'Only audio you select for transcription is included.'} />
        </ul>
      </section>
      {!routerAvailable ? (
        <StatusNotice title="Cloud router unavailable" action={<button className="cc-inline-action" type="button" onClick={() => actions.setAiMode('off')}>Turn AI off</button>}>
          <p>Organization is unavailable right now. Your original journals, transcripts, and audio remain available.</p>
        </StatusNotice>
      ) : null}
      <section className="cc-settings-section cc-ai-choice-section" aria-labelledby="cc-ai-mode-heading">
        <h2 id="cc-ai-mode-heading">AI mode</h2>
        <p>Choose how much help you want. Suggestions never change your originals.</p>
        <SelectableTabs<AiMode> items={aiModes} value={state.ai.mode} onChange={actions.setAiMode} ariaLabel="AI mode" />
        <div className="cc-ai-mode-description" aria-live="polite">
          {state.ai.mode === 'off' ? 'No organizing or reflection.' : null}
          {state.ai.mode === 'organizer' ? 'Cleans up wording, summarizes, and finds candidate items.' : null}
          {state.ai.mode === 'reflection' ? 'Adds optional connections across saved entries. Every connection stays a suggestion.' : null}
        </div>
      </section>
      <fieldset className="cc-settings-choice-fieldset">
        <legend>Processing provider</legend>
        <label className="cc-setting-choice cc-setting-choice--disabled">
          <input type="radio" name="ai-provider" value="on-device-when-available" checked={state.ai.provider === 'on-device-when-available'} disabled onChange={() => changeProvider('on-device-when-available')} />
          <span><strong>On-device when available</strong><small>Future native option. Not active in this prototype.</small></span>
        </label>
        <label className="cc-setting-choice">
          <input type="radio" name="ai-provider" value="router" checked={state.ai.provider === 'router'} disabled={state.ai.mode === 'off' || !routerAvailable} onChange={() => changeProvider('router')} />
          <span><strong>Router</strong><small>{routerAvailable ? 'First-version cloud processing.' : 'Unavailable right now. Originals are unaffected.'}</small></span>
        </label>
        <label className="cc-setting-choice">
          <input type="radio" name="ai-provider" value="off" checked={state.ai.provider === 'off'} onChange={() => changeProvider('off')} />
          <span><strong>Off</strong><small>No AI processing leaves this device.</small></span>
        </label>
      </fieldset>
      <StatusNotice title="What leaves this device" voice={state.ai.mode === 'off' || state.ai.provider === 'off' ? 'user' : 'candy-corn'}>
        <p>{leavesDeviceCopy(state.ai.mode, state.ai.provider)}</p>
      </StatusNotice>
    </>
  );
}

export function SettingsAiScreen() {
  return (
    <ScreenLayout title="AI and processing" subtitle="The first version uses a cloud router when AI is on." className="cc-settings-screen">
      <SettingsNav />
      <AiSettingsPanel />
    </ScreenLayout>
  );
}

type RetentionChoice = 'keep' | 'delete-after-verification' | 'ask';

const retentionChoices: readonly { value: RetentionChoice; title: string; detail: string }[] = [
  { value: 'keep', title: 'Keep raw recording', detail: 'Keep the original beside its transcript.' },
  { value: 'delete-after-verification', title: 'Delete after transcript verification', detail: 'Intended native behavior after you confirm the transcript.' },
  { value: 'ask', title: 'Ask every time', detail: 'Decide separately after each recording.' },
];

export function SettingsDataScreen() {
  const { actions } = useDemoState();
  const [retention, setRetention] = useState<RetentionChoice>('ask');
  const [showExport, setShowExport] = useState(false);
  const [confirmReset, setConfirmReset] = useState(false);
  const [resetComplete, setResetComplete] = useState(false);

  function resetDemo() {
    actions.resetDemo();
    setRetention('ask');
    setShowExport(false);
    setConfirmReset(false);
    setResetComplete(true);
  }

  return (
    <ScreenLayout title="Data and export" subtitle="Choose what the future native vault keeps. Phase 0 changes stay in memory only." className="cc-settings-screen">
      <SettingsNav />
      <fieldset className="cc-settings-choice-fieldset">
        <legend>Raw audio retention</legend>
        {retentionChoices.map((choice) => (
          <label className="cc-setting-choice" key={choice.value}>
            <input type="radio" name="audio-retention" value={choice.value} checked={retention === choice.value} onChange={() => { setRetention(choice.value); setResetComplete(false); }} />
            <span><strong>{choice.title}</strong><small>{choice.detail}</small></span>
          </label>
        ))}
      </fieldset>
      <section className="cc-data-action" aria-labelledby="cc-export-heading">
        <KernelGlyph voice="user" size={18} decorative />
        <div>
          <h2 id="cc-export-heading">Export preview</h2>
          <p>Export is not active in this prototype. No file will be created or downloaded.</p>
          <button className="cc-button" type="button" aria-expanded={showExport} aria-controls="cc-export-preview" onClick={() => setShowExport((current) => !current)}>
            <AppIcon name="download" size={18} />
            {showExport ? 'Hide archive preview' : 'Preview archive contents'}
          </button>
          {showExport ? (
            <ul id="cc-export-preview" className="cc-export-preview">
              <li>Original journals and organized copies</li>
              <li>Session audio, transcripts, and summaries you retained</li>
              <li>Goals, mood check-ins, and appointment briefs</li>
              <li>A plain provenance record for generated items</li>
            </ul>
          ) : null}
        </div>
      </section>
      <section className="cc-data-action cc-data-action--reset" aria-labelledby="cc-reset-heading">
        <KernelGlyph voice="provider" size={18} decorative />
        <div>
          <h2 id="cc-reset-heading">Reset demo</h2>
          <p>Restore the fictional Jamie Rivera thread and clear changes made during this visit.</p>
          {!confirmReset ? <button className="cc-button" type="button" onClick={() => { setConfirmReset(true); setResetComplete(false); }}><AppIcon name="trash" size={18} />Reset demo</button> : (
            <div className="cc-reset-confirm" role="group" aria-label="Confirm reset demo">
              <p>This clears only temporary prototype changes. Reset now?</p>
              <button className="cc-button" type="button" onClick={() => setConfirmReset(false)}>Cancel</button>
              <button className="cc-button cc-button--danger" type="button" onClick={resetDemo}>Reset now</button>
            </div>
          )}
          {resetComplete ? <p className="cc-reset-complete" role="status">Seeded demo restored.</p> : null}
        </div>
      </section>
    </ScreenLayout>
  );
}

export const screens = defineScreens([
  { id: 'prepareTherapy', path: routePaths.prepareTherapy, title: 'Prepare for therapy', reviewLabel: 'Prepare for therapy', order: 18, primarySection: 'prepare', showBottomNav: true, component: PrepareTherapyScreen },
  { id: 'prepareTms', path: routePaths.prepareTms, title: 'Prepare for TMS', reviewLabel: 'Prepare for TMS', order: 19, primarySection: 'prepare', showBottomNav: true, component: PrepareTmsScreen },
  { id: 'settingsPrivacy', path: routePaths.settingsPrivacy, title: 'Privacy', reviewLabel: 'Settings privacy', order: 22, primarySection: 'settings', showBottomNav: true, component: SettingsPrivacyScreen },
  { id: 'settingsAi', path: routePaths.settingsAi, title: 'AI and processing', reviewLabel: 'Settings AI and processing', order: 23, primarySection: 'settings', showBottomNav: true, component: SettingsAiScreen },
  { id: 'settingsData', path: routePaths.settingsData, title: 'Data and export', reviewLabel: 'Settings data and export', order: 24, primarySection: 'settings', showBottomNav: true, component: SettingsDataScreen },
]);
