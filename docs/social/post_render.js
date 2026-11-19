// Cattura i fotogrammi di un post di posts.html (1080×1350, 30 fps).
// Uso: node post_render.js <numero post> <cartella> [secondi]
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [, , n, dir, secs = '7'] = process.argv;
  fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1080, height: 1350 } });
  await p.clock.install({ time: new Date() });
  await p.goto('file://' + __dirname + '/posts.html?p=' + n, { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  const fps = 30, frames = Math.round(+secs * fps);
  for (let f = 0; f < frames; f++) {
    const ms = f * 1000 / fps;
    await p.evaluate(ms => document.getAnimations().forEach(a => { a.pause(); a.currentTime = ms; }), ms);
    await p.clock.runFor(1000 / fps);
    await p.screenshot({ path: `${dir}/${String(f).padStart(4, '0')}.png` });
  }
  await b.close(); console.log('frames', frames);
})();
