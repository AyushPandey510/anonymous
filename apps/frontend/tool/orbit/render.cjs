// Offline asset generation: npm install, then CHROMIUM_PATH=... npm run render.
const { chromium } = require('playwright');
const { createServer } = require('node:http');
const { readFileSync, mkdirSync } = require('node:fs');
const { join, dirname } = require('node:path');
const { tmpdir } = require('node:os');
const { execFileSync } = require('node:child_process');

const output = join(__dirname, '../../assets/orbit');
const frames = join(tmpdir(), 'space-orbit-frames');
mkdirSync(output, { recursive: true });
mkdirSync(frames, { recursive: true });
const three = join(dirname(require.resolve('three')), 'three.module.js');
const html = `<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:transparent}canvas{display:block;width:100vw;height:100vh}</style>
<script type="module">
import * as THREE from '/three.module.js';
const renderer = new THREE.WebGLRenderer({alpha:true,antialias:true,preserveDrawingBuffer:true});
renderer.setPixelRatio(1);
renderer.setSize(innerWidth,innerHeight);
renderer.setClearColor(0x000000,0);
document.body.appendChild(renderer.domElement);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(34,innerWidth/innerHeight,0.1,100);
camera.position.z = 7.2*Math.max(1,0.8/(innerWidth/innerHeight));
scene.add(new THREE.AmbientLight(0xffffff,1.45));
const key = new THREE.DirectionalLight(0xe9f3ff,3.2);
key.position.set(-3,5,6);scene.add(key);
const fill = new THREE.DirectionalLight(0x8e80ff,0.8);
fill.position.set(4,-2,1);scene.add(fill);
let seed = 93;
const random = () => {seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
const colors = [0x5145cc,0x7569e0,0x9a95df,0xa8bfd1,0x6664cb];
const meshes = [];
for(let i=0;i<34;i++) {
  const y = 1.68 - (i/33)*3.36;
  const angle = i*2.39996;
  const spread = 0.30 + random()*0.51;
  const radius = i%8===0 ? 0.225 : 0.065+random()*0.105;
  const mesh = new THREE.Mesh(new THREE.IcosahedronGeometry(radius,0),
    new THREE.MeshStandardMaterial({color:colors[i%colors.length],roughness:0.86,metalness:0,flatShading:true}));
  mesh.userData = {x:Math.cos(angle)*spread,y,z:Math.sin(angle)*0.38,
    phase:random()*Math.PI*2,rx:random()*Math.PI,ry:random()*Math.PI,spin:i%2 ? 1 : -1};
  meshes.push(mesh);scene.add(mesh);
}
window.renderFrame = (progress) => {
  const turn=progress*Math.PI*2;
  for(const mesh of meshes) {
    const d=mesh.userData;
    mesh.position.set(d.x+Math.sin(turn+d.phase)*0.13,d.y+Math.cos(turn+d.phase)*0.07,d.z+Math.sin(turn+d.phase)*0.15);
    mesh.rotation.set(d.rx+turn*d.spin,d.ry+turn,d.phase+Math.sin(turn)*0.18);
  }
  renderer.render(scene,camera);
};
window.renderFrame(0);
</script></html>`;

(async () => {
  const server = createServer((req, res) => {
    if (req.url.endsWith('.js')) {
      res.setHeader('Content-Type', 'text/javascript');
      res.end(readFileSync(req.url === '/three.core.js' ? join(dirname(three), 'three.core.js') : three));
    } else { res.setHeader('Content-Type', 'text/html'); res.end(html); }
  }).listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const browser = await chromium.launch({executablePath:process.env.CHROMIUM_PATH || undefined,
    args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage({viewport:{width:384,height:384}});
    await page.goto('http://127.0.0.1:'+server.address().port);
    await page.waitForFunction(() => typeof window.renderFrame === 'function');
    for(let i=0;i<180;i++) {
      await page.evaluate(p => window.renderFrame(p), i/180);
      await page.screenshot({path:join(frames,String(i).padStart(3,'0')+'.png'),omitBackground:true});
    }
    // Check the actual WebGL framebuffer at desktop and phone sizes, including motion.
    for(const viewport of [{width:1440,height:900},{width:360,height:800}]) {
      await page.setViewportSize(viewport);
      await page.reload();
      await page.waitForFunction(() => typeof window.renderFrame === 'function');
      const samples=[];
      for(const p of [0,0.25]) {
        samples.push(await page.evaluate(p => {
          window.renderFrame(p);
          const canvas=document.querySelector('canvas');
          const gl=canvas.getContext('webgl2');
          const pixels=new Uint8Array(canvas.width*canvas.height*4);
          gl.readPixels(0,0,canvas.width,canvas.height,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
          let visible=0,hash=0,edge=0;
          for(let i=3;i<pixels.length;i+=4) if(pixels[i]>0) {
            visible++;hash=(hash+pixels[i-2]*(i+1))%1000000007;
            const pixel=(i-3)/4,x=pixel%canvas.width,y=Math.floor(pixel/canvas.width);
            if(x<2||y<2||x>=canvas.width-2||y>=canvas.height-2) edge++;
          }
          return {visible,hash,edge};
        },p));
      }
      if(samples.some(s=>s.visible<500 || s.edge>0)||samples[0].hash===samples[1].hash) throw Error('Scene framing/motion check failed: '+JSON.stringify(samples));
      await page.screenshot({path:join(frames,'preview-'+viewport.width+'.png'),omitBackground:true});
      console.log('Verified viewport',viewport,samples);
    }
    execFileSync('ffmpeg',['-y','-v','error','-framerate','24','-i',join(frames,'%03d.png'),
      '-c:v','libwebp_anim','-quality','85','-loop','0',join(output,'crystals.webp')]);
    execFileSync('ffmpeg',['-y','-v','error','-i',join(frames,'000.png'),'-frames:v','1',join(output,'crystals-still.webp')]);
    console.log('Rendered',output);
  } finally { await browser.close();server.close(); }
})().catch(error => {console.error(error);process.exit(1);});
