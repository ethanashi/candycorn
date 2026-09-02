import type { ScreenPath } from '@/core/routes';

export type ProvenanceVoice = 'user' | 'provider' | 'candy-corn';
export interface Provenance {
  voice: ProvenanceVoice;
  label: string;
  detail: string;
  occurredAt?: string;
  sourcePath?: ScreenPath;
}
export interface MoodSnapshot {
  mood: number | null;
  anxiety: number | null;
  energy: number | null;
  distress?: number | null;
  note: string;
  recordedAt: string;
}
export type GoalCadence = 'today' | 'this-week' | 'this-month' | 'ongoing' | 'homework';
export interface Goal {
  id: string;
  text: string;
  cadence: GoalCadence;
  completed: boolean;
  provenance: Provenance;
}
export type TalkingPointStatus = 'open' | 'discussed' | 'dismissed';
export interface TalkingPoint {
  id: string;
  text: string;
  target: 'therapy' | 'tms' | 'psychiatry' | 'other';
  priority: 'normal' | 'important';
  status: TalkingPointStatus;
  provenance: Provenance;
}
export type JournalSource = 'voice' | 'text' | 'photo';
export interface JournalEntry {
  id: string;
  source: JournalSource;
  title: string;
  createdAt: string;
  original: string;
  cleaned: string;
  summary: string[];
  originalAssetPath?: string;
}
export type AppointmentType = 'therapy' | 'tms' | 'psychiatry' | 'other';
export interface Appointment {
  id: string;
  type: AppointmentType;
  providerName: string;
  startsAt: string;
  durationMinutes?: number;
  status: 'upcoming' | 'completed';
}
export type TranscriptSpeaker = 'patient' | 'provider' | 'unknown';
export interface TranscriptSegment {
  id: string;
  speaker: TranscriptSpeaker;
  startMilliseconds: number;
  endMilliseconds: number;
  text: string;
  confidence?: number;
}
export type AiMode = 'off' | 'organizer' | 'reflection';
export type AiProvider = 'on-device-when-available' | 'router' | 'off';
export interface AiSettings { mode: AiMode; provider: AiProvider; routerAvailable: boolean }
export interface DemoState {
  mood: MoodSnapshot;
  goals: Goal[];
  talkingPoints: TalkingPoint[];
  ai: AiSettings;
  consentAcknowledged: boolean;
}
export interface DemoActions {
  saveMood(value: MoodSnapshot): void;
  addGoal(value: Goal): void;
  toggleGoal(id: string): void;
  addTalkingPoint(value: TalkingPoint): void;
  updateTalkingPointStatus(id: string, status: TalkingPointStatus): void;
  setAiMode(mode: AiMode): void;
  setAiProvider(provider: AiProvider): void;
  setConsentAcknowledged(value: boolean): void;
  resetDemo(): void;
}
