import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { KernelGlyph, MoodKernel, clampMoodValue, voiceColorTokens } from '@/components';
import { demoReducer } from '@/core/demo-state';
import { routePaths } from '@/core/routes';
import { createInitialDemoState } from '@/core/seeded-data';
import type { Goal, TalkingPoint } from '@/core/types';

describe('foundation route contract', () => {
  it('contains 24 unique canonical paths', () => {
    const paths = Object.values(routePaths);
    expect(paths).toHaveLength(24);
    expect(new Set(paths).size).toBe(24);
  });
});

describe('provenance kernel', () => {
  it('maps each source voice to its fixed color role', () => {
    expect(voiceColorTokens).toEqual({
      user: 'var(--cc-orange)',
      provider: 'var(--cc-cocoa)',
      'candy-corn': 'var(--cc-yellow)',
    });
  });

  it('exposes meaning unless explicitly decorative', () => {
    const { rerender } = render(<KernelGlyph voice="provider" />);
    expect(screen.getByRole('img', { name: 'Provider said this' })).toBeInTheDocument();
    rerender(<KernelGlyph voice="provider" decorative />);
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
  });
});

describe('mood kernel', () => {
  it('clamps values to the supported range', () => {
    expect(clampMoodValue(-2)).toBe(1);
    expect(clampMoodValue(11)).toBe(10);
    expect(clampMoodValue(5.6)).toBe(6);
  });

  it('renders null values as unfilled', () => {
    render(<MoodKernel value={{ mood: null, anxiety: null, energy: null }} />);
    expect(screen.getAllByText('Not logged')).toHaveLength(3);
    const bands = screen.getByTestId('mood-kernel').querySelectorAll('.cc-mood-band');
    expect(bands).toHaveLength(3);
    bands.forEach((band) => expect(band).toHaveStyle('--cc-mood-fill: 0%'));
  });
});

describe('demo state', () => {
  it('keeps repeated goal and talking-point additions idempotent by id', () => {
    const initial = createInitialDemoState();
    const goal: Goal = { ...initial.goals[0]!, provenance: { ...initial.goals[0]!.provenance } };
    const point: TalkingPoint = { ...initial.talkingPoints[0]!, provenance: { ...initial.talkingPoints[0]!.provenance } };
    const afterGoal = demoReducer(initial, { type: 'add-goal', value: goal });
    const afterPoint = demoReducer(afterGoal, { type: 'add-talking-point', value: point });
    expect(afterPoint).toBe(initial);
    expect(afterPoint.goals).toHaveLength(initial.goals.length);
    expect(afterPoint.talkingPoints).toHaveLength(initial.talkingPoints.length);
  });

  it('forces the provider off when AI is turned off', () => {
    const initial = createInitialDemoState();
    const disabled = demoReducer(initial, { type: 'set-ai-mode', mode: 'off' });
    expect(disabled.ai).toMatchObject({ mode: 'off', provider: 'off' });
    const providerAttempt = demoReducer(disabled, { type: 'set-ai-provider', provider: 'router' });
    expect(providerAttempt.ai.provider).toBe('off');
  });
});
