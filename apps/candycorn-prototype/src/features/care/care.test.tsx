import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DemoStateProvider } from '@/core/demo-state';
import { routePaths } from '@/core/routes';
import {
  ActiveAppointmentScreen,
  AppointmentsScreen,
  RecordAppointmentScreen,
  TherapySessionScreen,
  TmsPostSessionScreen,
  TmsPreSessionScreen,
  screens as careScreens,
} from '@/features/care/screens';

afterEach(cleanup);

function LocationProbe() {
  const location = useLocation();
  return <output aria-label="Current path">{location.pathname}</output>;
}

function renderFeature(element: React.ReactNode, path: string) {
  if (!path.startsWith('/')) throw new Error('Care tests require an absolute route.');
  return render(
    <MemoryRouter initialEntries={[path]}>
      <DemoStateProvider>
        <Routes>
          <Route path="*" element={<>{element}<LocationProbe /></>} />
        </Routes>
      </DemoStateProvider>
    </MemoryRouter>,
  );
}

function renderConsentFlow() {
  return render(
    <MemoryRouter initialEntries={[routePaths.recordAppointment]}>
      <DemoStateProvider>
        <Routes>
          <Route path={routePaths.recordAppointment} element={<RecordAppointmentScreen />} />
          <Route path={routePaths.activeAppointment} element={<><ActiveAppointmentScreen /><LocationProbe /></>} />
          <Route path="*" element={<LocationProbe />} />
        </Routes>
      </DemoStateProvider>
    </MemoryRouter>,
  );
}

describe('care screen registration and appointment list', () => {
  it('registers the six canonical care routes in order', () => {
    expect(careScreens.map((definition) => definition.path)).toEqual([
      routePaths.appointments,
      routePaths.recordAppointment,
      routePaths.activeAppointment,
      routePaths.therapySession,
      routePaths.tmsPre,
      routePaths.tmsPost,
    ]);
    expect(careScreens.map((definition) => definition.order)).toEqual([12, 13, 14, 15, 16, 17]);
  });

  it('links upcoming, TMS, completed, and primary appointment actions', () => {
    renderFeature(<AppointmentsScreen />, routePaths.appointments);
    expect(screen.getByRole('link', { name: 'Record an appointment' })).toHaveAttribute('href', routePaths.recordAppointment);
    expect(screen.getByRole('link', { name: 'Record appointment' })).toHaveAttribute('href', routePaths.recordAppointment);
    expect(screen.getByRole('link', { name: 'Prepare' })).toHaveAttribute('href', routePaths.prepareTherapy);
    expect(screen.getByRole('link', { name: 'Open session' })).toHaveAttribute('href', routePaths.therapySession);
    expect(screen.getByRole('link', { name: 'Review check-in' })).toHaveAttribute('href', routePaths.tmsPost);
    expect(screen.getByText('Riverbend TMS team')).toBeVisible();
  });
});

describe('appointment consent', () => {
  beforeEach(() => {
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: vi.fn() } });
  });

  it('associates the disabled Start reason and clears consent when type changes', async () => {
    const user = userEvent.setup();
    renderFeature(<RecordAppointmentScreen />, routePaths.recordAppointment);
    const start = screen.getByRole('button', { name: 'Start recording' });
    const checkbox = screen.getByRole('checkbox', { name: 'I have permission to record this appointment' });
    expect(start).toBeDisabled();
    expect(start).toHaveAttribute('aria-describedby', 'recording-consent-reason');
    expect(screen.getByText('Ask everyone in the room before recording. Start stays unavailable until you confirm.')).toHaveAttribute('id', 'recording-consent-reason');
    await user.click(checkbox);
    expect(start).toBeEnabled();
    await user.click(screen.getByRole('tab', { name: 'TMS' }));
    expect(checkbox).not.toBeChecked();
    expect(start).toBeDisabled();
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
  });

  it('starts only after consent and safely blocks rapid repeated activation', async () => {
    const user = userEvent.setup();
    renderConsentFlow();
    await user.click(screen.getByRole('checkbox', { name: 'I have permission to record this appointment' }));
    const start = screen.getByRole('button', { name: 'Start recording' });
    await user.dblClick(start);
    expect(screen.getByLabelText('Current path')).toHaveTextContent(routePaths.activeAppointment);
    expect(screen.getByText('Recording')).toBeVisible();
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
  });
});

