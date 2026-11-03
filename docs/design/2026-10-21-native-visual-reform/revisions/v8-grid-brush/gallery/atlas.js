(() => {
const flows = {...window.cardLevelFlows,...window.primaryFlows,...window.auxiliaryFlows};
const keys=Object.keys(flows), $=id=>document.getElementById(id), params=new URLSearchParams(location.search);
let flowID=flows[params.get('flow')]?params.get('flow'):'levels', stateID, history=[], theme=params.get('theme')==='dark'?'dark':'light', markers=true;
stateID=flows[flowID].states[params.get('state')]?params.get('state'):flows[flowID].start;
const icons={levels:'01',growth:'02',spark:'03',merge:'04',reading:'05',writing:'06',sharing:'07','link-report':'08'};
function button(text,fn,cls){let b=document.createElement('button');b.type='button';b.textContent=text;b.className=cls||'';b.onclick=fn;return b}
function go(target){if(!flows[flowID].states[target])return;history.push(stateID);stateID=target;render();revealChangedScreen()}
function changeFlow(key,target){flowID=key;stateID=target||flows[key].start;history=[];render();revealChangedScreen()}
function revealChangedScreen(){ if(window.matchMedia('(max-width:600px)').matches)document.querySelector('.visual-stage').scrollIntoView({behavior:'instant',block:'start'}); }
function nav(){ $('flow-nav').replaceChildren(...keys.map(key=>{const b=button('',()=>changeFlow(key),'flow-btn');b.dataset.flow=key;b.setAttribute('aria-current',String(flowID===key));const n=document.createElement('span');n.className='number';n.textContent=icons[key];const t=document.createElement('span');const s=document.createElement('strong');s.textContent=flows[key].title;const m=document.createElement('small');m.textContent=flows[key].kicker;t.append(s,m);b.append(n,t);return b})); }
function render(){ const flow=flows[flowID], state=flow.states[stateID];nav();
for(const [id,value]of Object.entries({'flow-kicker':flow.kicker,'flow-title':flow.title,'flow-summary':flow.summary,'step-title':state.title,explanation:state.explanation,behavior:state.behavior,current:flow.current,design:flow.design,boundary:flow.boundary}))$(id).textContent=value;
$('state-label').textContent=state.status==='existing'?'已核对源码 · 暂无新视觉':'离线原型 · 新视觉提案';
const src=theme==='dark'?state.imageDark:state.imageLight; $('screen').hidden=!src;$('uncaptured').hidden=!!src;
if(src){$('screen').src=src;$('screen').alt=flow.title+' / '+state.title+' / '+(theme==='dark'&&state.imageDark!==state.imageLight?'深色':'浅色')+' 原生原型截图'+(theme==='dark'&&state.imageDark===state.imageLight?'；深色待补':'');}else{$('screen').removeAttribute('src');$('contract-copy').textContent=state.behavior}
$('visual-label').textContent=src?'SwiftUI 原生界面实拍':'源码行为说明 · 尚未拍摄';
$('image-note').textContent=!src?'这个节点保留为设计缺口，未补造截图。':theme==='dark'&&state.imageDark===state.imageLight?'此状态仅有浅色实拍，深色画面待补。':((state.hotspots||[]).length?'点击画面编号或右侧动作继续':'此画面无标记 · 使用右侧动作继续');
document.querySelector('.actions').hidden=state.actions.length===0;
$('actions').replaceChildren(...state.actions.map((a,i)=>button((i+1)+'  '+a.label+'  →',()=>go(a.to),'action')));
$('hotspot-toggle').hidden=!(state.hotspots||[]).length;
$('hotspots').className=markers?'show-hotspots':'';
$('hotspots').replaceChildren(...(state.hotspots||[]).map(h=>{const a=state.actions[h.action];if(!a)return document.createElement('span');const b=button('',()=>go(a.to),'hotspot');b.setAttribute('aria-label',a.label+'（画面）');b.dataset.index=h.action+1;b.style.cssText=`left:${h.x}%;top:${h.y}%;width:${h.w}%;height:${h.h}%`;return b;}));
$('back').disabled=!history.length;$('position').textContent=`${Object.keys(flow.states).indexOf(stateID)+1} / ${Object.keys(flow.states).length} 个状态`;
$('state-select').replaceChildren(...Object.entries(flow.states).map(([key,s])=>{const o=document.createElement('option');o.value=key;o.textContent=s.title;o.selected=key===stateID;return o}));
$('sources').replaceChildren(...flow.source.map(s=>{const li=document.createElement('li');li.textContent=s.label;const code=document.createElement('code');code.textContent=s.path.split('/Chorai_IOS_Frontend/')[1]||s.path;li.append(code);return li}));
document.body.dataset.theme=theme;document.querySelectorAll('[data-theme]').forEach(b=>{if(b.tagName==='BUTTON')b.setAttribute('aria-pressed',String(b.dataset.theme===theme))});
const q=new URLSearchParams({flow:flowID,state:stateID,theme});try{window.history.replaceState({},'',`${location.pathname}?${q}`)}catch{};document.title=flow.title+' · Chorai 功能旅程';
}
$('back').onclick=()=>{if(history.length){stateID=history.pop();render()}};$('restart').onclick=()=>{stateID=flows[flowID].start;history=[];render()};$('state-select').onchange=e=>go(e.target.value);
document.querySelectorAll('button[data-theme]').forEach(b=>b.onclick=()=>{theme=b.dataset.theme;render()});
$('hotspot-toggle').onclick=()=>{markers=!markers;$('hotspot-toggle').setAttribute('aria-pressed',String(markers));$('hotspot-toggle').textContent='点击标记：'+(markers?'开':'关');render()};
$('overview-toggle').onclick=()=>{const open=$('overview').hidden;$('overview').hidden=!open;$('overview-toggle').setAttribute('aria-expanded',String(open));};
const heading=document.createElement('h2');heading.textContent='八条旅程，补全卡片与 Chora。';$('overview').append(heading);
keys.forEach(key=>{const row=document.createElement('div');row.className='overview-row';const title=document.createElement('strong');title.textContent=icons[key]+' / '+flows[key].title;const nodes=document.createElement('div');nodes.className='overview-nodes';Object.entries(flows[key].states).forEach(([id,state],i)=>{if(i){const arr=document.createElement('span');arr.textContent='·';nodes.append(arr)}nodes.append(button(state.title.replace(/^\S+ · /,''),()=>changeFlow(key,id)))});row.append(title,nodes);$('overview').append(row)});
render();
})();
