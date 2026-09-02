import type { CSSProperties } from 'react';
import type { MoodSnapshot } from '@/core/types';

export interface MoodKernelProps {
  value: Pick<MoodSnapshot, 'mood' | 'anxiety' | 'energy'>;
  interactive?: boolean;
  onChange?: (dimension: 'mood' | 'anxiety' | 'energy', value: number) => void;
  compact?: boolean;
}

type MoodDimension = 'anxiety' | 'mood' | 'energy';

const dimensions: readonly { id: MoodDimension; label: string }[] = [
  { id: 'anxiety', label: 'Anxiety' },
  { id: 'mood', label: 'Mood' },
  { id: 'energy', label: 'Energy' },
];

export function clampMoodValue(value: number | null): number | null {
  if (value === null || !Number.isFinite(value)) return null;
  return Math.min(10, Math.max(1, Math.round(value)));
}

function MoodBand({
  dimension,
  label,
  value,
  interactive,
  onChange,
}: {
  dimension: MoodDimension;
  label: string;
  value: number | null;
  interactive: boolean;
  onChange?: MoodKernelProps['onChange'];
}) {
  const clamped = clampMoodValue(value);
  const style = { '--cc-mood-fill': `${clamped === null ? 0 : clamped * 10}%` } as CSSProperties;
  const content = (
    <>
      <span>{label}</span>
      <span className="cc-mood-band__value">{clamped === null ? 'Not logged' : `${clamped}/10`}</span>
    </>
  );
  if (!interactive) {
    return <div className={`cc-mood-band cc-mood-band--${dimension}`} style={style}>{content}</div>;
  }
  return (
    <button
      className={`cc-mood-band cc-mood-band--${dimension}`}
      type="button"
      style={style}
      aria-label={`${label}, ${clamped ?? 'not logged'}. Increase value`}
      onClick={() => onChange?.(dimension, clamped === null || clamped >= 10 ? 1 : clamped + 1)}
    >
      {content}
    </button>
  );
}

export function MoodKernel({ value, interactive = false, onChange, compact = false }: MoodKernelProps) {
  if (interactive && onChange === undefined) {
    throw new Error('Interactive MoodKernel requires an onChange handler.');
  }
  return (
    <div
      className={`cc-mood-kernel${compact ? ' cc-mood-kernel--compact' : ''}`}
      aria-label="Mood check-in"
      data-testid="mood-kernel"
    >
      {dimensions.map(({ id, label }) => (
        <MoodBand
          key={id}
          dimension={id}
          label={label}
          value={value[id]}
          interactive={interactive}
          onChange={onChange}
        />
      ))}
    </div>
  );
}
