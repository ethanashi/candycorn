import { Link } from 'react-router-dom';
import { KernelGlyph } from '@/components/KernelGlyph';
import type { Provenance } from '@/core/types';

export interface ProvenanceLineProps { provenance: Provenance; compact?: boolean }

export function ProvenanceLine({ provenance, compact = false }: ProvenanceLineProps) {
  const copy = (
    <span className="cc-provenance-copy">
      <strong>{provenance.label}</strong>
      <span>{provenance.detail}</span>
    </span>
  );
  return (
    <div className={`cc-provenance-line${compact ? ' cc-provenance-line--compact' : ''}`}>
      <KernelGlyph voice={provenance.voice} size={compact ? 16 : 18} decorative />
      {provenance.sourcePath ? <Link to={provenance.sourcePath}>{copy}</Link> : copy}
    </div>
  );
}
