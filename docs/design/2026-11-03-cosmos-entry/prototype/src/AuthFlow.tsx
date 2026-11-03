import { createContext, useCallback, useContext, useEffect, useRef, useState, type FocusEvent, type ReactNode } from 'react';
import { MotionConfig, motion, useIsPresent } from 'motion/react';
import { ArrowLeftIcon, CheckIcon, PlusIcon, EyeClosedIcon, EyeOpenIcon, ReloadIcon } from '@radix-ui/react-icons';
import { BottomSheet, FlowStack, KeyboardInput, MobileScroll, useKeyboard, useKeyboardInsets, type FlowControls, type FlowScreen } from './mobile';
import './auth.css';

export type AuthScenario = 'success' | 'rejected' | 'offline' | 'access-required';
type Step = 'signin' | 'access' | 'email' | 'code' | 'username' | 'password' | 'confirm' | 'interests' | 'complete';
type Fields = { access: string; email: string; code: string; username: string; password: string; confirm: string };
type Mode = 'signin' | 'signup';
type Sheet = 'terms' | 'privacy' | 'Google' | 'Apple' | null;
type AuthProps = { initialMode: Mode; reduced: boolean; scenario: AuthScenario; onExit: () => void };
type Model = {
  fields: Fields; update: (field: keyof Fields, value: string) => void; busy: boolean; error: string; canAutofocus: boolean;
  mode: Mode; reduced: boolean; remaining: number; selections: string[]; pendingAccess: boolean;
  setSelections: (value: string[]) => void; submit: (flow: FlowControls, step: Step) => void;
  back: (flow: FlowControls) => void; changeMode: (flow: FlowControls, mode: Mode) => void;
  resend: () => void; openSheet: (sheet: Sheet, flow: FlowControls) => void;
  recoverCode: (flow: FlowControls) => void; canSubmit: (step: Step) => boolean; go: (flow: FlowControls, step: Step) => void; cancelPending: () => void;
};
const AuthContext = createContext<Model | null>(null);
function useAuth() { const value = useContext(AuthContext); if (!value) throw new Error('Auth context missing'); return value; }
const empty: Fields = { access: '', email: '', code: '', username: '', password: '', confirm: '' };
const emailValid = (value: string) => /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(value);
// Swift CharacterSet.letters accepts letters and combining marks; decimalDigits is Nd.
const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const passwordValid = (value: string) => [...graphemes.segment(value)].length >= 8 && /[\p{L}\p{M}]/u.test(value) && /\p{Nd}/u.test(value);
// Illustrative preview data, not a claim about the live server taxonomy. Art,
// Technology and Culture also occur in the native InterestSelectionStore tests.
const interests = ['Art', 'Technology', 'Culture', 'Design', 'Science', 'Literature', 'Philosophy', 'Music', 'Architecture', 'Psychology', 'Nature', 'History'];
const titles: Record<Step, string> = { signin: 'Welcome back', access: 'Your invitation to Chorai', email: 'Enter your email address', code: 'Check your inbox', username: 'What should we call you?', password: 'Create your password', confirm: 'Confirm your password', interests: 'Follow your curiosity', complete: 'Flow complete' };
const order: Step[] = ['access', 'email', 'code', 'username', 'password', 'confirm'];

