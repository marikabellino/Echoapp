const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [,, html, dir] = process.argv;
  fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
  await p.goto('file://' + html + (process.argv[4] || '')); await p.evaluate(() => window.ready);
  const fps = 30, n = 8 * fps;
  for (let f = 0; f < n; f++) {
    await p.evaluate(t => render(t), f / fps);
    await p.screenshot({ path: `${dir}/${String(f).padStart(4, '0')}.png` });
  }
  await b.close(); console.log('frames', n);
})();
