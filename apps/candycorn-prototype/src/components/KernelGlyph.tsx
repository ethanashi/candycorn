import type { ProvenanceVoice } from '@/core/types';

export interface KernelGlyphProps {
  voice: ProvenanceVoice;
  size?: 16 | 18 | 20;
  decorative?: boolean;
}

export const voiceColorTokens: Readonly<Record<ProvenanceVoice, string>> = {
  user: 'var(--cc-orange)',
  provider: 'var(--cc-cocoa)',
  'candy-corn': 'var(--cc-yellow)',
};

const voiceLabels: Readonly<Record<ProvenanceVoice, string>> = {
  user: 'You said or chose this',
  provider: 'Provider said this',
  'candy-corn': 'Candy Corn suggested this',
};

export function KernelGlyph({ voice, size = 18, decorative = false }: KernelGlyphProps) {
  const width = Math.round(size / 1.3);
  return (
    <svg
      className="cc-kernel-glyph"
      width={width}
      height={size}
      viewBox="0 0 14 18"
      fill="none"
      aria-hidden={decorative ? true : undefined}
      aria-label={decorative ? undefined : voiceLabels[voice]}
      role={decorative ? undefined : 'img'}
      focusable="false"
      data-voice={voice}
    >
      <path
        d="M5.13 1.64a2.2 2.2 0 0 1 3.74 0l4.69 12.07A2.4 2.4 0 0 1 11.32 17H2.68a2.4 2.4 0 0 1-2.24-3.29L5.13 1.64Z"
        fill={voiceColorTokens[voice]}
      />
    </svg>
  );
}
