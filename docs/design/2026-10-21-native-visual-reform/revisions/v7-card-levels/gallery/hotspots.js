/* Percent coordinates checked against 1206×2622 native simulator captures.
 * Hotspots navigate this screenshot walkthrough; they never execute the underlying action. */
(() => {
const p=window.primaryFlows;
const h=(action,x,y,w,height)=>({action,x,y,w,h:height});
p.spark.states.results.hotspots=[h(0,10,74,60,6),h(1,9,83,40,5),h(2,5,88,90,7),h(4,5,26,90,9)];
p.spark.states.loading.hotspots=[h(0,10,49,80,7)];
p.spark.states.collected.hotspots=[h(1,10,74,60,6),h(2,5,88,90,7)];
p.spark.states.error.hotspots=[h(1,9,50,60,6),h(2,5,26,90,9)];
p.spark.states.deeper.hotspots=[h(0,28,16,30,6)];
p.spark.states.reader.hotspots=[h(0,3,9,14,6)];
p.merge.states.selection.hotspots=[h(0,5,65,90,10)];
p.merge.states.selected.hotspots=[h(0,60,87,35,9)];
p.merge.states.progress.hotspots=[h(0,5,87,72,8),h(1,5,79,90,7)];
p.merge.states.background.hotspots=[h(0,11,52,78,7)];
p.merge.states.ready.hotspots=[h(0,6,38,88,43)];
p.merge.states.edit.hotspots=[h(0,52,87,43,8)];
p.merge.states['sync-error'].hotspots=[h(1,10,43.5,60,7)];
p.merge.states.conflict.hotspots=[h(0,10,46,80,7),h(0,10,54,80,7)];
window.auxiliaryFlows.reading.states.reader.hotspots=[h(0,72,7,13,6),h(2,3,7,13,6)];
})();
