import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import {
  KernelGlyph,
  MoodKernel,
  ProvenanceLine,
  ScreenLayout,
  SelectableTabs,
} from '@/components';
import { useDemoState } from '@/core/demo-state';
import { AppIcon } from '@/core/icons';
import { routePaths, type ScreenPath } from '@/core/routes';
import { defineScreens } from '@/core/screen-registry';
import type { Goal, GoalCadence, Provenance, TalkingPoint } from '@/core/types';
import './continuity.css';

const cadenceOrder: readonly GoalCadence[] = ['today', 'this-week', 'this-month', 'ongoing', 'homework'];
const cadenceLabels: Readonly<Record<GoalCadence, string>> = {
  today: 'Today',
  'this-week': 'This week',
  'this-month': 'This month',
  ongoing: 'Ongoing',
  homework: 'Homework',
};

const tmsTalkingPoint: TalkingPoint = {
  id: 'tms-sleep-and-headache-notes',
  text: 'Share sleep and headache notes before the next TMS visit',
  target: 'tms',
  priority: 'important',
  status: 'open',
  provenance: {
    voice: 'provider',
    label: 'TMS team asked you to track this',
    detail: 'TMS visit, Sep 5 at 9:52 AM',
    occurredAt: '2026-09-05T09:52:00-07:00',
    sourcePath: routePaths.tmsPost,
  },
};

function provenanceText(provenance: Provenance): Provenance {
  return {
    voice: provenance.voice,
    label: provenance.label,
    detail: provenance.detail,
    ...(provenance.occurredAt === undefined ? {} : { occurredAt: provenance.occurredAt }),
  };
}

function GoalRow({ goal, onToggle }: { goal: Goal; onToggle(id: string): void }) {
  const action = goal.completed ? 'Mark incomplete' : 'Mark complete';
  const provenance = goal.id === 'finish-senior-year-timeline'
    ? { ...goal.provenance, detail: 'Therapy on Sep 2 at 42:18' }
    : goal.provenance;
  return (
    <li className={`cc-goal-row${goal.completed ? ' cc-goal-row--completed' : ''}`}>
      <button type="button" className="cc-goal-toggle" aria-label={`${action}: ${goal.text}`} aria-pressed={goal.completed} onClick={() => onToggle(goal.id)}>
        {goal.completed ? <AppIcon name="check" size={18} strokeWidth={2.5} /> : null}
      </button>
      <div className="cc-goal-row__copy">
        <strong>{goal.text}</strong>
        <ProvenanceLine provenance={provenanceText(provenance)} compact />
      </div>
    </li>
  );
}

function GoalSection({ cadence, goals, open, onToggleOpen, onToggleGoal }: {
  cadence: GoalCadence;
  goals: readonly Goal[];
  open: boolean;
  onToggleOpen(cadence: GoalCadence): void;
  onToggleGoal(id: string): void;
}) {
  const label = cadenceLabels[cadence];
  return (
    <section className="cc-goal-section" aria-labelledby={`cc-goals-${cadence}`}>
      <button type="button" className="cc-goal-section__toggle" aria-expanded={open} aria-controls={`cc-goals-list-${cadence}`} onClick={() => onToggleOpen(cadence)}>
        <span id={`cc-goals-${cadence}`}>{label}</span>
        <span className="cc-goal-section__count">{goals.length}</span>
        <AppIcon name="chevronDown" size={18} />
      </button>
      {open ? (
        <div id={`cc-goals-list-${cadence}`}>
          {goals.length > 0 ? <ul>{goals.map((goal) => <GoalRow key={goal.id} goal={goal} onToggle={onToggleGoal} />)}</ul> : <p className="cc-goal-empty">No goals here yet.</p>}
        </div>
      ) : null}
    </section>
  );
}

export function GoalsScreen() {
  const { state, actions } = useDemoState();
  const [collapsed, setCollapsed] = useState<ReadonlySet<GoalCadence>>(() => new Set());

  function toggleSection(cadence: GoalCadence) {
    setCollapsed((current) => {
      const next = new Set(current);
      if (next.has(cadence)) next.delete(cadence);
      else next.add(cadence);
      return next;
    });
  }

  return (
    <ScreenLayout title="Goals" subtitle="What you chose, what was assigned, and what still needs your approval." className="cc-goals">
      <div className="cc-goal-ledger">
        {cadenceOrder.map((cadence) => (
          <GoalSection key={cadence} cadence={cadence} goals={state.goals.filter((goal) => goal.cadence === cadence)} open={!collapsed.has(cadence)} onToggleOpen={toggleSection} onToggleGoal={actions.toggleGoal} />
        ))}
      </div>
    </ScreenLayout>
  );
}