describe('active appointment recording', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('blocks a direct deep link without requesting permission', () => {
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: vi.fn() } });
    renderFeature(<ActiveAppointmentScreen />, routePaths.activeAppointment);
    expect(screen.getByRole('heading', { name: 'Permission has not been confirmed' })).toBeVisible();
    expect(screen.getByText('No microphone request was made and no recording started.')).toBeVisible();
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
  });

  it('advances deterministically, clears the timer, and finishes once into saved state', () => {
    const clearIntervalSpy = vi.spyOn(window, 'clearInterval');
    const view = renderConsentFlow();
    fireEvent.click(screen.getByRole('checkbox', { name: 'I have permission to record this appointment' }));
    fireEvent.click(screen.getByRole('button', { name: 'Start recording' }));
    expect(screen.getByLabelText('Appointment recording duration')).toHaveTextContent('18:24');
    act(() => vi.advanceTimersByTime(2_000));
    expect(screen.getByLabelText('Appointment recording duration')).toHaveTextContent('18:26');
    const finish = screen.getByRole('button', { name: 'Finish' });
    fireEvent.click(finish);
    fireEvent.click(finish);
    expect(screen.getByRole('heading', { name: 'Saved on this device' })).toBeVisible();
    expect(screen.getByRole('link', { name: 'Open session detail' })).toHaveAttribute('href', routePaths.therapySession);
    expect(clearIntervalSpy).toHaveBeenCalled();
    view.unmount();
  });
});

describe('therapy session detail', () => {
  it('supports every detail tab with shared keyboard semantics', () => {
    renderFeature(<TherapySessionScreen />, routePaths.therapySession);
    const transcript = screen.getByRole('tab', { name: 'Transcript' });
    expect(transcript).toHaveAttribute('aria-selected', 'true');
    fireEvent.keyDown(transcript, { key: 'ArrowRight' });
    expect(screen.getByRole('tab', { name: 'Homework' })).toHaveAttribute('aria-selected', 'true');
    fireEvent.click(screen.getByRole('tab', { name: 'Homework' }));
    expect(screen.getAllByText('Therapy, Sep 2 at 42:18')).toHaveLength(2);
    fireEvent.click(screen.getByRole('tab', { name: 'Talking points' }));
    expect(screen.getByText('Candy Corn suggested this')).toBeVisible();
    expect(screen.getByLabelText('Simulated transcript playback')).toBeVisible();
  });

  it('uses a summary timestamp to open and focus the original segment', () => {
    renderFeature(<TherapySessionScreen />, routePaths.therapySession);
    fireEvent.click(screen.getByRole('tab', { name: 'Summary' }));
    fireEvent.click(screen.getByRole('button', { name: 'You said this at 12:24' }));
    expect(screen.getByRole('tab', { name: 'Transcript' })).toHaveAttribute('aria-selected', 'true');
    expect(document.activeElement).toHaveAttribute('id', 'therapy-sep-2-1');
    expect(screen.getByText('I do not think I miss playing as much as I miss having the chance to prove I could have done it.')).toBeVisible();
  });

  it('corrects only unknown attribution while preserving transcript text', () => {
    renderFeature(<TherapySessionScreen />, routePaths.therapySession);
    const original = 'Let us make sure we come back to the meeting with the coaches.';
    expect(screen.getByText(original)).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: 'Mark as provider' }));
    expect(screen.getAllByText('Dr. Elena Park')).toHaveLength(2);
    expect(screen.getByText(original)).toBeVisible();
    expect(screen.queryByRole('button', { name: 'Mark as provider' })).not.toBeInTheDocument();
  });
});

describe('TMS check-ins', () => {
  it('saves pre-session capture to preparation and states the treatment boundary', async () => {
    const user = userEvent.setup();
    renderFeature(<TmsPreSessionScreen />, routePaths.tmsPre);
    expect(screen.getByText('Candy Corn does not create treatment provocations. It only organizes what you and your provider supply.')).toBeVisible();
    await user.click(screen.getByRole('button', { name: 'Add this to tell the provider' }));
    expect(screen.getByRole('button', { name: 'Added for the provider' })).toBeDisabled();
    await user.click(screen.getByRole('button', { name: 'Save pre-session check-in' }));
    expect(screen.getByLabelText('Current path')).toHaveTextContent(routePaths.prepareTms);
  });

  it('saves post-session observations locally without a causal claim', async () => {
    const user = userEvent.setup();
    renderFeature(<TmsPostSessionScreen />, routePaths.tmsPost);
    expect(screen.getByText('This check-in records timing and context. It does not claim that TMS caused a mood or symptom change.')).toBeVisible();
    await user.click(screen.getByRole('button', { name: 'Save post-session check-in' }));
    expect(screen.getByRole('heading', { name: 'Post-session check-in saved' })).toBeVisible();
    expect(screen.getByRole('link', { name: 'Open History' })).toHaveAttribute('href', routePaths.history);
    expect(screen.getByRole('link', { name: 'Prepare for TMS' })).toHaveAttribute('href', routePaths.prepareTms);
  });
});