export function AuthFlow({ initialMode, reduced, scenario, onExit }: AuthProps) {
  const keyboard = useKeyboard();
  const [fields, setFields] = useState<Fields>(empty);
  const [mode, setMode] = useState<Mode>(initialMode);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [pendingAccess, setPendingAccess] = useState(false);
  const [accessPassed, setAccessPassed] = useState(false);
  const [hasProductAccess, setHasProductAccess] = useState(false);
  const [selections, setSelections] = useState<string[]>([]);
  const [sentEmail, setSentEmail] = useState('');
  const [deadline, setDeadline] = useState(0);
  const [now, setNow] = useState(Date.now());
  const [sheet, setSheet] = useState<Sheet>(null);
  const sheetFlow = useRef<FlowControls | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const operation = useRef(0);
  const alive = useRef(true);
  const scenarioRef = useRef(scenario);
  scenarioRef.current = scenario;
  const cancelPending = useCallback(() => { operation.current++; if (timer.current) clearTimeout(timer.current); timer.current = null; setBusy(false); }, []);
  useEffect(() => { alive.current = true; return () => { alive.current = false; operation.current++; if (timer.current) clearTimeout(timer.current); }; }, []);
  useEffect(() => { cancelPending(); setError(''); }, [scenario, cancelPending]);
  useEffect(() => { if (!deadline) return; const interval = setInterval(() => setNow(Date.now()), 500); return () => clearInterval(interval); }, [deadline]);
  const remaining = Math.max(0, Math.ceil((deadline - now) / 1000));

  const update = (field: keyof Fields, value: string) => {
    setFields(current => ({ ...current, [field]: value, ...(field === 'email' && value !== current.email ? { code: '' } : {}) }));
    setError('');
    if (field === 'email' && value !== fields.email) { setSentEmail(''); setDeadline(0); }
    if (field === 'access' && value !== fields.access) setAccessPassed(false);
  };
  const go = (flow: FlowControls, step: Step) => { cancelPending(); setError(''); keyboard.hide(); flow.push(screen(step)); };
  const back = (flow: FlowControls) => { cancelPending(); setError(''); keyboard.hide(); if (flow.canGoBack) flow.pop(); else onExit(); };
  const changeMode = (flow: FlowControls, next: Mode) => { cancelPending(); setError(''); setMode(next); setPendingAccess(false); keyboard.hide(); flow.push(screen(next === 'signin' ? 'signin' : 'access')); };
  const perform = (rejection: string, done: () => void) => {
    if (busy) return;
    keyboard.hide(); cancelPending(); const id = operation.current; setBusy(true); setError('');
    timer.current = setTimeout(() => {
      if (!alive.current || id !== operation.current) return;
      timer.current = null; setBusy(false);
      if (scenarioRef.current === 'offline') { setError('Connection unavailable. Try again when you’re back online.'); return; }
      if (scenarioRef.current === 'rejected') { setError(rejection); return; }
      done();
    }, reduced ? 360 : 720);
  };
  const canSubmit = (step: Step) => {
    if (busy) return false;
    switch (step) {
      case 'signin': return emailValid(fields.email) && fields.password.length > 0;
      case 'access': return fields.access.trim().length >= 9 && fields.access.trim().length <= 64;
      case 'email': return emailValid(fields.email);
      case 'code': return fields.code.length === 6 && sentEmail === fields.email;
      case 'username': return fields.username.trim().length >= 2;
      case 'password': return passwordValid(fields.password);
      case 'confirm': return fields.confirm.length > 0;
      case 'interests': return selections.length > 0 && selections.length <= 9;
      case 'complete': return true;
    }
  };
  const startResend = (done?: () => void) => perform('Too many code requests. Please wait a moment and try again.', () => { setSentEmail(fields.email); setNow(Date.now()); setDeadline(Date.now() + 60000); done?.(); });
  const finishAuth = (flow: FlowControls, authMode: Mode = mode) => {
    setMode(authMode);
    if (scenarioRef.current === 'access-required' && !hasProductAccess) { setPendingAccess(true); go(flow, 'access'); }
    else go(flow, authMode === 'signup' ? 'interests' : 'complete');
  };
  const submit = (flow: FlowControls, step: Step) => {
    if (busy) return;
    if (!canSubmit(step)) { setError(step === 'email' ? 'Enter a valid email address.' : step === 'password' ? 'Use at least 8 characters with a letter and a number.' : step === 'access' ? 'Enter a valid Product Access Code.' : step === 'code' ? 'Enter the six-character code from your email.' : 'Complete this field to continue.'); return; }
    if (step === 'signin') { perform('Email or password is incorrect. Please try again.', () => finishAuth(flow, 'signin')); return; }
    if (step === 'access') { perform('This Product Access Code is invalid or no longer available.', () => { setAccessPassed(true); if (pendingAccess) setHasProductAccess(true); else setMode('signup'); go(flow, pendingAccess ? (mode === 'signup' ? 'interests' : 'complete') : 'email'); }); return; }
    if (step === 'email') { if (sentEmail === fields.email) go(flow, 'code'); else startResend(() => go(flow, 'code')); return; }
    if (step === 'code') { go(flow, 'username'); return; } // Format only. Server validates on final register.
    if (step === 'username') { go(flow, 'password'); return; }
    if (step === 'password') { go(flow, 'confirm'); return; }
    if (step === 'confirm') {
      if (!emailValid(fields.email) || fields.username.trim().length < 2 || !passwordValid(fields.password)) { setError('Check your account details before creating your account.'); return; }
      if (fields.password !== fields.confirm) { setError('Your passwords don’t match. Try again.'); return; }
      if (!accessPassed) { setError('Confirm your Product Access Code before creating an account.'); return; }
      if (sentEmail !== fields.email || fields.code.length !== 6) { setError('Request a code for this email before creating your account.'); return; }
      perform('This code is incorrect or expired. Go back to request a new code.', () => finishAuth(flow)); return;
    }
    if (step === 'interests') { perform('We couldn’t save your interests. Try again, or skip this step.', () => go(flow, 'complete')); return; }
    keyboard.hide(); onExit();
  };
  const openSheet = (next: Sheet, flow: FlowControls) => { keyboard.hide(); sheetFlow.current = flow; setSheet(next); };
  const closeSheet = () => {
    keyboard.hide();
    const focused = document.activeElement;
    if (focused instanceof HTMLElement && focused.closest('.auth-sheet-copy')) focused.blur();
    setSheet(null);
  };
  const providerContinue = () => {
    const flow = sheetFlow.current;
    closeSheet();
    if (!flow) return;
    const providerMode: Mode = flow.current.id === 'auth-signin' ? 'signin' : 'signup';
    if (providerMode === 'signup' && !accessPassed) { setError('Confirm your Product Access Code first.'); return; }
    perform('This sign-in could not be verified. Please try again.', () => finishAuth(flow, providerMode));
  };
  const recoverCode = (flow: FlowControls) => {
    cancelPending(); setError(''); setFields(current => ({ ...current, code: '' })); keyboard.hide();
    const index = flow.stack.map(entry => entry.id).lastIndexOf('auth-code');
    if (index >= 0) { for (let i = flow.stack.length - 1; i > index; i--) flow.pop(); }
    else flow.replace(screen('code'));
  };
  const model: Model = { fields, update, busy, error, canAutofocus: sheet === null && !busy, mode, reduced, remaining, selections, pendingAccess, setSelections, submit, back, changeMode, resend: () => { if (remaining === 0 && emailValid(fields.email)) startResend(); }, openSheet, recoverCode, canSubmit, go, cancelPending };
  return <AuthContext.Provider value={model}><div className="cosmos-auth" data-reduced-motion={reduced} data-testid="cosmos-auth"><MotionConfig reducedMotion={reduced ? 'always' : 'never'}><FlowStack initial={screen(initialMode === 'signin' ? 'signin' : 'access')} /><BottomSheet open={sheet !== null} onOpenChange={open => { if (!open) closeSheet(); }} title={sheet === 'terms' ? 'User Agreement' : sheet === 'privacy' ? 'Privacy Policy' : `${sheet ?? ''} sign-in preview`} snap={0.45}><div className="auth-sheet-copy">{sheet === 'terms' || sheet === 'privacy' ? <><p>This is a design preview, not the legal document.</p><p>The app opens Chorai’s existing {sheet === 'terms' ? 'User Agreement' : 'Privacy Policy'} here. This preview does not accept terms or create an account.</p><button className="auth-primary" onClick={closeSheet}>Done</button></> : <><p>The app opens {sheet} to authorize your account. No provider is contacted in this preview.</p><button className="auth-primary" onClick={providerContinue}>Preview the next step</button><button className="auth-text-button" onClick={closeSheet}>Cancel</button></>}</div></BottomSheet></MotionConfig></div></AuthContext.Provider>;
}