function targetLabel(point: TalkingPoint): string {
  if (point.target === 'therapy') return 'Therapy with Dr. Elena Park, Sep 9';
  if (point.target === 'tms') return 'Next TMS visit';
  if (point.target === 'psychiatry') return 'Next psychiatry visit';
  return 'Next care conversation';
}

function TalkingPointRow({ point, onStatus }: { point: TalkingPoint; onStatus(id: string, status: 'discussed' | 'dismissed'): void }) {
  return (
    <li className="cc-bring-up-row">
      <div className="cc-bring-up-row__heading">
        <strong>{point.text}</strong>
      </div>
      <p className="cc-bring-up-row__meta">{point.priority === 'important' ? 'Important' : 'Normal priority'} · {targetLabel(point)}</p>
      <ProvenanceLine provenance={provenanceText(point.provenance)} compact />
      <div className="cc-bring-up-row__actions">
        <button type="button" onClick={() => onStatus(point.id, 'discussed')} aria-label={`Mark discussed: ${point.text}`}>Discussed</button>
        <button type="button" onClick={() => onStatus(point.id, 'dismissed')} aria-label={`Dismiss: ${point.text}`}>Dismiss</button>
      </div>
    </li>
  );
}

export function BringUpScreen() {
  const { state, actions } = useDemoState();
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const manualItemExists = state.talkingPoints.some((point) => point.id === 'manual-next-appointment');
  const openItems = state.talkingPoints.filter((point) => point.status === 'open');

  useEffect(() => { actions.addTalkingPoint(tmsTalkingPoint); }, [actions]);

  function addManualItem(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const text = draft.trim();
    if (text.length === 0) {
      setError('Write what you want to bring up first.');
      return;
    }
    const provenance: Provenance = { voice: 'user', label: 'You added this', detail: 'Bring up next time, Sep 5' };
    actions.addTalkingPoint({ id: 'manual-next-appointment', text, target: 'therapy', priority: 'normal', status: 'open', provenance });
    setDraft('');
    setError('');
  }

  return (
    <ScreenLayout title="Bring up next time" subtitle="A short inbox for the conversations you do not want to lose." backTo={routePaths.today} className="cc-bring-up">
      {openItems.length > 0 ? <ul className="cc-bring-up-list">{openItems.map((point) => <TalkingPointRow key={point.id} point={point} onStatus={actions.updateTalkingPointStatus} />)}</ul> : (
        <div className="cc-continuity-empty"><KernelGlyph voice="user" size={20} decorative /><h2>Nothing waiting for the next appointment</h2><p>You can return here whenever something comes up.</p><Link to={routePaths.today}>Back to Today</Link></div>
      )}
      <section className="cc-manual-point" aria-labelledby="cc-manual-point-heading">
        <h2 id="cc-manual-point-heading">Add your own</h2>
        {manualItemExists ? <p className="cc-manual-point__complete">Your manual item is in the inbox. You can discuss or dismiss it above.</p> : (
          <form onSubmit={addManualItem} noValidate>
            <label htmlFor="manual-talking-point">What do you want to remember?</label>
            <textarea id="manual-talking-point" maxLength={200} rows={3} value={draft} onChange={(event) => { setDraft(event.target.value); setError(''); }} />
            {error ? <p className="cc-field-error" role="alert">{error}</p> : null}
            <button type="submit" className="cc-button cc-button--primary">Add to inbox</button>
          </form>
        )}
      </section>
    </ScreenLayout>
  );
}

type HistoryFilter = 'all' | 'journal' | 'mood' | 'therapy' | 'tms';
interface HistoryEntry {
  id: string;
  day: 'Sep 5' | 'Sep 3' | 'Sep 2';
  type: Exclude<HistoryFilter, 'all'>;
  label: string;
  time: string;
  excerpt: string;
  to: ScreenPath;
}

const historyFilters: readonly { value: HistoryFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'journal', label: 'Journal' },
  { value: 'mood', label: 'Mood' },
  { value: 'therapy', label: 'Therapy' },
  { value: 'tms', label: 'TMS' },
];

