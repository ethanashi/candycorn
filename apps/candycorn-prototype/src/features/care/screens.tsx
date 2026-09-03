import { useEffect, useRef, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
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
import { seededAppointments, seededTranscript } from '@/core/seeded-data';
import type {
  Appointment,
  AppointmentType,
  MoodSnapshot,
  ProvenanceVoice,
  TranscriptSegment,
  TranscriptSpeaker,
} from '@/core/types';
import './care.css';

const appointmentLabels: Readonly<Record<AppointmentType, string>> = {
  therapy: 'Therapy',
  tms: 'TMS',
  psychiatry: 'Psychiatry',
  other: 'Other',
};

const appointmentTypeItems = [
  { value: 'therapy', label: 'Therapy' },
  { value: 'tms', label: 'TMS' },
  { value: 'psychiatry', label: 'Psychiatry' },
  { value: 'other', label: 'Other' },
] as const;

const sessionTabs = [
  { value: 'summary', label: 'Summary' },
  { value: 'transcript', label: 'Transcript' },
  { value: 'homework', label: 'Homework' },
  { value: 'talking-points', label: 'Talking points' },
] as const;

const appointmentRecordingStartSeconds = 18 * 60 + 24;
const waveformBars = [36, 62, 45, 78, 52, 30, 68, 84, 41, 57, 72, 35, 64, 48, 80, 39, 59, 74, 43, 67, 32, 76, 51, 88, 46, 63, 38, 70, 54, 82, 42, 61];

type SessionTab = (typeof sessionTabs)[number]['value'];
type RecordingStatus = 'recording' | 'saved';

interface RecordingRouteState {
  appointmentType: AppointmentType;
  consented: true;
}

interface TmsSnapshot {
  mood: number;
  anxiety: number;
  energy: number;
  distress: number;
}

function isAppointmentType(value: unknown): value is AppointmentType {
  return value === 'therapy' || value === 'tms' || value === 'psychiatry' || value === 'other';
}

function readRecordingState(value: unknown): RecordingRouteState | null {
  if (typeof value !== 'object' || value === null) return null;
  const candidate = value as Partial<RecordingRouteState>;
  if (!isAppointmentType(candidate.appointmentType) || candidate.consented !== true) return null;
  return { appointmentType: candidate.appointmentType, consented: true };
}

function formatTimer(totalSeconds: number): string {
  if (!Number.isSafeInteger(totalSeconds) || totalSeconds < 0) {
    throw new RangeError('Recording time must be a non-negative whole number.');
  }
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function formatTimestamp(milliseconds: number): string {
  if (!Number.isSafeInteger(milliseconds) || milliseconds < 0) {
    throw new RangeError('Transcript timestamps must be non-negative whole milliseconds.');
  }
  const totalSeconds = Math.floor(milliseconds / 1_000);
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, '0')}`;
}

function AppointmentRow({ appointment }: { appointment: Appointment }) {
  const isTherapyUpcoming = appointment.id === 'therapy-sep-9';
  const isCompletedTherapy = appointment.id === 'therapy-sep-2';
  const isTms = appointment.type === 'tms';
  return (
    <article className="cc-care-appointment-row">
      <div className="cc-care-appointment-date">
        <span>{appointment.startsAt.slice(5, 7) === '09' ? 'Sep' : 'Visit'}</span>
        <strong>{Number(appointment.startsAt.slice(8, 10))}</strong>
      </div>
      <div className="cc-care-appointment-copy">
        <div><strong>{appointmentLabels[appointment.type]}</strong><span>{appointment.providerName}</span></div>
        <p>{appointment.status === 'upcoming' ? '2:00 PM · Upcoming' : `${appointment.durationMinutes ?? 0} min · Completed`}</p>
        <div className="cc-care-row-actions">
          {isTherapyUpcoming ? <Link to={routePaths.prepareTherapy}>Prepare</Link> : null}
          {isTherapyUpcoming ? <Link to={routePaths.recordAppointment}>Record appointment</Link> : null}
          {isCompletedTherapy ? <Link to={routePaths.therapySession}>Open session</Link> : null}
          {isTms ? <Link to={routePaths.tmsPost}>Review check-in</Link> : null}
        </div>
      </div>
    </article>
  );
}

export function AppointmentsScreen() {
  if (seededAppointments.length !== 3) {
    throw new Error('The care list requires exactly three fictional appointments.');
  }
  return (
    <ScreenLayout title="Appointments" subtitle="Upcoming care and the source record from completed visits." backTo={routePaths.today}>
      <Link className="cc-button cc-button--primary cc-care-full-button" to={routePaths.recordAppointment}>
        <AppIcon name="microphone" size={20} />Record an appointment
      </Link>
      <section className="cc-care-appointment-list" aria-label="Fictional appointments">
        {seededAppointments.map((appointment) => <AppointmentRow key={appointment.id} appointment={appointment} />)}
      </section>
    </ScreenLayout>
  );
}

export function RecordAppointmentScreen() {
  const navigate = useNavigate();
  const { state, actions } = useDemoState();
  const [appointmentType, setAppointmentType] = useState<AppointmentType>('therapy');
  const startedRef = useRef(false);
  const reasonId = 'recording-consent-reason';

  function changeAppointmentType(nextType: AppointmentType) {
    if (!isAppointmentType(nextType)) throw new TypeError('A known appointment type is required.');
    startedRef.current = false;
    setAppointmentType(nextType);
    actions.setConsentAcknowledged(false);
  }

  function startRecording() {
    if (!state.consentAcknowledged || startedRef.current) return;
    startedRef.current = true;
    actions.setConsentAcknowledged(true);
    navigate(routePaths.activeAppointment, { state: { appointmentType, consented: true } satisfies RecordingRouteState });
  }

  return (
    <ScreenLayout title="Record an appointment" subtitle="Choose the visit type before confirming permission." backTo={routePaths.appointments} className="cc-care-consent-screen">
      <SelectableTabs items={appointmentTypeItems} value={appointmentType} onChange={changeAppointmentType} ariaLabel="Appointment type" />
      <section className="cc-care-consent" aria-labelledby="recording-permission-title">
        <KernelGlyph voice="user" size={20} decorative />
        <div>
          <h2 id="recording-permission-title">Recording requires permission</h2>
          <p id={reasonId}>Ask everyone in the room before recording. Start stays unavailable until you confirm.</p>
        </div>
        <label className="cc-care-consent-check">
          <input
            type="checkbox"
            checked={state.consentAcknowledged}
            onChange={(event) => actions.setConsentAcknowledged(event.target.checked)}
            aria-describedby={reasonId}
          />
          <span>I have permission to record this appointment</span>
        </label>
        <button
          type="button"
          className="cc-button cc-button--primary"
          disabled={!state.consentAcknowledged}
          aria-describedby={reasonId}
          onClick={startRecording}
        >
          Start recording
        </button>
      </section>
      <p className="cc-care-local-note">The original audio is saved on this device before any processing.</p>
    </ScreenLayout>
  );
}

function AppointmentWaveform() {
  if (waveformBars.length < 16 || waveformBars.length > 64) {
    throw new RangeError('The appointment waveform must remain a bounded visual fixture.');
  }
  return (
    <div className="cc-care-waveform" aria-label="Simulated appointment waveform">
      {waveformBars.map((height, index) => (
        <span key={`${height}-${index}`} style={{ height: `${height}%`, animationDelay: `${index * -21}ms` }} />
      ))}
    </div>
  );
}

function SavedAppointment({ appointmentType }: { appointmentType: AppointmentType }) {
  const destination = appointmentType === 'tms'
    ? routePaths.tmsPost
    : appointmentType === 'therapy'
      ? routePaths.therapySession
      : routePaths.appointments;
  const actionLabel = appointmentType === 'tms' ? 'Complete post-session check-in' : appointmentType === 'therapy' ? 'Open session detail' : 'Back to appointments';
  return (
    <div className="cc-care-saved-recording">
      <StatusNotice title="Saved on this device" voice="user">
        <p>The original recording is preserved. Nothing was sent anywhere.</p>
      </StatusNotice>
      <Link className="cc-button cc-button--primary" to={destination}>{actionLabel}</Link>
    </div>
  );
}

export function ActiveAppointmentScreen() {
  const location = useLocation();
  const routeState = readRecordingState(location.state);
  const { state } = useDemoState();
  const [status, setStatus] = useState<RecordingStatus>('recording');
  const [seconds, setSeconds] = useState(appointmentRecordingStartSeconds);
  const finishedRef = useRef(false);

  useEffect(() => {
    if (routeState === null || !state.consentAcknowledged || status !== 'recording') return undefined;
    const intervalId = window.setInterval(() => setSeconds((value) => value + 1), 1_000);
    return () => window.clearInterval(intervalId);
  }, [routeState, state.consentAcknowledged, status]);

  function finishRecording() {
    if (finishedRef.current || routeState === null || !state.consentAcknowledged) return;
    finishedRef.current = true;
    setStatus('saved');
  }

  if (routeState === null || !state.consentAcknowledged) {
    return (
      <ScreenLayout title="Recording is not active" subtitle="Confirm permission before a recording can start." backTo={routePaths.appointments}>
        <StatusNotice
          title="Permission has not been confirmed"
          action={<Link className="cc-button" to={routePaths.recordAppointment}>Review recording permission</Link>}
        >
          <p>No microphone request was made and no recording started.</p>
        </StatusNotice>
      </ScreenLayout>
    );
  }

  if (status === 'saved') return <SavedAppointment appointmentType={routeState.appointmentType} />;

  return (
    <div className="cc-care-active" aria-label="Active appointment recording">
      <header>
        <Link to={routePaths.appointments} aria-label="Back to appointments"><AppIcon name="back" size={22} /></Link>
        <span>{appointmentLabels[routeState.appointmentType]}</span>
      </header>
      <div className="cc-care-recording-stage">
        <p>Recording</p>
        <output aria-label="Appointment recording duration">{formatTimer(seconds)}</output>
        <AppointmentWaveform />
        <button type="button" className="cc-care-finish" onClick={finishRecording}>
          <AppIcon name="stop" size={19} />Finish
        </button>
      </div>
      <p className="cc-care-local-note">Recording continues while your phone is locked.</p>
    </div>
  );
}

const summaryItems: readonly { text: string; segmentId: string; voice: ProvenanceVoice; source: string }[] = [
  {
    text: 'The missed chance to prove you could have played still feels more important than playing again.',
    segmentId: 'therapy-sep-2-1',
    voice: 'user',
    source: 'You said this at 12:24',
  },
  {
    text: 'Dr. Park reflected that the grief may be about never getting to test what you believed about yourself.',
    segmentId: 'therapy-sep-2-2',
    voice: 'provider',
    source: 'Therapist said this on Sep 2 at 12:48',
  },
];

function TranscriptRow({ segment, speaker, onCorrect }: { segment: TranscriptSegment; speaker: TranscriptSpeaker; onCorrect: (speaker: TranscriptSpeaker) => void }) {
  const speakerLabel = speaker === 'patient' ? 'Jamie' : speaker === 'provider' ? 'Dr. Elena Park' : 'Unknown speaker';
  return (
    <article id={segment.id} className={`cc-care-transcript-row cc-care-transcript-row--${speaker}`} tabIndex={-1}>
      <header>
        {speaker === 'unknown' ? <span className="cc-care-unknown-glyph" aria-hidden="true">?</span> : <KernelGlyph voice={speaker === 'provider' ? 'provider' : 'user'} size={18} decorative />}
        <strong>{speakerLabel}</strong>
        <time>{formatTimestamp(segment.startMilliseconds)}</time>
      </header>
      <p>{segment.text}</p>
      {speaker === 'unknown' ? (
        <div className="cc-care-speaker-actions" aria-label="Correct unknown speaker">
          <button type="button" onClick={() => onCorrect('patient')}>Mark as me</button>
          <button type="button" onClick={() => onCorrect('provider')}>Mark as provider</button>
        </div>
      ) : null}
    </article>
  );
}

function SummaryPanel({ onTimestamp }: { onTimestamp: (segmentId: string) => void }) {
  return (
    <section className="cc-care-summary" aria-label="Session summary">
      {summaryItems.map((item) => (
        <article key={item.segmentId}>
          <KernelGlyph voice={item.voice} size={18} decorative />
          <div>
            <p>{item.text}</p>
            <button type="button" onClick={() => onTimestamp(item.segmentId)}>{item.source}</button>
          </div>
        </article>
      ))}
    </section>
  );
}

function HomeworkPanel() {
  return (
    <section className="cc-care-detail-ledger" aria-label="Session homework">
      <article>
        <p>Finish the senior-year football timeline.</p>
        <ProvenanceLine provenance={{ voice: 'provider', label: 'Therapist assigned this', detail: 'Therapy, Sep 2 at 42:18', occurredAt: '2026-09-02T14:42:18-07:00' }} />
      </article>
      <article>
        <p>Notice when feeling better is followed by guilt about moving forward.</p>
        <ProvenanceLine provenance={{ voice: 'provider', label: 'Therapist assigned this', detail: 'Therapy, Sep 2 at 42:18', occurredAt: '2026-09-02T14:42:18-07:00' }} />
      </article>
    </section>
  );
}

function TalkingPointsPanel() {
  return (
    <section className="cc-care-detail-ledger" aria-label="Session talking points">
      <article>
        <p>The senior-year meeting with the coaches.</p>
        <ProvenanceLine provenance={{ voice: 'user', label: 'You brought this up', detail: 'Therapy, Sep 2 at 38:44' }} />
      </article>
      <article>
        <p>Ask whether needing proof is the part that keeps the memory stuck.</p>
        <ProvenanceLine provenance={{ voice: 'candy-corn', label: 'Candy Corn suggested this', detail: 'Based on the saved transcript. You chose to keep it.' }} />
      </article>
    </section>
  );
}

export function TherapySessionScreen() {
  const [tab, setTab] = useState<SessionTab>('transcript');
  const [speakerCorrections, setSpeakerCorrections] = useState<Readonly<Record<string, TranscriptSpeaker>>>({});
  const pendingFocusRef = useRef<string | null>(null);

  useEffect(() => {
    if (tab !== 'transcript' || pendingFocusRef.current === null) return;
    const segment = document.getElementById(pendingFocusRef.current);
    pendingFocusRef.current = null;
    segment?.focus();
  }, [tab]);

  function openTranscriptAt(segmentId: string) {
    if (!seededTranscript.some((segment) => segment.id === segmentId)) {
      throw new Error('A summary timestamp must reference a seeded transcript segment.');
    }
    pendingFocusRef.current = segmentId;
    setTab('transcript');
  }

  function correctSpeaker(segment: TranscriptSegment, speaker: TranscriptSpeaker) {
    if (segment.speaker !== 'unknown' || speaker === 'unknown') return;
    setSpeakerCorrections((current) => ({ ...current, [segment.id]: speaker }));
  }

  return (
    <ScreenLayout title="Therapy with Dr. Elena Park" subtitle="Sep 2 · 52 min · Saved on this device" backTo={routePaths.appointments} className="cc-care-session">
      <SelectableTabs<SessionTab> items={sessionTabs} value={tab} onChange={setTab} ariaLabel="Session detail" />
      <div className="cc-care-session-panel" role="tabpanel">
        {tab === 'summary' ? <SummaryPanel onTimestamp={openTranscriptAt} /> : null}
        {tab === 'transcript' ? (
          <section className="cc-care-transcript" aria-label="Source-preserving transcript">
            {seededTranscript.map((segment) => (
              <TranscriptRow key={segment.id} segment={segment} speaker={speakerCorrections[segment.id] ?? segment.speaker} onCorrect={(speaker) => correctSpeaker(segment, speaker)} />
            ))}
          </section>
        ) : null}
        {tab === 'homework' ? <HomeworkPanel /> : null}
        {tab === 'talking-points' ? <TalkingPointsPanel /> : null}
      </div>
      <section className="cc-care-scrubber" aria-label="Simulated transcript playback">
        <div><time>12:48</time><time>52:06</time></div>
        <input type="range" min="0" max="3126" defaultValue="768" aria-label="Simulated playback position" />
        <strong>Playing from the saved transcript</strong>
      </section>
    </ScreenLayout>
  );
}

function updateSnapshot(snapshot: TmsSnapshot, dimension: 'mood' | 'anxiety' | 'energy', value: number): TmsSnapshot {
  if (!Number.isInteger(value) || value < 1 || value > 10) throw new RangeError('TMS check-in values must be from 1 to 10.');
  return { ...snapshot, [dimension]: value };
}

function DistressControl({ value, onChange }: { value: number; onChange: (value: number) => void }) {
  if (!Number.isInteger(value) || value < 1 || value > 10) throw new RangeError('Distress must be from 1 to 10.');
  return (
    <label className="cc-care-distress">
      <span>Distress <strong>{value}/10</strong></span>
      <input type="range" min="1" max="10" value={value} onChange={(event) => onChange(Number(event.target.value))} />
    </label>
  );
}

function TmsMeasures({ snapshot, onChange }: { snapshot: TmsSnapshot; onChange: (value: TmsSnapshot) => void }) {
  const moodValue: Pick<MoodSnapshot, 'mood' | 'anxiety' | 'energy'> = snapshot;
  return (
    <section className="cc-care-tms-measures" aria-labelledby="tms-measures-title">
      <h2 id="tms-measures-title">Mood, anxiety, and distress</h2>
      <MoodKernel value={moodValue} interactive onChange={(dimension, value) => onChange(updateSnapshot(snapshot, dimension, value))} />
      <DistressControl value={snapshot.distress} onChange={(distress) => onChange({ ...snapshot, distress })} />
    </section>
  );
}

export function TmsPreSessionScreen() {
  const navigate = useNavigate();
  const { actions } = useDemoState();
  const [snapshot, setSnapshot] = useState<TmsSnapshot>({ mood: 6, anxiety: 7, energy: 4, distress: 6 });
  const [bothering, setBothering] = useState('The guilt that shows up after I start feeling better.');
  const [providerNote, setProviderNote] = useState('Mention any sleep changes before today’s session.');
  const [added, setAdded] = useState(false);

  function addForProvider() {
    if (added || !bothering.trim()) return;
    actions.addTalkingPoint({
      id: 'tms-pre-bothering-today',
      text: bothering.trim(),
      target: 'tms',
      priority: 'normal',
      status: 'open',
      provenance: { voice: 'user', label: 'You chose to tell the provider', detail: 'TMS pre-session check-in' },
    });
    setAdded(true);
  }

  return (
    <ScreenLayout title="Before TMS" subtitle="A short check-in for Jamie’s next visit." backTo={routePaths.appointments} className="cc-care-tms">
      <TmsMeasures snapshot={snapshot} onChange={setSnapshot} />
      <label className="cc-care-note-field">
        <span>What has been bothering you most today?</span>
        <textarea value={bothering} onChange={(event) => { setBothering(event.target.value); setAdded(false); }} />
      </label>
      <button type="button" className="cc-care-outline-button" disabled={!bothering.trim() || added} onClick={addForProvider}>{added ? 'Added for the provider' : 'Add this to tell the provider'}</button>
      <label className="cc-care-note-field">
        <span>Provider-supplied focus item</span>
        <textarea value={providerNote} onChange={(event) => setProviderNote(event.target.value)} />
      </label>
      <ProvenanceLine provenance={{ voice: 'provider', label: 'TMS team supplied this', detail: 'Visit instructions, Sep 5 at 9:12 AM' }} />
      <StatusNotice title="You set the focus"><p>Candy Corn does not create treatment provocations. It only organizes what you and your provider supply.</p></StatusNotice>
      <button type="button" className="cc-button cc-button--primary cc-care-full-button" onClick={() => navigate(routePaths.prepareTms)}>Save pre-session check-in</button>
    </ScreenLayout>
  );
}

export function TmsPostSessionScreen() {
  const [snapshot, setSnapshot] = useState<TmsSnapshot>({ mood: 6, anxiety: 5, energy: 4, distress: 5 });
  const [providerInstructions, setProviderInstructions] = useState('Keep the usual schedule and note anything you want to discuss next time.');
  const [nextItem, setNextItem] = useState('Ask whether the head pressure is expected to stay this brief.');
  const [saved, setSaved] = useState(false);

  if (saved) {
    return (
      <ScreenLayout title="Post-session check-in saved" subtitle="Saved on this device." backTo={routePaths.appointments}>
        <StatusNotice title="Saved on this device" voice="user"><p>Your notes are recorded without claiming what caused a change.</p></StatusNotice>
        <div className="cc-care-post-actions">
          <Link className="cc-button cc-button--primary" to={routePaths.history}>Open History</Link>
          <Link className="cc-button" to={routePaths.prepareTms}>Prepare for TMS</Link>
        </div>
      </ScreenLayout>
    );
  }

  return (
    <ScreenLayout title="After TMS" subtitle="Record what you notice without assigning a cause." backTo={routePaths.appointments} className="cc-care-tms">
      <TmsMeasures snapshot={snapshot} onChange={setSnapshot} />
      <label className="cc-care-note-field">
        <span>Provider instruction notes</span>
        <textarea value={providerInstructions} onChange={(event) => setProviderInstructions(event.target.value)} />
      </label>
      <ProvenanceLine provenance={{ voice: 'provider', label: 'TMS team said this', detail: 'Post-session instructions, Sep 5 at 9:56 AM' }} />
      <label className="cc-care-note-field">
        <span>One thing for next session</span>
        <textarea value={nextItem} onChange={(event) => setNextItem(event.target.value)} />
      </label>
      <p className="cc-care-causality-note">This check-in records timing and context. It does not claim that TMS caused a mood or symptom change.</p>
      <button type="button" className="cc-button cc-button--primary cc-care-full-button" onClick={() => setSaved(true)}>Save post-session check-in</button>
    </ScreenLayout>
  );
}

export const screens = defineScreens([
  { id: 'appointments', path: routePaths.appointments, title: 'Appointments', reviewLabel: 'Appointments', order: 12, primarySection: 'today', showBottomNav: true, component: AppointmentsScreen },
  { id: 'recordAppointment', path: routePaths.recordAppointment, title: 'Record an appointment', reviewLabel: 'Record appointment', order: 13, primarySection: null, showBottomNav: false, component: RecordAppointmentScreen },
  { id: 'activeAppointment', path: routePaths.activeAppointment, title: 'Active appointment recording', reviewLabel: 'Active recording', order: 14, primarySection: null, showBottomNav: false, component: ActiveAppointmentScreen },
  { id: 'therapySession', path: routePaths.therapySession, title: 'Therapy session', reviewLabel: 'Therapy session detail', order: 15, primarySection: 'history', showBottomNav: true, component: TherapySessionScreen },
  { id: 'tmsPre', path: routePaths.tmsPre, title: 'Before TMS', reviewLabel: 'TMS pre-session', order: 16, primarySection: 'prepare', showBottomNav: false, component: TmsPreSessionScreen },
  { id: 'tmsPost', path: routePaths.tmsPost, title: 'After TMS', reviewLabel: 'TMS post-session', order: 17, primarySection: 'history', showBottomNav: false, component: TmsPostSessionScreen },
]);
