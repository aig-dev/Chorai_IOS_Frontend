from pathlib import Path
from PIL import Image
import base64,io,json,re
root=Path(__file__).resolve().parent.parent;g=root/'gallery';data=json.loads((root/'qa/gallery-data.json').read_text());cache={}
for f in data.values():
 for s in f['states'].values():
  for key in ['imageLight','imageDark']:
   p=s.get(key)
   if p:
    if p not in cache:
     im=Image.open((g/p).resolve()).convert('RGB');im.thumbnail((804,1748));buf=io.BytesIO();im.save(buf,format='WEBP',lossless=True,method=6)
     cache[p]='data:image/webp;base64,'+base64.b64encode(buf.getvalue()).decode()
    s[key]=cache[p]
html=(g/'index.html').read_text().replace('<link rel="stylesheet" href="atlas.css">','<style>'+(g/'atlas.css').read_text()+'</style>')
html=re.sub(r'<script src="[^"]+"></script>','',html)
html=html.replace('<a href="../Chorai-Grid-Brush-V8-offline.html" download>下载离线版 ↓</a>','')
html=html.replace('<a href="../../v7-card-levels/gallery/">V7 原版对照 ↗</a>','<span>V8 离线版</span>')
html=html.replace('<a class="file-link" href="../README.md">原型说明与启动方式 ↗</a>','<span class="file-link">全部画面已内嵌 · 无须网络</span>')
payload='<script>window.primaryFlows='+json.dumps(data,ensure_ascii=False,separators=(',',':'))+';window.auxiliaryFlows={};window.cardLevelFlows={};</script><script>'+(g/'atlas.js').read_text()+'</script>'
html=html.replace('</body>',payload+'</body>');out=root/'Chorai-Grid-Brush-V8-offline.html';out.write_text(html)
print(f'{out.name}: {out.stat().st_size/1024/1024:.2f} MiB, {len(cache)} embedded images')
