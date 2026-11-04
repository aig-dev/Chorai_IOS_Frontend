import { useEffect, useState, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, MotionConfig, motion } from "motion/react";
import { ArrowLeftIcon, MixerHorizontalIcon, Cross2Icon } from "@radix-ui/react-icons";
import { useKeyboard, useMobileDevice } from "./mobile";
import { AuthFlow } from "./AuthFlow";

type Scenario = "success" | "rejected" | "offline" | "access-required";
type Mode = "intro" | "signin" | "signup";
const A = "/chorai-assets/";
function useReducedPreference() {
  const [reduced, setReduced] = useState(() => matchMedia("(prefers-reduced-motion: reduce)").matches);
  useEffect(() => {
    const query = matchMedia("(prefers-reduced-motion: reduce)");
    const change = () => setReduced(query.matches);
    query.addEventListener("change", change);
    return () => query.removeEventListener("change", change);
  }, []);
  return reduced;
}
export default function Prototype() {
  const systemReduced = useReducedPreference();
  const [manualReduced, setManualReduced] = useState(false);
  const reduced = manualReduced || systemReduced;
  const [theme, setTheme] = useState<"light" | "dark">("light");
  const [scenario, setScenario] = useState<Scenario>("success");
  const [mode, setMode] = useState<Mode>("intro");
  const [splash, setSplash] = useState(!reduced);
  const [flowKey, setFlowKey] = useState(0);
  const [panel, setPanel] = useState(() => window.innerWidth >= 1100);
  const keyboard = useKeyboard();
  const {device} = useMobileDevice();
  useEffect(() => {
    if (!splash) return;
    if (reduced) { setSplash(false); return; }
    const timer = window.setTimeout(() => setSplash(false), 1050);
    return () => window.clearTimeout(timer);
  }, [splash, reduced, flowKey]);
  const open = (next: Mode, withSplash = false) => {
    keyboard.hide(); setFlowKey(key => key + 1);
    setMode(next); setSplash(withSplash && !reduced);
    if (window.innerWidth < 1100) setPanel(false);
  };
  return <MotionConfig reducedMotion={reduced ? "always" : "never"}>
    <div className="cosmos-entry" data-theme={theme} data-reduced={reduced} data-testid="cosmos-entry" style={{"--entry-safe-bottom": `${device.geometry.safeArea.bottom}px`, "--entry-safe-top": `${device.geometry.safeArea.top}px`} as CSSProperties}>
      <AnimatePresence mode="wait" initial={false}>
        {splash ? <motion.div className="brand-splash" key={`splash-${flowKey}`} initial={{opacity:1}} exit={{opacity:0}} transition={{duration:.18}} data-testid="brand-startup">
          <motion.img className="brand-mascot" src={A + "chora.png"} alt="Chora" initial={{opacity:0, scale:.84, y:8}} animate={{opacity:1, scale:1, y:0}} transition={{duration:.6, ease:[.22,1,.36,1]}} />
          <span className="splash-wordmark">chorai</span>
        </motion.div> : <motion.div className="entry-flow" key={`${mode}-${flowKey}`} initial={{opacity:0}} animate={{opacity:1}} exit={{opacity:0}} transition={{duration:reduced ? 0 : .2}}>
          {mode === "intro" ? <Introduction reduced={reduced} onLogin={() => open("signin")} onStart={() => open("signup")} /> : <AuthFlow initialMode={mode} reduced={reduced} scenario={scenario} onExit={() => open("intro")} />}
        </motion.div>}
      </AnimatePresence>
    </div>
    {createPortal(<aside className={`entry-review ${panel ? "expanded" : ""}`} aria-label="Flow review controls">
      <button className="review-trigger" onClick={() => setPanel(!panel)} aria-expanded={panel}><MixerHorizontalIcon />流程与演示{panel && <Cross2Icon />}</button>
      {panel && <div className="entry-review-body">
        <p className="review-kicker">CHORAI · COSMOS STUDY</p><h2>完整进入流程</h2><p className="review-explainer">页面、输入、键盘与转场。</p>
        <div className="review-route-buttons">
          <button onClick={() => open("intro", true)}>首次进入 · 重播</button><button onClick={() => open("signin", true)}>再次打开 · 短启动</button>
          <button onClick={() => open("signin")}>Sign In</button><button onClick={() => open("signup")}>Sign Up</button>
        </div>
        <fieldset className="review-scenarios"><legend>模拟服务结果</legend>{([['success','正常'],['rejected','拒绝 / 错误'],['offline','网络失败'],['access-required','需要访问码']] as [Scenario,string][]).map(([value,label]) => <button key={value} aria-pressed={scenario === value} onClick={() => setScenario(value)}>{label}</button>)}</fieldset>
        <div className="review-appearance"><button onClick={() => setTheme("light")} aria-pressed={theme === "light"}>浅色</button><button onClick={() => setTheme("dark")} aria-pressed={theme === "dark"}>深色</button></div>
        <button className="review-reduce" role="switch" aria-checked={reduced} disabled={systemReduced} onClick={() => setManualReduced(!manualReduced)}>减少开场与转场<span>{reduced ? "开启" : "关闭"}</span></button>
        <p className="review-disclaimer">离线交互样机。所有发送、登录和注册结果均为模拟，不创建账户。</p>
        <p className="review-disclaimer">请用虚构信息。示例：hello@example.com · Chora2026 · 123456 · CRAI-DEMO</p>
      </div>}
    </aside>, document.body)}
  </MotionConfig>;
}
const slides = [
  { title: <>Find ideas that<br/>stay with you.</>, label: "Explore" },
  { title: <>A place for your thoughts,<br/>and the things you find.</>, label: "Notes and collections" },
  { title: <>Let one idea<br/>lead to another.</>, label: "Spark" },
];
function Introduction({reduced,onLogin,onStart}:{reduced:boolean;onLogin:()=>void;onStart:()=>void}) {
  const [page,setPage] = useState(0); const [direction,setDirection] = useState(1); const [moving,setMoving] = useState(false);
  const next = () => { if (moving) return; if (page === 2) { onStart(); return; } setDirection(1); setMoving(true); setPage(page + 1); };
  const back = () => { if (!moving && page > 0) { setDirection(-1); setMoving(true); setPage(page - 1); } };
  useEffect(() => { if (!moving) return; const timer = setTimeout(() => setMoving(false), reduced ? 0 : 650); return () => clearTimeout(timer); }, [moving,reduced]);
  return <section className={`intro intro-${page}`} data-testid="introduction" aria-label={slides[page].label}>
    <header className="intro-nav">{page > 0 ? <button onClick={back} disabled={moving} aria-label="Previous introduction"><ArrowLeftIcon width={20} height={20} /></button> : <span/>}<button onClick={onLogin}>Log In</button></header>
    <div className="intro-title-region"><AnimatePresence mode="wait" initial={false}><motion.h1 key={page} initial={{opacity:0,y:reduced?0:7}} animate={{opacity:1,y:0}} exit={{opacity:0,y:reduced?0:-7}} transition={{duration:reduced?0:.2}}>{slides[page].title}</motion.h1></AnimatePresence></div>
    <div className="intro-art-window" aria-hidden="true"><AnimatePresence initial={false} custom={direction}><motion.div className="intro-art" key={page} custom={direction} variants={{enter:(d:number)=>({y:reduced?0:d*520,opacity:reduced?0:1}),active:{y:0,opacity:1},exit:(d:number)=>({y:reduced?0:d*-520,opacity:reduced?0:1})}} initial="enter" animate="active" exit="exit" transition={{duration:reduced?.1:.65,ease:[.65,0,.25,1]}}>
      {page === 0 ? <DiscoverArt/> : page === 1 ? <LibraryArt/> : <SparkArt/>}
    </motion.div></AnimatePresence></div>
    <footer className="intro-footer"><button className="intro-next" onClick={next} disabled={moving}>{page === 2 ? "Get started" : "Next"}</button><div className="intro-pagination" aria-label={`Introduction ${page+1} of 3`}>{slides.map((slide,index)=><span key={slide.label} className={index === page ? "active" : ""}/>)}</div></footer>
  </section>;
}
function DiscoverArt() {
  return <div className="discover-art"><img className="discover-photo" src={A+"reading-garden.png"} alt="" draggable="false"/><div className="discover-fragment">A slower<br/>afternoon.</div><article className="discovery-note"><span className="note-category">CULTURE · ATTENTION</span><p>Attention is a kind<br/>of generosity.</p><div className="note-author">Mira Chen</div></article></div>;
}
function LibraryArt() {
  return <div className="library-art">
    <div><article className="library-tile photo-tile"><img src={A+"reading-garden.png"} alt=""/></article><strong>A slower afternoon</strong><span>Collected moments</span></div>
    <div><article className="library-tile type-tile"><span>01</span><p>Keep the<br/>unfinished<br/>things.</p></article><strong>Notes to return to</strong><span>My notes</span></div>
    <div><article className="library-tile quote-tile"><p>What if<br/>we leave<br/>the edges<br/>open?</p></article><strong>Questions, still open</strong><span>My notes</span></div>
    <div><article className="library-tile chora-tile"><img src={A+"chora.png"} alt=""/></article><strong>Small discoveries</strong><span>Collections</span></div>
  </div>;
}
function SparkArt() {
  return <div className="spark-art"><article className="spark-source"><img src={A+"reading-garden.png"} alt=""/><div><span>FROM YOUR NOTE</span><p>The things we notice<br/>become the things<br/>we care about.</p></div></article><p className="spark-caption">A new perspective.<br/>A thought worth following.</p></div>;
}
