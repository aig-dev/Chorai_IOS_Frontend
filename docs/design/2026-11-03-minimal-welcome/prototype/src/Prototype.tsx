import { createContext, useCallback, useContext, useEffect, useRef, useState, type CSSProperties, type FocusEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { MotionConfig, useIsPresent } from "motion/react";
import { ArrowLeftIcon, Cross2Icon, LockClosedIcon, MixerHorizontalIcon, MoonIcon, PersonIcon, ReloadIcon, SpeakerLoudIcon, SpeakerOffIcon, SunIcon } from "@radix-ui/react-icons";
import { FlowStack, KeyboardInput, MobileScroll, useKeyboard, useMobileDevice, type FlowControls, type FlowScreen } from "./mobile";

const assets = "/chorai-assets/";
const SEGMENTS = [{ text: "cho", at: 120 }, { text: "ra", at: 420 }, { text: "i", at: 720 }];
const END = 1660;
type MotionState = "playing" | "settled" | "reduced";
type Review = {
  elapsed: number; state: MotionState; audioState: string; theme: "light" | "dark";
  reduced: boolean; systemReduced: boolean; manualReduced: boolean;
  play: (sound: boolean) => void; stop: () => void;
  setTheme: (theme: "light" | "dark") => void; setManualReduced: (value: boolean) => void;
};
const ReviewContext = createContext<Review | null>(null);
function useReview() { const value = useContext(ReviewContext); if (!value) throw new Error("Missing review context"); return value; }
function useSystemReducedMotion() {
  const [value, setValue] = useState(() => matchMedia("(prefers-reduced-motion: reduce)").matches);
  useEffect(() => { const query = matchMedia("(prefers-reduced-motion: reduce)"); const change = () => setValue(query.matches); query.addEventListener("change", change); return () => query.removeEventListener("change", change); }, []);
  return value;
}
function reveal(elapsed: number, at: number, duration: number, reduced: boolean): CSSProperties {
  const t = reduced ? 1 : Math.max(0, Math.min(1, (elapsed - at) / duration));
  const progress = 1 - Math.pow(1 - t, 4);
  return { opacity: progress, transform: `translateY(${(1 - progress) * 16}px) scale(${0.97 + progress * 0.03})` };
}

export default function Prototype() {
  const systemReduced = useSystemReducedMotion();
  const [manualReduced, setManualReduced] = useState(false);
  const reduced = systemReduced || manualReduced;
  const [theme, setTheme] = useState<"light" | "dark">("light");
  const [elapsed, setElapsed] = useState(reduced ? END : 0);
  const [state, setState] = useState<MotionState>(reduced ? "reduced" : "playing");
  const [audioState, setAudioState] = useState("silent");
  const frame = useRef(0);
  const generation = useRef(0);
  const context = useRef<AudioContext | null>(null);
  const buffer = useRef<AudioBuffer | null>(null);
  const sound = useRef<AudioBufferSourceNode | null>(null);

  const cancel = useCallback(() => {
    generation.current += 1;
    cancelAnimationFrame(frame.current);
    if (sound.current) { try { sound.current.stop(); } catch { /* already stopped */ } sound.current.disconnect(); sound.current = null; }
  }, []);
  const stop = useCallback(() => { cancel(); setElapsed(END); setState(reduced ? "reduced" : "settled"); setAudioState("silent"); }, [cancel, reduced]);
  const play = useCallback(async (withSound: boolean) => {
    cancel();
    const id = generation.current;
    if (reduced) { setElapsed(END); setState("reduced"); setAudioState("reduced-motion"); return; }
    let audioClock: AudioContext | null = null;
    let audioStart = 0;
    setAudioState(withSound ? "preparing" : "silent");
    if (withSound) {
      try {
        const ctx = context.current ?? (context.current = new AudioContext());
        await ctx.resume();
        if (!buffer.current) {
          const response = await fetch(assets + "welcome-beats.wav");
          if (!response.ok) throw new Error("Sound unavailable");
          buffer.current = await ctx.decodeAudioData(await response.arrayBuffer());
        }
        if (generation.current !== id) return;
        if (document.hidden) {
          cancel(); setElapsed(END); setState("settled"); setAudioState("silent"); return;
        }
        const source = ctx.createBufferSource(); source.buffer = buffer.current; source.connect(ctx.destination);
        audioStart = ctx.currentTime + 0.06; source.start(audioStart); sound.current = source; audioClock = ctx;
        setAudioState("playing");
      } catch { if (generation.current !== id) return; setAudioState("unavailable"); }
    }
    if (generation.current !== id) return;
    if (document.hidden) {
      cancel(); setElapsed(END); setState("settled"); setAudioState("silent"); return;
    }
    const visualStart = performance.now() + (audioClock ? 60 : 40);
    setElapsed(0); setState("playing");
    const tick = () => {
      if (generation.current !== id) return;
      const next = Math.max(0, audioClock ? (audioClock.currentTime - audioStart) * 1000 : performance.now() - visualStart);
      setElapsed(Math.min(next, END));
      if (next < END) frame.current = requestAnimationFrame(tick);
      else { setState("settled"); if (sound.current) { try { sound.current.stop(); } catch { /* ended */ } sound.current.disconnect(); sound.current = null; } setAudioState(current => current === "unavailable" ? current : "silent"); }
    };
    frame.current = requestAnimationFrame(tick);
  }, [cancel, reduced]);

  const initialPlay = useRef(play);
  const lastReduced = useRef(reduced);
  useEffect(() => { void initialPlay.current(false); return cancel; }, [cancel]);
  useEffect(() => {
    if (lastReduced.current === reduced) return;
    lastReduced.current = reduced;
    stop();
  }, [reduced, stop]);
  useEffect(() => {
    const hide = () => { if (document.hidden) stop(); };
    document.addEventListener("visibilitychange", hide);
    return () => document.removeEventListener("visibilitychange", hide);
  }, [stop]);
  useEffect(() => () => { cancel(); void context.current?.close(); }, [cancel]);
  const value: Review = { elapsed, state, audioState, theme, reduced, systemReduced, manualReduced, play, stop, setTheme, setManualReduced };
  return <ReviewContext.Provider value={value}><div className="minimal-app" data-theme={theme} data-reduced-motion={reduced} data-testid="minimal-app"><MotionConfig reducedMotion={reduced ? "always" : "never"}><FlowStack initial={welcomeScreen} /></MotionConfig></div></ReviewContext.Provider>;
}

function Scene({ flow, name, children }: { flow: FlowControls; name: string; children: ReactNode }) {
  const isPresent = useIsPresent();
  const current = flow.current.id === name && isPresent;
  return <><div className="minimal-scene" aria-hidden={!current} inert={!current} data-screen={name}>{children}</div>{current && <ReviewTools flow={flow} />}</>;
}
function Welcome({ flow }: { flow: FlowControls }) {
  const review = useReview();
  const { device } = useMobileDevice();
  useEffect(() => { if (flow.current.id !== "welcome") review.stop(); }, [flow.current.id]);
  return <Scene flow={flow} name="welcome"><MobileScroll className="welcome-scroll"><main className="welcome-content" style={{ "--welcome-height": `${device.geometry.screen.height}px` } as CSSProperties} data-testid="welcome-screen" data-motion-state={review.state} data-audio-state={review.audioState}>
    <div className="welcome-hero">
      <h1 className="welcome-wordmark" aria-label="chorai" data-testid="welcome-title">{SEGMENTS.map(segment => <span key={segment.text} aria-hidden="true" style={reveal(review.elapsed, segment.at, 250, review.reduced)}>{segment.text}</span>)}</h1>
      <img className="welcome-chora" src={assets + "chora.png"} alt="Chora" width="144" height="144" draggable="false" style={reveal(review.elapsed, 1080, 460, review.reduced)} data-testid="welcome-chora" />
    </div>
  </main></MobileScroll></Scene>;
}
function WelcomeActions({ flow }: { flow: FlowControls }) {
  const review = useReview();
  const navigate = (destination: FlowScreen) => { review.stop(); flow.push(destination); };
  return <div className="welcome-actions"><button className="primary-action" onClick={() => navigate(signInScreen)} data-testid="welcome-login">Login</button><button className="beta-action" onClick={() => navigate(betaScreen)} data-testid="welcome-beta">Join Private Beta</button></div>;
}
function Header({ flow, title }: { flow: FlowControls; title: string }) {
  return <div className="auth-nav"><button className="back-action" aria-label="Back" onClick={flow.pop}><ArrowLeftIcon width={22} height={22} /></button><span>{title}</span><div className="nav-balance" /></div>;
}
function AuthForm({ flow, beta = false }: { flow: FlowControls; beta?: boolean }) {
  const keyboard = useKeyboard();
  const [email, setEmail] = useState(""); const [password, setPassword] = useState(""); const [code, setCode] = useState(""); const [notice, setNotice] = useState("");
  const blur = (event: FocusEvent<HTMLInputElement>) => { if (!(event.relatedTarget instanceof HTMLInputElement)) keyboard.hide(); };
  const showNotice = (method: string) => { keyboard.hide(); setNotice(`${method} is not connected in this design preview. No information was sent.`); };
  return <Scene flow={flow} name={beta ? "beta" : "signin"}><MobileScroll className="auth-scroll"><main className="auth-content" data-testid={beta ? "beta-screen" : "signin-screen"}>
    <h1>{beta ? "Join Private Beta" : "Welcome back."}</h1>
    <p className="auth-intro">{beta ? "Enter your product access code." : "Sign in to continue to Chorai."}</p>
    <form onSubmit={event => { event.preventDefault(); showNotice(beta ? "Access code verification" : "Email sign-in"); }}>
      <div className="auth-fields">{beta ? <label className="field-row"><LockClosedIcon aria-hidden="true" /><KeyboardInput aria-label="Product access code" placeholder="Product access code" value={code} onChange={event => setCode(event.target.value)} onBlur={blur} autoComplete="off" /></label> : <><label className="field-row"><PersonIcon aria-hidden="true" /><KeyboardInput aria-label="Email" type="email" inputMode="email" placeholder="Email" value={email} onChange={event => setEmail(event.target.value)} onBlur={blur} autoComplete="off" /></label><label className="field-row"><LockClosedIcon aria-hidden="true" /><KeyboardInput aria-label="Password" type="password" placeholder="Password" value={password} onChange={event => setPassword(event.target.value)} onBlur={blur} autoComplete="off" /></label></>}</div>
      <button className="primary-action" type="submit">{beta ? "Continue" : "Sign In"}</button>
    </form>
    {!beta && <><div className="auth-divider"><span />Or sign in with<span /></div><div className="providers"><button onClick={() => showNotice("Google sign-in")}>Google</button><button onClick={() => showNotice("Apple sign-in")}>Apple</button></div></>}
    <p className="preview-note">Design preview · no account activity</p>
    {notice && <p className="auth-notice" role="status">{notice}</p>}
  </main></MobileScroll></Scene>;
}
const welcomeScreen: FlowScreen = { id: "welcome", footerHeight: 170, footer: flow => <WelcomeActions flow={flow} />, render: flow => <Welcome flow={flow} /> };
const signInScreen: FlowScreen = { id: "signin", headerHeight: 52, header: flow => <Header flow={flow} title="Sign In" />, render: flow => <AuthForm flow={flow} /> };
const betaScreen: FlowScreen = { id: "beta", headerHeight: 52, header: flow => <Header flow={flow} title="Private Beta" />, render: flow => <AuthForm flow={flow} beta /> };

function ReviewTools({ flow }: { flow: FlowControls }) {
  const review = useReview();
  const [open, setOpen] = useState(() => window.innerWidth >= 1080);
  const replay = (sound: boolean) => { if (flow.canGoBack) flow.pop(); review.play(sound); if (window.innerWidth < 1080) setOpen(false); };
  return createPortal(<aside className={`review-tools ${open ? "is-open" : ""}`} aria-label="Motion review controls" data-testid="review-controls" data-audio-state={review.audioState}>
    <button className="review-toggle" aria-expanded={open} onClick={() => setOpen(!open)}><MixerHorizontalIcon />播放与外观{open && <Cross2Icon />}</button>
    {open && <div className="review-panel"><p className="review-label">CHORAI · MOTION STUDY</p><h2>标题，然后 Chora。</h2><p className="review-description">约 1.6 秒，播完停稳。</p>
      <div className="replay-buttons"><button className="sound-replay" onClick={() => replay(true)} disabled={review.reduced}><SpeakerLoudIcon />有声重播</button><button onClick={() => replay(false)}><ReloadIcon />静音重播</button></div>
      <div className="theme-buttons" role="group" aria-label="Appearance"><button aria-pressed={review.theme === "light"} onClick={() => review.setTheme("light")}><SunIcon />浅色</button><button aria-pressed={review.theme === "dark"} onClick={() => review.setTheme("dark")}><MoonIcon />深色</button></div>
      <button className="reduce-toggle" role="switch" aria-checked={review.reduced} aria-label="减少开场与转场" disabled={review.systemReduced} onClick={() => review.setManualReduced(!review.manualReduced)}><span>减少开场与转场</span><span className="switch-indicator" /></button>
      <p className="review-status" role="status">{review.reduced ? "已显示静态末帧" : review.audioState === "playing" ? "音效播放中" : review.audioState === "preparing" ? "正在准备音效" : review.audioState === "unavailable" ? "音效未能播放，当前为静音预览" : review.state === "playing" ? "静音播放中" : "已停稳"}</p>
      <p className="review-footnote"><SpeakerOffIcon />首次静音。浏览器不模拟 iPhone 触感。</p>
    </div>}
  </aside>, document.body);
}