const historyEntries: readonly HistoryEntry[] = [
  { id: 'journal-football', day: 'Sep 5', type: 'journal', label: 'Football and feeling guilty', time: '3:18 PM', excerpt: 'Exercise helped, then feeling better brought up guilt.', to: routePaths.journalDetail },
  { id: 'tms-post', day: 'Sep 5', type: 'tms', label: 'TMS post-session note', time: '9:52 AM', excerpt: 'Saved observations without claiming what caused the change.', to: routePaths.tmsPost },
  { id: 'journal-timeline', day: 'Sep 3', type: 'journal', label: 'The senior-year timeline', time: '4:06 PM', excerpt: 'The missed chance to prove I could have played still feels unresolved.', to: routePaths.journalDetail },
  { id: 'therapy-session', day: 'Sep 2', type: 'therapy', label: 'Therapy with Dr. Elena Park', time: '2:00 PM', excerpt: 'Worked on the senior-year story and moving-forward guilt.', to: routePaths.therapySession },
];

function HistoryRow({ entry }: { entry: HistoryEntry }) {
  return (
    <li><Link className="cc-history-row" to={entry.to}>
      <span className="cc-history-row__top"><strong>{entry.label}</strong><time>{entry.time}</time></span>
      <span className="cc-history-row__type">{entry.type === 'tms' ? 'TMS' : `${entry.type[0]?.toUpperCase()}${entry.type.slice(1)}`}</span>
      <span className="cc-history-row__excerpt">{entry.excerpt}</span>
      <AppIcon name="chevronRight" size={18} />
    </Link></li>
  );
}

export function HistoryScreen() {
  const { state } = useDemoState();
  const [filter, setFilter] = useState<HistoryFilter>('all');
  const hasMood = state.mood.mood !== null || state.mood.anxiety !== null || state.mood.energy !== null;
  const moodEntry: HistoryEntry = { id: 'mood-sep-5', day: 'Sep 5', type: 'mood', label: 'Mood check-in', time: '5:30 PM', excerpt: state.mood.note || 'Mood, anxiety, and energy saved.', to: routePaths.checkIn };
  const visibleEntries = [...historyEntries, ...(hasMood ? [moodEntry] : [])].filter((entry) => filter === 'all' || entry.type === filter);
  const days: readonly HistoryEntry['day'][] = ['Sep 5', 'Sep 3', 'Sep 2'];

  return (
    <ScreenLayout title="History" subtitle="Your care thread, in the order it happened." className="cc-history">
      <SelectableTabs<HistoryFilter> items={historyFilters} value={filter} onChange={setFilter} ariaLabel="Filter history" />
      {visibleEntries.length > 0 ? <div className="cc-history-days">{days.map((day) => {
        const dayEntries = visibleEntries.filter((entry) => entry.day === day);
        if (dayEntries.length === 0) return null;
        return <section key={day} aria-labelledby={`cc-history-${day.replace(' ', '-').toLowerCase()}`}><div className="cc-history-day"><h2 id={`cc-history-${day.replace(' ', '-').toLowerCase()}`}>{day}</h2><MoodKernel value={state.mood} compact /></div><ul>{dayEntries.map((entry) => <HistoryRow key={entry.id} entry={entry} />)}</ul></section>;
      })}</div> : <div className="cc-continuity-empty"><KernelGlyph voice="candy-corn" size={20} decorative /><h2>No {historyFilters.find((item) => item.value === filter)?.label.toLowerCase()} entries yet</h2><p>Your other history is still here. Choose a different filter.</p></div>}
    </ScreenLayout>
  );
}

interface SearchRecord {
  id: string;
  title: string;
  excerpt: string;
  searchable: string;
  to: ScreenPath;
  provenance: Provenance;
}

const fixedSearchRecords: readonly SearchRecord[] = [
  { id: 'search-journal-football', title: 'Football and feeling guilty', excerpt: 'Exercise helped, then feeling better brought up guilt.', searchable: 'football guilt exercise feeling better journal', to: routePaths.journalDetail, provenance: { voice: 'user', label: 'You said this', detail: 'Journal, Sep 5 at 3:18 PM', sourcePath: routePaths.journalDetail } },
  { id: 'search-therapy-football', title: 'Senior-year football in therapy', excerpt: 'Not getting the chance to prove you could have played still hurts.', searchable: 'football senior year prove played therapy coaches', to: routePaths.therapySession, provenance: { voice: 'provider', label: 'Dr. Elena Park reflected this', detail: 'Therapy, Sep 2 at 12:48', sourcePath: routePaths.therapySession } },
];