function screen(step: Step): FlowScreen {
  const render: FlowScreen['render'] = flow => <AuthScreen flow={flow} step={step} owner={render} />;
  return { id: `auth-${step}`, headerHeight: 52, footerHeight: step === 'confirm' ? 126 : step === 'interests' ? 128 : 84, header: flow => <AuthHeader flow={flow} step={step} />, footer: flow => <AuthFooter flow={flow} step={step} />, render };
}
function AuthHeader({ flow, step }: { flow: FlowControls; step: Step }) {
  const a = useAuth();
  const index = order.indexOf(step);
  return <div className="auth-header"><button aria-label="Back" className="auth-back" onClick={() => a.back(flow)}><ArrowLeftIcon width={20} height={20}/></button>{index >= 0 && !a.pendingAccess ? <div className="auth-progress" role="progressbar" aria-label="Account setup progress" aria-valuemin={0} aria-valuemax={6} aria-valuenow={index + 1}><span style={{width:`${(index + 1) / 6 * 100}%`}} /></div> : <span className="auth-header-brand">chorai</span>}{step === 'signin' ? <button className="auth-header-link" onClick={() => a.changeMode(flow, 'signup')}>Sign Up</button> : step === 'access' && !a.pendingAccess ? <button className="auth-header-link" onClick={() => a.changeMode(flow, 'signin')}>Log In</button> : step === 'interests' ? <button className="auth-header-link" disabled={a.busy} onClick={() => a.go(flow, 'complete')}>Skip</button> : <span className="auth-header-space" />}</div>;
}
function AuthFooter({ flow, step }: { flow: FlowControls; step: Step }) {
  const a = useAuth();
  const label = step === 'signin' ? 'Sign in' : step === 'confirm' ? 'Create account' : step === 'complete' ? 'Back to preview' : step === 'interests' ? 'Continue' : 'Continue';
  return <div className="auth-footer">{step === 'interests' && <div className="auth-selection-summary"><button onClick={() => a.setSelections([])} disabled={a.busy || !a.selections.length}>Reset</button><span>{a.selections.length ? `${a.selections.length} selected` : 'Choose up to 9'}</span></div>}<button className="auth-primary" disabled={!a.canSubmit(step)} onClick={() => a.submit(flow, step)} data-testid={`auth-${step}-continue`}>{a.busy ? <><ReloadIcon className="auth-spinner" aria-hidden="true"/><span className="auth-sr-only">Working…</span></> : label}</button>{step === 'confirm' && <p className="auth-legal">By continuing, you agree to our <button onClick={() => a.openSheet('terms', flow)}>User Agreement</button> and acknowledge our <button onClick={() => a.openSheet('privacy', flow)}>Privacy Policy</button>.</p>}</div>;
}
function AuthScreen({ flow, step, owner }: { flow: FlowControls; step: Step; owner: FlowScreen['render'] }) {
  const a = useAuth();
  const present = useIsPresent();
  const current = present && flow.current.render === owner;
  const { isKeyboardVisible } = useKeyboardInsets();
  useEffect(() => { if (!current) a.cancelPending(); }, [current]);
  let subtitle: ReactNode = step === 'signin' ? 'Enter your email and password' : step === 'access' ? (a.pendingAccess ? 'Your account needs Private Beta access.' : 'Enter your Product Access Code to get started.') : step === 'email' ? 'A place for your ideas starts here.' : step === 'code' ? <>Enter the code sent to <strong>{a.fields.email}</strong></> : step === 'username' ? 'Choose a username for your account.' : step === 'password' ? 'At least 8 characters, with a letter and a number.' : step === 'confirm' ? 'One more time, then you’re ready.' : step === 'interests' ? 'Choose up to 9 starting points. You can skip this.' : 'Explore opens here in the app.';
  return <div className="auth-scene" inert={!current} aria-hidden={!current} data-screen={step} data-keyboard-open={isKeyboardVisible}><MobileScroll className="auth-scroll"><motion.main className={`auth-body auth-body-${step}`} initial={{opacity:0,y:a.reduced ? 0 : 8}} animate={{opacity:1,y:0}} transition={{duration:a.reduced ? 0 : .26}}><div className="auth-heading"><h1>{titles[step]}</h1><p>{subtitle}</p></div>
    {step === 'signin' ? <><form noValidate className="auth-signin-fields" onSubmit={e => { e.preventDefault(); a.submit(flow, step); }}><Field name="email" label="Email" active={current} large={false}/><Field name="password" label="Password" active={false} large={false}/><button type="submit" hidden aria-hidden="true" tabIndex={-1}>Sign in</button></form><ProviderButtons flow={flow}/></> : step === 'interests' ? <div className="auth-interests" aria-label="Interests">{interests.map(value => { const selected = a.selections.includes(value); return <button key={value} aria-pressed={selected} disabled={a.busy || (!selected && a.selections.length >= 9)} onClick={() => a.setSelections(selected ? a.selections.filter(x=>x!==value) : [...a.selections,value])}><span>{value}</span>{selected ? <CheckIcon width={16} height={16} aria-hidden="true"/> : <PlusIcon width={16} height={16} aria-hidden="true"/>}</button>; })}</div> : step === 'complete' ? <div className="auth-checkpoint"><img src="/chorai-assets/chora.png" alt="Chora" draggable={false}/><p>Design preview · no account was created<br/>and no information was sent.</p></div> : <><form noValidate className="auth-single-field" onSubmit={e => { e.preventDefault(); a.submit(flow, step); }}><Field name={step} label={step === 'access' ? 'CRAI-XXXX' : step === 'email' ? 'Email address' : step === 'code' ? 'Email code' : step === 'username' ? 'Username' : step === 'password' ? 'Password' : 'Confirm password'} active={current} large/><button hidden aria-hidden="true" type="submit" tabIndex={-1}>Continue</button></form>{step === 'code' && <div className="auth-code-tools"><button onClick={a.resend} disabled={a.busy || a.remaining > 0}>{a.remaining > 0 ? `Resend code in ${a.remaining}s` : 'Resend code'}</button><button onClick={() => a.back(flow)}>Change email</button><p>Your code is checked when your account is created.</p></div>}{step === 'email' && <ProviderButtons flow={flow}/>}</>}
    {a.error && current && <div className="auth-error"><p role="alert">{a.error}</p>{step === 'confirm' && a.error.includes('code is incorrect') && <button className="auth-recovery" onClick={() => a.recoverCode(flow)}>Back to email code</button>}</div>}
  </motion.main></MobileScroll></div>;
}
function ProviderButtons({ flow }: { flow: FlowControls }) {
  const a = useAuth();
  return <div className="auth-providers"><span>or continue with</span><div><button disabled={a.busy} onClick={() => a.openSheet('Google', flow)}>Google</button><button disabled={a.busy} onClick={() => a.openSheet('Apple', flow)}>Apple</button></div></div>;
}
function Field({name,label,active,large}:{name:keyof Fields;label:string;active:boolean;large:boolean}) {
  const a = useAuth();
  const keyboard = useKeyboard();
  const input = useRef<HTMLInputElement>(null);
  const [visible,setVisible] = useState(false);
  const secure = name === 'password' || name === 'confirm';
  const focusAllowed = active && a.canAutofocus;
  const focusAllowedRef = useRef(focusAllowed);
  focusAllowedRef.current = focusAllowed;
  useEffect(() => {
    if (!focusAllowed) return;
    const focus = setTimeout(() => {
      const field = input.current;
      // A portal sheet may still be exiting. Never compete with its focus trap,
      // a parked route, or a pending response for focus behind the overlay.
      if (!focusAllowedRef.current || !field?.isConnected || field.disabled || field.closest('[inert], [aria-hidden="true"]')) return;
      field.focus({ preventScroll: true });
    }, a.reduced ? 30 : 360);
    return () => clearTimeout(focus);
  }, [focusAllowed,a.reduced]);
  const blur = (event:FocusEvent<HTMLInputElement>) => { if (!(event.relatedTarget instanceof HTMLInputElement)) keyboard.hide(); };
  return <label className={`auth-field ${large ? 'auth-field-large' : 'auth-field-outlined'}`}><span className="auth-sr-only">{label}</span><KeyboardInput ref={input} aria-label={label} data-testid={`auth-field-${name}`} value={a.fields[name]} onChange={event=>a.update(name,event.target.value)} onBlur={blur} onKeyDown={event => { if (event.key === 'Enter' && !large && name === 'email') { event.preventDefault(); event.currentTarget.closest('form')?.querySelector<HTMLInputElement>('[data-testid="auth-field-password"]')?.focus({ preventScroll: true }); } }} disabled={a.busy} type={secure && !visible ? 'password' : name === 'email' ? 'email' : 'text'} inputMode={name === 'email' ? 'email' : 'text'} enterKeyHint="next" placeholder={label} maxLength={name === 'code' ? 6 : name === 'access' ? 64 : undefined} autoComplete="off" autoCapitalize="none" spellCheck={false}/>{secure && <button type="button" aria-label={visible ? 'Hide password' : 'Show password'} onPointerDown={event=>event.preventDefault()} onClick={()=>setVisible(!visible)}>{visible ? <EyeOpenIcon width={22} height={22}/> : <EyeClosedIcon width={22} height={22}/>}</button>}</label>;
}
