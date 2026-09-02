import type { ReactNode } from 'react';
import { KernelGlyph } from '@/components/KernelGlyph';
import type { ProvenanceVoice } from '@/core/types';

interface StatusNoticeProps {
  title: string;
  children: ReactNode;
  voice?: ProvenanceVoice;
  action?: ReactNode;
}

export function StatusNotice({ title, children, voice = 'candy-corn', action }: StatusNoticeProps) {
  return (
    <section className="cc-status-notice" aria-label={title}>
      <KernelGlyph voice={voice} size={18} decorative />
      <div>
        <h2>{title}</h2>
        <div className="cc-status-notice__copy">{children}</div>
        {action ? <div className="cc-status-notice__action">{action}</div> : null}
      </div>
    </section>
  );
}
