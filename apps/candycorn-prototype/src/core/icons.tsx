import {
  ArrowLeft,
  CalendarDays,
  Camera,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Download,
  FileText,
  History,
  Home,
  ListPlus,
  Mic,
  Pause,
  Pencil,
  Play,
  Plus,
  Search,
  Settings,
  Shield,
  Sparkles,
  Square,
  Trash2,
  Volume2,
  X,
  type LucideIcon,
  type LucideProps,
} from 'lucide-react';

export const iconRegistry = {
  back: { icon: ArrowLeft, sfSymbol: 'chevron.left' },
  calendar: { icon: CalendarDays, sfSymbol: 'calendar' },
  camera: { icon: Camera, sfSymbol: 'camera' },
  capture: { icon: Plus, sfSymbol: 'plus.circle.fill' },
  check: { icon: Check, sfSymbol: 'checkmark' },
  checkCircle: { icon: CheckCircle2, sfSymbol: 'checkmark.circle' },
  chevronDown: { icon: ChevronDown, sfSymbol: 'chevron.down' },
  chevronLeft: { icon: ChevronLeft, sfSymbol: 'chevron.left' },
  chevronRight: { icon: ChevronRight, sfSymbol: 'chevron.right' },
  clock: { icon: Clock3, sfSymbol: 'clock' },
  close: { icon: X, sfSymbol: 'xmark' },
  download: { icon: Download, sfSymbol: 'square.and.arrow.down' },
  history: { icon: History, sfSymbol: 'clock.arrow.circlepath' },
  home: { icon: Home, sfSymbol: 'house' },
  journal: { icon: FileText, sfSymbol: 'square.and.pencil' },
  listPlus: { icon: ListPlus, sfSymbol: 'text.badge.plus' },
  microphone: { icon: Mic, sfSymbol: 'mic' },
  pause: { icon: Pause, sfSymbol: 'pause.fill' },
  pencil: { icon: Pencil, sfSymbol: 'pencil' },
  play: { icon: Play, sfSymbol: 'play.fill' },
  prepare: { icon: CalendarDays, sfSymbol: 'calendar.badge.clock' },
  search: { icon: Search, sfSymbol: 'magnifyingglass' },
  settings: { icon: Settings, sfSymbol: 'gearshape' },
  shield: { icon: Shield, sfSymbol: 'lock.shield' },
  sparkles: { icon: Sparkles, sfSymbol: 'sparkles' },
  stop: { icon: Square, sfSymbol: 'stop.fill' },
  trash: { icon: Trash2, sfSymbol: 'trash' },
  volume: { icon: Volume2, sfSymbol: 'speaker.wave.2' },
} as const satisfies Record<string, { icon: LucideIcon; sfSymbol: string }>;

export type AppIconName = keyof typeof iconRegistry;

interface AppIconProps extends Omit<LucideProps, 'name'> {
  name: AppIconName;
  decorative?: boolean;
  label?: string;
}

export function AppIcon({ name, decorative = true, label, ...iconProps }: AppIconProps) {
  const Icon = iconRegistry[name].icon;
  if (!decorative && !label?.trim()) {
    throw new Error(`Non-decorative icon ${name} requires a label.`);
  }
  return (
    <Icon
      aria-hidden={decorative ? true : undefined}
      aria-label={decorative ? undefined : label}
      role={decorative ? undefined : 'img'}
      focusable="false"
      {...iconProps}
    />
  );
}
