import type { JournalEntry, TranscriptSegment } from '@/core/types';

export interface LocalRecording { id: string; durationMilliseconds: number; localUrl: string }
export interface RecordingPort {
  start(kind: 'journal' | 'appointment'): Promise<void>;
  finish(): Promise<LocalRecording>;
  cancel(): Promise<void>;
}
export interface PhotoCapturePort { captureJournalPage(): Promise<{ localUrl: string }> }
export interface ProcessingPort {
  transcribe(recording: LocalRecording): Promise<TranscriptSegment[]>;
  organizeJournal(entry: JournalEntry): Promise<JournalEntry>;
}
export interface ExportPort { exportArchive(): Promise<{ localUrl: string }> }
export type DeviceOnlyProof =
  | 'background-audio' | 'audio-interruptions' | 'camera-permission'
  | 'encrypted-storage' | 'native-export' | 'dynamic-type' | 'safe-areas';