function SearchResult({ record }: { record: SearchRecord }) {
  return (
    <li className="cc-search-result"><Link className="cc-search-result__heading" to={record.to}><strong>{record.title}</strong><AppIcon name="chevronRight" size={18} /></Link><p>{record.excerpt}</p><ProvenanceLine provenance={provenanceText(record.provenance)} compact /></li>
  );
}

function stateSearchRecords(goals: readonly Goal[], points: readonly TalkingPoint[]): SearchRecord[] {
  const goalRecords = goals.map((goal) => ({ id: `goal-${goal.id}`, title: goal.text, excerpt: cadenceLabels[goal.cadence], searchable: `${goal.text} ${goal.provenance.label} ${goal.provenance.detail}`, to: routePaths.goals, provenance: goal.provenance }));
  const pointRecords = points.map((point) => ({ id: `point-${point.id}`, title: point.text, excerpt: targetLabel(point), searchable: `${point.text} ${point.id === 'proof-stuck-point' ? 'football senior year' : ''} ${point.provenance.label} ${point.provenance.detail}`, to: routePaths.bringUp, provenance: point.provenance }));
  return [...goalRecords, ...pointRecords];
}

export function SearchScreen() {
  const { state } = useDemoState();
  const [query, setQuery] = useState('');
  const normalizedQuery = query.trim().toLowerCase();
  const records = useMemo(() => [...fixedSearchRecords, ...stateSearchRecords(state.goals, state.talkingPoints)], [state.goals, state.talkingPoints]);
  const results = normalizedQuery.length === 0 ? [] : records.filter((record) => `${record.title} ${record.excerpt} ${record.searchable}`.toLowerCase().includes(normalizedQuery));

  return (
    <ScreenLayout title="Search memory" subtitle="Search across journals, sessions, goals, and pinned items." className="cc-memory-search">
      <label className="cc-search-field" htmlFor="memory-search"><span>Search your thread</span><span className="cc-search-field__control"><AppIcon name="search" size={20} /><input id="memory-search" type="search" maxLength={120} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Try football" />{query ? <button type="button" onClick={() => setQuery('')} aria-label="Clear memory search"><AppIcon name="close" size={18} /></button> : null}</span></label>
      {normalizedQuery.length === 0 ? <div className="cc-search-prompt"><KernelGlyph voice="candy-corn" size={18} decorative /><p>Try “football” to find where that thread appeared in a journal, therapy, and your appointment inbox.</p><span>Search runs on this device.</span></div> : null}
      {normalizedQuery.length > 0 && results.length > 0 ? <section className="cc-search-results" aria-labelledby="cc-search-results-heading"><h2 id="cc-search-results-heading">{results.length} {results.length === 1 ? 'result' : 'results'}</h2><ul>{results.map((record) => <SearchResult key={record.id} record={record} />)}</ul></section> : null}
      {normalizedQuery.length > 0 && results.length === 0 ? <div className="cc-continuity-empty"><KernelGlyph voice="candy-corn" size={20} decorative /><h2>No seeded memories match “{query.trim()}”</h2><p>Try another word or clear the search. Nothing was sent anywhere.</p><button type="button" onClick={() => setQuery('')}>Clear search</button></div> : null}
    </ScreenLayout>
  );
}

export const screens = defineScreens([
  { id: 'goals', path: routePaths.goals, title: 'Goals', reviewLabel: 'Goals', order: 10, primarySection: 'today', showBottomNav: true, component: GoalsScreen },
  { id: 'bringUp', path: routePaths.bringUp, title: 'Bring up next time', reviewLabel: 'Bring up next time', order: 11, primarySection: 'today', showBottomNav: true, component: BringUpScreen },
  { id: 'history', path: routePaths.history, title: 'History', reviewLabel: 'History timeline', order: 20, primarySection: 'history', showBottomNav: true, component: HistoryScreen },
  { id: 'search', path: routePaths.search, title: 'Search memory', reviewLabel: 'Search and memory', order: 21, primarySection: 'history', showBottomNav: true, component: SearchScreen },
]);
