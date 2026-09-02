import { createContext, type Dispatch, type PropsWithChildren, useContext, useMemo, useReducer } from 'react';
import { createInitialDemoState } from '@/core/seeded-data';
import type {
  AiMode,
  AiProvider,
  DemoActions,
  DemoState,
  Goal,
  MoodSnapshot,
  TalkingPoint,
  TalkingPointStatus,
} from '@/core/types';

type DemoAction =
  | { type: 'save-mood'; value: MoodSnapshot }
  | { type: 'add-goal'; value: Goal }
  | { type: 'toggle-goal'; id: string }
  | { type: 'add-talking-point'; value: TalkingPoint }
  | { type: 'update-talking-point-status'; id: string; status: TalkingPointStatus }
  | { type: 'set-ai-mode'; mode: AiMode }
  | { type: 'set-ai-provider'; provider: AiProvider }
  | { type: 'set-consent'; value: boolean }
  | { type: 'reset' };

interface DemoContextValue { state: DemoState; actions: DemoActions }

const DemoStateContext = createContext<DemoContextValue | null>(null);

export function demoReducer(state: DemoState, action: DemoAction): DemoState {
  switch (action.type) {
    case 'save-mood':
      return { ...state, mood: { ...action.value } };
    case 'add-goal':
      return state.goals.some((goal) => goal.id === action.value.id)
        ? state
        : { ...state, goals: [...state.goals, { ...action.value, provenance: { ...action.value.provenance } }] };
    case 'toggle-goal':
      return { ...state, goals: state.goals.map((goal) => goal.id === action.id ? { ...goal, completed: !goal.completed } : goal) };
    case 'add-talking-point':
      return state.talkingPoints.some((point) => point.id === action.value.id)
        ? state
        : { ...state, talkingPoints: [...state.talkingPoints, { ...action.value, provenance: { ...action.value.provenance } }] };
    case 'update-talking-point-status':
      return { ...state, talkingPoints: state.talkingPoints.map((point) => point.id === action.id ? { ...point, status: action.status } : point) };
    case 'set-ai-mode':
      return {
        ...state,
        ai: { ...state.ai, mode: action.mode, provider: action.mode === 'off' ? 'off' : state.ai.provider },
      };
    case 'set-ai-provider':
      return {
        ...state,
        ai: { ...state.ai, provider: state.ai.mode === 'off' ? 'off' : action.provider },
      };
    case 'set-consent':
      return { ...state, consentAcknowledged: action.value };
    case 'reset':
      return createInitialDemoState();
  }
}

function buildActions(dispatch: Dispatch<DemoAction>): DemoActions {
  return {
    saveMood: (value) => dispatch({ type: 'save-mood', value }),
    addGoal: (value) => dispatch({ type: 'add-goal', value }),
    toggleGoal: (id) => dispatch({ type: 'toggle-goal', id }),
    addTalkingPoint: (value) => dispatch({ type: 'add-talking-point', value }),
    updateTalkingPointStatus: (id, status) => dispatch({ type: 'update-talking-point-status', id, status }),
    setAiMode: (mode) => dispatch({ type: 'set-ai-mode', mode }),
    setAiProvider: (provider) => dispatch({ type: 'set-ai-provider', provider }),
    setConsentAcknowledged: (value) => dispatch({ type: 'set-consent', value }),
    resetDemo: () => dispatch({ type: 'reset' }),
  };
}

export function DemoStateProvider({ children }: PropsWithChildren) {
  const [state, dispatch] = useReducer(demoReducer, undefined, createInitialDemoState);
  const actions = useMemo(() => buildActions(dispatch), [dispatch]);
  const value = useMemo(() => ({ state, actions }), [state, actions]);
  return <DemoStateContext.Provider value={value}>{children}</DemoStateContext.Provider>;
}

export function useDemoState(): DemoContextValue {
  const context = useContext(DemoStateContext);
  if (context === null) {
    throw new Error('useDemoState must be used inside DemoStateProvider.');
  }
  return context;
}
