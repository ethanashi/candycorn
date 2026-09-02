import { routePaths } from '@/core/routes';
import type {
  Appointment,
  DemoState,
  Goal,
  JournalEntry,
  TalkingPoint,
  TranscriptSegment,
} from '@/core/types';

export const fictionalPatientName = 'Jamie Rivera';

export const seededGoals: readonly Goal[] = [
  {
    id: 'notice-moving-forward-guilt',
    text: 'Notice when moving-forward guilt appears',
    cadence: 'today',
    completed: false,
    provenance: {
      voice: 'user',
      label: 'You chose this',
      detail: 'Journal, Sep 5 at 3:18 PM',
      occurredAt: '2026-09-05T15:18:00-07:00',
      sourcePath: routePaths.journalDetail,
    },
  },
  {
    id: 'write-guilt-example',
    text: 'Write down one example if guilt shows up',
    cadence: 'this-week',
    completed: false,
    provenance: {
      voice: 'candy-corn',
      label: 'Candy Corn suggested this',
      detail: 'Based on your Sep 5 journal. You added it.',
      occurredAt: '2026-09-05T15:20:00-07:00',
      sourcePath: routePaths.journalSuggestions,
    },
  },
  {
    id: 'finish-senior-year-timeline',
    text: 'Finish the senior-year football timeline',
    cadence: 'homework',
    completed: true,
    provenance: {
      voice: 'provider',
      label: 'Therapist assigned this',
      detail: 'Therapy, Sep 2 at 42:18',
      occurredAt: '2026-09-02T14:42:18-07:00',
      sourcePath: routePaths.therapySession,
    },
  },
  {
    id: 'exercise-when-stuck',
    text: 'Use exercise when thoughts feel stuck',
    cadence: 'ongoing',
    completed: false,
    provenance: {
      voice: 'user',
      label: 'You chose this',
      detail: 'Journal, Sep 3 at 4:06 PM',
      occurredAt: '2026-09-03T16:06:00-07:00',
      sourcePath: routePaths.journalDetail,
    },
  },
];

export const seededTalkingPoints: readonly TalkingPoint[] = [
  {
    id: 'proof-stuck-point',
    text: 'Is needing proof that I could have played the part that keeps me stuck?',
    target: 'therapy',
    priority: 'important',
    status: 'open',
    provenance: {
      voice: 'user',
      label: 'You pinned this',
      detail: 'Journal, Sep 5 at 3:18 PM',
      occurredAt: '2026-09-05T15:18:00-07:00',
      sourcePath: routePaths.journalDetail,
    },
  },
  {
    id: 'moving-forward-dismissive',
    text: 'Why does moving forward sometimes feel like dismissing what happened?',
    target: 'therapy',
    priority: 'normal',
    status: 'open',
    provenance: {
      voice: 'candy-corn',
      label: 'Candy Corn suggested this',
      detail: 'Based on two journal entries. You added it.',
      occurredAt: '2026-09-05T15:20:00-07:00',
      sourcePath: routePaths.journalSuggestions,
    },
  },
  {
    id: 'senior-year-coach-meeting',
    text: 'The senior-year meeting with the coaches',
    target: 'therapy',
    priority: 'normal',
    status: 'open',
    provenance: {
      voice: 'provider',
      label: 'Therapist asked to revisit this',
      detail: 'Therapy, Sep 2 at 38:44',
      occurredAt: '2026-09-02T14:38:44-07:00',
      sourcePath: routePaths.therapySession,
    },
  },
];

export const seededJournalEntries: readonly JournalEntry[] = [
  {
    id: 'football-and-guilt',
    source: 'voice',
    title: 'Football and feeling guilty',
    createdAt: '2026-09-05T15:18:00-07:00',
    original: 'Work was fine until around three when I started thinking about football again. I got angry, went to the gym, and felt better. Then I realized I had not thought about it for a few hours, and I felt guilty about that.',
    cleaned: 'Work was going well until around 3 PM, when I started thinking about football again and became frustrated. Going to the gym helped. Later, I realized I had gone a few hours without thinking about football, and that made me feel guilty.',
    summary: [
      'Football thoughts interrupted an otherwise steady workday.',
      'Exercise helped you feel better for a while.',
      'Feeling better was followed by guilt.',
    ],
  },
  {
    id: 'senior-year-timeline',
    source: 'text',
    title: 'The senior-year timeline',
    createdAt: '2026-09-03T16:06:00-07:00',
    original: 'I finished the senior-year section. What still bothers me is never getting the chance to prove I could have played.',
    cleaned: 'I finished writing the senior-year section. What still bothers me is that I never had the chance to prove I could have played.',
    summary: ['Finished the assigned timeline.', 'The missed chance to prove ability still feels unresolved.'],
  },
];

export const seededAppointments: readonly Appointment[] = [
  {
    id: 'therapy-sep-9',
    type: 'therapy',
    providerName: 'Dr. Elena Park',
    startsAt: '2026-09-09T14:00:00-07:00',
    durationMinutes: 50,
    status: 'upcoming',
  },
  {
    id: 'tms-sep-5',
    type: 'tms',
    providerName: 'Riverbend TMS team',
    startsAt: '2026-09-05T09:30:00-07:00',
    durationMinutes: 22,
    status: 'completed',
  },
  {
    id: 'therapy-sep-2',
    type: 'therapy',
    providerName: 'Dr. Elena Park',
    startsAt: '2026-09-02T14:00:00-07:00',
    durationMinutes: 50,
    status: 'completed',
  },
];

export const seededTranscript: readonly TranscriptSegment[] = [
  {
    id: 'therapy-sep-2-1',
    speaker: 'patient',
    startMilliseconds: 744000,
    endMilliseconds: 756000,
    text: 'I do not think I miss playing as much as I miss having the chance to prove I could have done it.',
    confidence: 0.96,
  },
  {
    id: 'therapy-sep-2-2',
    speaker: 'provider',
    startMilliseconds: 768000,
    endMilliseconds: 781000,
    text: 'So the part that still hurts may be not getting to test what you believed about yourself.',
    confidence: 0.94,
  },
  {
    id: 'therapy-sep-2-3',
    speaker: 'unknown',
    startMilliseconds: 2324000,
    endMilliseconds: 2331000,
    text: 'Let us make sure we come back to the meeting with the coaches.',
  },
];

export function createInitialDemoState(): DemoState {
  return {
    mood: {
      mood: 6,
      anxiety: 7,
      energy: 4,
      note: 'Exercise helped today, then the guilt showed up.',
      recordedAt: '2026-09-05T17:30:00-07:00',
    },
    goals: seededGoals.map((goal) => ({ ...goal, provenance: { ...goal.provenance } })),
    talkingPoints: seededTalkingPoints.map((point) => ({ ...point, provenance: { ...point.provenance } })),
    ai: { mode: 'organizer', provider: 'router', routerAvailable: true },
    consentAcknowledged: false,
  };
}
