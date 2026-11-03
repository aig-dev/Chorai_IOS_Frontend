const fs=require('fs'),vm=require('vm'),path=require('path');
const root=path.resolve(__dirname,'..'),g=path.join(root,'gallery'),c={window:{}};vm.createContext(c);
for(const name of ['primary-flows.js','auxiliary-flows.js','hotspots.js','card-level-flows.js'])vm.runInContext(fs.readFileSync(path.join(g,name),'utf8'),c);
const data={...c.window.cardLevelFlows,...c.window.primaryFlows,...c.window.auxiliaryFlows};
let states=0,edges=0;const images=new Set();
for(const f of Object.values(data))for(const s of Object.values(f.states)){
 states++;for(const a of s.actions){if(!f.states[a.to])throw Error('Invalid edge: '+a.to);edges++;}
 for(const h of s.hotspots||[])if(!s.actions[h.action])throw Error('Invalid hotspot');
 for(const p of [s.imageLight,s.imageDark])if(p){images.add(p);if(!fs.existsSync(path.resolve(g,p)))throw Error('Missing image '+p);}
}
fs.writeFileSync(path.join(root,'qa/gallery-data.json'),JSON.stringify(data));
console.log(JSON.stringify({flows:Object.keys(data).length,states,edges,images:images.size,missing:0}));
