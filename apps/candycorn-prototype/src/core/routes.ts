export const routePaths = {
  welcome: '/welcome', today: '/today', checkIn: '/check-in', capture: '/capture',
  journalVoice: '/journal/voice', journalWrite: '/journal/write', journalPhoto: '/journal/photo',
  journalDetail: '/journal/entry/football-and-guilt', journalSuggestions: '/journal/suggestions',
  goals: '/goals', bringUp: '/bring-up', appointments: '/appointments',
  recordAppointment: '/appointments/record', activeAppointment: '/appointments/active',
  therapySession: '/sessions/therapy-sep-2', tmsPre: '/tms/pre-session',
  tmsPost: '/tms/post-session', prepareTherapy: '/prepare/therapy',
  prepareTms: '/prepare/tms', history: '/history', search: '/search',
  settingsPrivacy: '/settings/privacy', settingsAi: '/settings/ai', settingsData: '/settings/data',
} as const;

export type ScreenId = keyof typeof routePaths;
export type ScreenPath = (typeof routePaths)[ScreenId];
