/* ============================================================
   OptiPC 2.0 — interface
   core.js contient tout le code éprouvé de la V1 (analyses, licences,
   désinstallations, quarantaine...). Ce fichier ajoute la 2.0 et
   remplace les fonctions dont l'affichage change.
   ============================================================ */
'use strict';

/* ── Communication avec la fenêtre native ──────────────────────────── */
function hostPost(msg){ try{ window.chrome.webview.postMessage(msg); }catch(e){} }
function wcMin(){ hostPost({cmd:'min'}); }
function wcMax(){ hostPost({cmd:'max'}); }
function wcClose(){ hostPost({cmd:'close'}); }
try{ window.chrome.webview.addEventListener('message',e=>{ const m=e.data||{}; if(m.cmd==='maxstate'){ const ic=$('wc-max-ico'), b=$('wc-max'); if(ic)ic.innerHTML=m.max?'<rect x="1.5" y="3.5" width="7" height="7" fill="none" stroke="currentColor" stroke-width="1.2"/><path d="M3.5 3.5V1.5h7v7h-2" fill="none" stroke="currentColor" stroke-width="1.2"/>':'<rect x="1.5" y="1.5" width="9" height="9" fill="none" stroke="currentColor" stroke-width="1.2"/>'; if(b)b.setAttribute('aria-label',m.max?'Restaurer':'Agrandir'); } }); }catch(e){}
(function setupDrag(){
  // Si la région de déplacement native n'est pas prise en charge, le clic arrive ici :
  // on demande alors à la fenêtre de se déplacer.
  document.addEventListener('mousedown',function(e){
    if(e.button!==0)return;
    const tb=e.target.closest('.titlebar');
    if(!tb||e.target.closest('.nd'))return;
    if(e.detail>1)return;
    hostPost({cmd:'drag'});
  });
})();

/* ── Prix et identité ──────────────────────────────────────────────── */
EDITEUR.prixPro='99,80 € par an (ou 13,80 € par mois)';
EDITEUR.dureePro='Abonnement annuel, 1 ordinateur';
const PRICES={month:'13,80 €',year:'99,80 €'};
// Limites de la version gratuite (27/10/2026) : le moteur répond {premium:true, quota:'startup'|'uninstall'}
(function(){ try{ const post=API.post; const MSG={startup:'La version gratuite permet de retirer 2 programmes du démarrage. Passez en Premium pour alléger complètement le démarrage de Windows.',uninstall:'La version gratuite permet 3 désinstallations par mois. Passez en Premium pour désinstaller sans limite.'}; API.post=async function(u,b,t){ const r=await post.call(API,u,b,t); try{ if(r&&r.premium&&!_isPro){ showProGate(MSG[r.quota]||'Cette fonction est incluse dans Premium.'); } }catch(e){} return r; }; }catch(e){} })();
function ouvrirLien(u){ try{ window.open(u,'_blank'); toast('Ouverture dans votre navigateur…','ok'); }catch(e){} }
function openBuyPage(){ try{ window.open(BUY_URL,'_blank'); toast('Page d’achat ouverte dans votre navigateur','ok'); }catch(e){ toast('Rendez-vous sur secureetech.com/optipc','info'); } }
function openPremium(){
  if(_isPro){ goSec('params'); return; }
  showProGate('Supprimez les menaces détectées, nettoyez sans limite et automatiquement, et mettez à jour vos logiciels en un clic.');
}

/* ── Utilitaires ───────────────────────────────────────────────────── */
function $(id){ return document.getElementById(id); }
function esc(x){ return String(x==null?'':x).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function fmtB(b){ b=Number(b)||0; if(b<=0)return '0 Mo'; if(b>=1073741824)return (b/1073741824).toFixed(1).replace('.',',')+' Go'; if(b>=1048576)return Math.round(b/1048576)+' Mo'; if(b>=1024)return Math.round(b/1024)+' Ko'; return b+' o'; }
function cssVar(n){ return getComputedStyle(document.documentElement).getPropertyValue(n).trim(); }
function hexToRgba(hex,a){
  hex=String(hex||'').trim();
  if(hex.startsWith('rgb'))return hex.replace(/rgba?\(([^)]+)\)/,(m,v)=>{const p=v.split(',').slice(0,3);return 'rgba('+p.join(',')+','+a+')';});
  const h=hex.replace('#',''); if(h.length<6)return 'rgba(128,128,128,'+a+')';
  return 'rgba('+parseInt(h.substr(0,2),16)+','+parseInt(h.substr(2,2),16)+','+parseInt(h.substr(4,2),16)+','+a+')';
}
function spinner(t){ return '<div class="empty-note"><span class="spin" style="width:14px;height:14px;border-width:2px;vertical-align:middle;margin-right:8px"></span>'+esc(t||'Chargement…')+'</div>'; }
function loading(s,m){
  m=m||'Traitement...';
  let el=$('_loadbar');
  if(s){
    if(!el){ el=document.createElement('div'); el.id='_loadbar'; el.style.cssText='position:fixed;bottom:22px;left:50%;transform:translateX(-50%);background:var(--card);border:1px solid var(--acc-line);border-radius:999px;padding:11px 20px;display:flex;align-items:center;gap:10px;z-index:9997;font-size:14px;font-weight:600;color:var(--text);box-shadow:0 10px 30px rgba(0,0,0,.18)'; document.body.appendChild(el); }
    el.innerHTML='<span class="spin" style="width:16px;height:16px;border-width:2px"></span><span>'+esc(m)+'</span>';
    el.style.display='flex'; el.style.opacity='1';
    if(window._loadWatch)clearTimeout(window._loadWatch);
    window._loadWatch=setTimeout(()=>{loading(false);},180000);
  } else {
    if(window._loadWatch){clearTimeout(window._loadWatch);window._loadWatch=null;}
    if(el){ el.style.transition='opacity .3s'; el.style.opacity='0'; setTimeout(()=>{if(el&&el.parentNode)el.remove();},300); }
  }
}

/* ── Thème et taille du texte ──────────────────────────────────────── */
function getThemePref(){ try{ return localStorage.getItem('optipc_theme')||'light'; }catch(e){ return 'light'; } }
function effectiveTheme(p){ if(p==='auto'){ try{ return matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'; }catch(e){ return 'light'; } } return p==='dark'?'dark':'light'; }
function applyTheme(){
  const pref=getThemePref(), t=effectiveTheme(pref);
  document.documentElement.setAttribute('data-theme',t);
  const tx=$('tb-theme-txt'), ic=$('tb-theme-ico');
  if(tx)tx.textContent=t==='dark'?'Clair':'Sombre';
  if(ic)ic.innerHTML=t==='dark'?'<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>':'<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>';
  document.querySelectorAll('#set-theme button').forEach(b=>b.classList.toggle('on',b.dataset.v===pref));
  hostPost({cmd:'theme',dark:t==='dark'});
  redrawGraphs();
  if(window._histItems)renderHistory(window._histItems);
}
function setTheme(p){ try{ localStorage.setItem('optipc_theme',p); }catch(e){} applyTheme(); }
function toggleTheme(){ setTheme(effectiveTheme(getThemePref())==='dark'?'light':'dark'); }
try{ matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>{ if(getThemePref()==='auto')applyTheme(); }); }catch(e){}
function setZoom(z){
  try{ localStorage.setItem('optipc_zoom',z); }catch(e){}
  document.documentElement.style.zoom=z;
  document.querySelectorAll('#set-zoom button').forEach(b=>b.classList.toggle('on',b.dataset.v===String(z)));
}
function syncSettingsUI(){
  const pref=getThemePref();
  document.querySelectorAll('#set-theme button').forEach(b=>b.classList.toggle('on',b.dataset.v===pref));
  let z='1'; try{ z=localStorage.getItem('optipc_zoom')||'1'; }catch(e){}
  document.querySelectorAll('#set-zoom button').forEach(b=>b.classList.toggle('on',b.dataset.v===String(z)));
}

/* ── Navigation ────────────────────────────────────────────────────── */
let _secLoaded={};
function showSec(name,el){
  _playNav();
  if(name==='care')name='home';
  if(name==='speedup'||name==='perf')name='tools';
  if(name==='monpc')name='health';
  document.querySelectorAll('.sec').forEach(s=>s.classList.remove('active'));
  document.querySelectorAll('.sb-item').forEach(n=>n.classList.toggle('active',n.dataset.sec===name));
  const sec=$('sec-'+name); if(sec){ sec.classList.add('active'); sec.scrollTop=0; }
  const first=!_secLoaded[name]; _secLoaded[name]=true;
  if(name==='home'){ loadHomeStatus(); }
  if(name==='clean'){ cleanTab('quick'); }
  if(name==='space'){ if(_space)renderSpace(); }
  if(name==='protect'){ loadSecStatus(); loadAccessStatus(); if(first&&!window._brw)loadBrowserHijack(); else if(window._brw)renderBrowserHijack(window._brw); }
  if(name==='apps'){ if(first){ loadApps(); loadStartup(); if(!window._softUpd)loadSoftUpdatesCount(); } else appCounts(); }
  if(name==='health'){ loadHealth(false); loadDiskInfo(); if(first)loadSysInfo(); }
  if(name==='network'){ if(first)loadNetwork(false); }
  if(name==='tools'){ loadQuarantine(); loadRestorePoints(); loadWinOld(); const adv=$('adv-card'); if(adv&&!adv._hooked){ adv._hooked=true; adv.addEventListener('toggle',()=>{ if(adv.open&&!adv._loaded){ adv._loaded=true; loadRam(); loadPowerPlans(); loadServices(); loadVirtMem(); } }); } }
  if(name==='params'){ renderPlanCompare(); loadScheduleStatus(); loadNotifSetting(); syncSettingsUI(); }
}
function goSec(name){ showSec(name,null); }
function goActivate(){
  goSec('params');
  const k=$('lic-key');
  if(k){ setTimeout(()=>{ k.scrollIntoView({behavior:'smooth',block:'center'}); k.focus(); },150); }
}

/* ── Graphiques de la barre latérale ───────────────────────────────── */
const _dskHist=[], _gpuHist=[];
function _drawGraph(canvasId,data,colorVar){
  const c=$(canvasId); if(!c||!data||!data.length)return;
  if(data.length===1)data=[data[0],data[0]];
  const ctx=c.getContext('2d'), W=c.width, H=c.height;
  let col=colorVar||'#E8650C';
  if(String(col).startsWith('--'))col=cssVar(col)||'#E8650C';
  ctx.clearRect(0,0,W,H);
  ctx.strokeStyle=hexToRgba(cssVar('--muted')||'#888',.14); ctx.lineWidth=1;
  for(let i=1;i<3;i++){ ctx.beginPath(); ctx.moveTo(0,H/3*i); ctx.lineTo(W,H/3*i); ctx.stroke(); }
  const step=W/39, x0=W-(data.length-1)*step, pad=4;
  const y=v=>H-pad-(Math.max(0,Math.min(100,v))/100)*(H-pad*2);
  const g=ctx.createLinearGradient(0,0,0,H); g.addColorStop(0,hexToRgba(col,.35)); g.addColorStop(1,hexToRgba(col,0));
  ctx.beginPath(); data.forEach((v,i)=>{ const x=x0+i*step; i?ctx.lineTo(x,y(v)):ctx.moveTo(x,y(v)); });
  ctx.lineTo(W,H); ctx.lineTo(x0,H); ctx.closePath(); ctx.fillStyle=g; ctx.fill();
  ctx.beginPath(); data.forEach((v,i)=>{ const x=x0+i*step; i?ctx.lineTo(x,y(v)):ctx.moveTo(x,y(v)); });
  ctx.strokeStyle=col; ctx.lineWidth=2.4; ctx.lineJoin='round'; ctx.stroke();
  const lx=x0+(data.length-1)*step, ly=y(data[data.length-1]);
  ctx.beginPath(); ctx.arc(lx,ly,3,0,Math.PI*2); ctx.fillStyle=col; ctx.fill();
}
function redrawGraphs(){
  _drawGraph('sb-cpu-canvas',_cpuHist,'--c-cpu');
  _drawGraph('sb-ram-canvas',_ramHist,'--c-ram');
  _drawGraph('sb-temp-canvas',_tempHist,'--c-temp');
  _drawGraph('sb-dsk-canvas',_dskHist,'--c-disk');
  _drawGraph('sb-gpu-canvas',_gpuHist,'--c-gpu');
}
async function pollPerf(){
  try{
    const [d,p2]=await Promise.all([API.get('/api/perf',15000),API.get('/api/perf2',15000).catch(()=>null)]);
    const r=d.ram||{};
    const ram=Math.round(r.pct||0), cpu=Math.round(r.cpuPct||0);
    _ramHist.push(ram); if(_ramHist.length>40)_ramHist.shift();
    _cpuHist.push(cpu); if(_cpuHist.length>40)_cpuHist.shift();
    const sr=$('sb-ram-pct'); if(sr)sr.textContent=ram+' %';
    const sc=$('sb-cpu-pct'); if(sc)sc.textContent=cpu+' %';
    const rd=$('sb-ram-detail'); if(rd&&r.used&&r.total)rd.textContent=r.used+' / '+r.total;
    const cd=$('sb-cpu-detail'); if(cd)cd.textContent=cpu<30?'Charge normale':cpu<60?'Charge modérée':'Charge élevée';
    const st=$('stat-ram'); if(st)st.textContent=ram+' %';
    const sb=$('stat-ram-bar'); if(sb)sb.style.width=ram+'%';
    const t=d.temp||{};
    const tv=$('sb-temp-val'), td=$('sb-temp-detail');
    if(t.available){
      const c=t.celsius;
      if(tv){ tv.textContent=Math.round(c)+' °C'; tv.style.color=c>=85?'var(--red)':'var(--c-temp)'; }
      if(td)td.textContent=c>=85?'Critique':c>=70?'Chaud':'Normal';
      _tempMax=Math.max(_tempMax,c+5);
      _tempHist.push(Math.min(100,Math.round(c/_tempMax*100))); if(_tempHist.length>40)_tempHist.shift();
    } else {
      if(tv){ tv.textContent='N/D'; tv.style.color='var(--muted)'; }
      if(td)td.textContent='Capteur non disponible';
    }
    const dr=d.drives||[]; const c1=dr.find(x=>x.letter==='C:')||dr[0];
    const sd=$('sb-disk-txt'); if(sd&&c1)sd.textContent=String(c1.free||'--').replace(' GB',' Go').replace(' MB',' Mo');
    const n=$('sb-net-txt'); if(n)n.textContent=d.net==='Connecte'?'Connecté':(d.net==='Deconnecte'?'Déconnecté':(d.net||'--'));
    const so=$('sb-self-txt'); if(so&&d.self){ so.textContent=d.self.cpu+' %'; so.title='OptiPC : '+d.self.cpu+' % du processeur · '+d.self.mem; }
    if(p2){
      const dk=(p2.disk==null)?null:p2.disk;
      const dv=$('sb-dsk-pct'); if(dv)dv.textContent=dk==null?'N/D':dk+' %';
      if(dk!=null){ _dskHist.push(dk); if(_dskHist.length>40)_dskHist.shift(); }
      const g=p2.gpu||{};
      const box=$('sb-gpu-box');
      if(g.present){
        if(box)box.style.display='';
        const gv=$('sb-gpu-pct'); if(gv)gv.textContent=g.pct==null?'N/D':g.pct+' %';
        const gd=$('sb-gpu-detail'); if(gd)gd.textContent=(g.name||'Carte graphique').replace(/NVIDIA |GeForce |\(R\)|\(TM\)/g,'').trim()+(g.temp!=null?' · '+g.temp+' °C':'');
        if(g.pct!=null){ _gpuHist.push(g.pct); if(_gpuHist.length>40)_gpuHist.shift(); }
      } else if(box) box.style.display='none';
      const pr=$('stat-procs'); if(pr&&p2.procs)pr.textContent=p2.procs;
    }
    redrawGraphs();
  }catch(e){}
  _schedPerf();
}

/* ── Accueil : la grande analyse ───────────────────────────────────── */
const ICO={
  trash:'<path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/>',
  copy:'<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
  folder:'<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  file:'<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
  download:'<path d="M12 4v11"/><path d="m7 10 5 5 5-5"/><path d="M5 20h14"/>',
  rocket:'<path d="M5 15c-1.5 1.5-2 5-2 5s3.5-.5 5-2"/><path d="M9 15 5.5 11.5c1-3 3.5-6.5 8.5-8.5 2 0 4 0 7 .5.5 3 .5 5 .5 7-2 5-5.5 7.5-8.5 8.5z"/><circle cx="15" cy="9" r="1.6"/>',
  cpu:'<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
  shield:'<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/>',
  refresh:'<path d="M20 11a8 8 0 0 0-14.5-4.5L4 8"/><path d="M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.5 4.5L20 16"/><path d="M20 20v-4h-4"/>',
  health:'<path d="M20.8 8.6a5 5 0 0 0-8.8-3.2 5 5 0 0 0-8.8 3.2c0 5.4 8.8 11.4 8.8 11.4s8.8-6 8.8-11.4z"/><path d="M3.5 12h4l2-3 3 6 2-3h6"/>',
  disk:'<path d="M21 12a9 9 0 1 1-9-9v9z"/><path d="M14 3.3A9 9 0 0 1 20.7 10H14z"/>',
  zap:'<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  crown:'<path d="m3 8 4.5 4L12 5l4.5 7L21 8l-2 11H5z"/>',
  check:'<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  alert:'<path d="M12 3 2 20h20z"/><path d="M12 10v4"/><circle cx="12" cy="17" r=".6"/>',
  gauge:'<path d="M4 18a9 9 0 1 1 16 0"/><path d="m12 14 4-5"/>',
  big:'<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 16-5-5-9 9"/>'
};
function svgI(k,s){ return '<svg width="'+(s||22)+'" height="'+(s||22)+'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(ICO[k]||'')+'</svg>'; }

// Programmes qu'on peut retirer du démarrage sans risque (le programme reste installé).
const USELESS_START=/spotify|discord|steam|epic ?games|epicgameslauncher|origin|uplay|ubisoft|battle\.net|opera|edgeautolaunch|microsoftedgeautolaunch|teams|skype|zoom|ccleaner|itunes|utorrent|bittorrent|qbittorrent|cortana|creative ?cloud|ccxprocess|lghub|wallpaper|messenger|whatsapp|telegram|slack|viber|amazon ?music|deezer|evernote|grammarly|clipchamp|yourphone|phonelink/i;
const KEEP_START=/securityhealth|defender|antivirus|avast|avg|norton|kaspersky|bitdefender|eset|mcafee|malwarebytes|realtek|rtk|nvidia|amd|radeon|intel|synaptics|elan|etd|touchpad|audio|bluetooth|onedrive|dropbox|google ?drive|icloud|optipc|secureetech|anydesk|teamviewer|vigilance|vpn/i;
function isUselessStartup(i){ const n=String(i.name||''), c=String(i.command||''); return !!i.enabled && USELESS_START.test(n+' '+c) && !KEEP_START.test(n); }

let _scanR=null, _issues=[], _optRunning=false;
function setPhase(p){ const h=$('hero'); if(h)h.dataset.phase=p; const o=$('orb'); if(o)o.disabled=(p==='scan'||p==='opt'); }
function orbClick(){
  const p=($('hero')||{}).dataset?$('hero').dataset.phase:'idle';
  if(p==='idle')startHomeScan();
  else if(p==='done'){ const r=$('home-results'); if(r)r.scrollIntoView({behavior:'smooth',block:'start'}); }
  else if(p==='fixed')resetHome();
}
function resetHome(){ setPhase('idle'); const r=$('home-results'); if(r)r.style.display='none'; const d=$('home-dash'); if(d)d.style.display='flex'; }
function countUp(el,to,ms,fmt){
  if(!el)return; const from=Number(el.dataset.v||0), t0=performance.now(); el.dataset.v=to;
  const f=fmt||(v=>String(Math.round(v)));
  const tick=now=>{ const k=Math.min(1,(now-t0)/(ms||900)), e=1-Math.pow(1-k,3); el.textContent=f(from+(to-from)*e); if(k<1)requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
function setScore(score){
  const s=Math.max(0,Math.min(100,Math.round(score||0)));
  const C=2*Math.PI*120, arc=$('score-arc');
  const c=s>=80?['#A6F5C8','#3DD47F','Excellent']:s>=60?['#FFE08A','#FFB547','À améliorer']:['#FFB3A8','#FF6B5E','À soigner'];
  const g1=$('sg1'), g2=$('sg2'); if(g1)g1.setAttribute('stop-color',c[0]); if(g2)g2.setAttribute('stop-color',c[1]);
  if(arc){ arc.style.setProperty('--sc',c[1]); requestAnimationFrame(()=>arc.setAttribute('stroke-dasharray',(C*s/100).toFixed(1)+' '+C.toFixed(1))); }
  countUp($('orb-score'),s,1300);
  const l=$('orb-lbl'); if(l){ l.textContent=c[2]; l.style.color=c[1]; }
}
// Compatibilité avec le code de la V1
function setRing(score){ if(score!=null)window._lastScore=score; }
function setRingScanning(){}
function resetCare(){ resetHome(); }
function buildRecs(){ if(_scanR)renderIssues(); }
async function doCare(){
  // Rafraîchissement discret (après un nettoyage, par exemple)
  try{ const d=await API.get('/api/analyze',180000); _cleanItems=d.items||[]; window._lastScanData=d; renderQuickClean(); loadScoreHistory(); }catch(e){}
}

const SCAN_STEPS=[['web','Navigateurs détournés'],['junk','Fichiers inutiles'],['space','Doublons, dossiers et fichiers vides'],['start','Programmes au démarrage'],['sec','Protection et antivirus'],['health','Santé des disques'],['upd','Logiciels à mettre à jour'],['ram','Mémoire vive']];
function stepsHtml(list,prefix){ return list.map(s=>'<div class="step" id="'+prefix+s[0]+'"><span class="sd"></span><span>'+esc(s[1])+'</span><span class="f"></span></div>').join(''); }
function stepSet(prefix,k,state,found){
  const el=$(prefix+k); if(!el)return;
  el.className='step '+state;
  const sd=el.querySelector('.sd'); if(sd)sd.innerHTML=state==='done'?svgI('check',14):state==='err'?'!':'';
  if(found!=null)el.querySelector('.f').textContent=found;
}
async function startHomeScan(){
  if(_scanning||_optRunning)return; _scanning=true;
  _playNav&&_playNav();
  setPhase('scan');
  const res=$('home-results'); if(res)res.style.display='none';
  const dash=$('home-dash'); if(dash)dash.style.display='none';
  $('scan-steps').innerHTML=stepsHtml(SCAN_STEPS,'ss-');
  setTopStatus('run','Analyse en cours…');
  const t0=Date.now(); let done=0, shown=0;
  const total=SCAN_STEPS.length;
  const timer=setInterval(()=>{
    const t=(Date.now()-t0)/1000, f=done/total, curve=100*(1-Math.exp(-t/45));
    const target=Math.min(99,f*85+(1-f)*curve);
    shown=Math.min(99,Math.max(shown+0.04,target));
    $('orb-pct').textContent=Math.round(shown)+'\u202F%'; $('scan-bar').style.width=shown+'%';
    const sec=Math.round(t); $('scan-count').textContent=done+' / '+total+' contrôles terminés · '+Math.floor(sec/60)+':'+String(sec%60).padStart(2,'0');
  },200);
  const R={}; window._scanR=R;
  const run=(k,p,fmt)=>{ stepSet('ss-',k,'run'); return p.then(v=>{ R[k]=v; done++; stepSet('ss-',k,'done',fmt?fmt(v):''); }).catch(()=>{ R[k]=null; done++; stepSet('ss-',k,'err','indisponible'); }); };
  await Promise.all([
    run('junk',API.get('/api/analyze',180000),d=>{ _cleanItems=d.items||[]; window._lastScanData=d; return fmtB(junkBytes(d,true)); }),
    run('space',API.post('/api/space/scan',{force:true},300000),d=>{ _space=d; window._space=d; return (((d.groups||{}).dups||{}).items||[]).length+' doublons'; }),
    run('start',API.get('/api/startup',60000),d=>{ const n=(d.items||[]).filter(isUselessStartup).length; return n?n+' inutile'+(n>1?'s':''):'OK'; }),
    run('sec',API.get('/api/security/status',60000),d=>{ const n=secIssueList(d).length; return n?n+' à corriger':'OK'; }),
    run('health',API.post('/api/health',{force:false},120000),d=>{ const w=((d||{}).disks||{}).worst; return w==='crit'?'alerte':w==='warn'?'à surveiller':'OK'; }),
    run('upd',API.post('/api/softupdates',{force:false},180000),d=>d&&d.available?(d.count?d.count+' à mettre à jour':'à jour'):'—'),
    run('ram',API.get('/api/ram',30000),d=>(d.pct||d.usedPct||0)+' %'),
    run('web',API.get('/api/browsers/hijack',90000),d=>{ renderBrowserHijack(d); return d.count?d.count+' détournement'+(d.count>1?'s':''):'OK'; })
  ]);
  clearInterval(timer);
  $('orb-pct').textContent='100 %'; $('scan-bar').style.width='100%';
  _scanR=R; _scanning=false;
  if(R.health){ window._health=R.health; renderHomeHealth(R.health); }
  if(R.upd){ window._softUpd=R.upd; }
  if(R.junk){ renderQuickClean(); }
  buildIssues(); renderIssues();
  setTimeout(()=>{
    setPhase('done'); setScore((R.junk&&R.junk.score)||60);
    const r=$('home-results'); if(r){ r.style.display=''; }
    loadScoreHistory(); loadSecStatusQuiet();
  },350);
  addLog('Analyse complète : score '+((R.junk&&R.junk.score)||'--')+'/100');
}
function junkBytes(d,includeAdv){
  const it=(d&&d.items)||[];
  return it.filter(i=>i.size>0&&((i.cat==='Windows'&&i.id!=='recent')||i.cat==='Navigateurs'||(includeAdv&&_isPro&&i.cat==='Avance'&&i.id!=='winold'&&i.id!=='prefetch'))).reduce((s,i)=>s+(i.size||0),0);
}
function secIssueList(d){
  if(!d)return [];
  const other=d.otherAV===true, out=[];
  if(!d.defEnabled&&!other)out.push('enable_defender');
  if(!d.fwOk)out.push('enable_firewall');
  if(d.uacOk===false)out.push('enable_uac');
  if(d.ssOk===false)out.push('enable_smartscreen');
  return out;
}
function spItems(k){ return ((((_scanR||{}).space||{}).groups||{})[k]||{}).items||[]; }
function spItemsVis(k){ return spVisible(spItems(k)); }
function buildIssues(){
  const R=_scanR||{}, L=[];
  const an=R.junk;
  if(an){
    const jb=junkBytes(an,true);
    if(jb>0){ const jg=_isPro?jb:Math.round(jb/2); L.push({id:'junk',ico:'trash',cls:'bad',t:'Fichiers inutiles',d:'Fichiers temporaires, caches des navigateurs, restes de mises à jour Windows'+(_isPro?'':' · '+fmtB(jb)+' trouvés : la version gratuite en nettoie la moitié, Premium nettoie tout'),bytes:jg,gain:fmtB(jg),sev:'Important',act:true,on:true}); }
    const adv=(an.items||[]).filter(i=>i.size>0&&i.cat==='Avance'&&i.id!=='winold'&&i.id!=='prefetch').reduce((s,i)=>s+i.size,0);
    if(adv>0&&!_isPro)L.push({id:'adv',ico:'crown',cls:'acc',t:'Nettoyage avancé',d:'Mises à jour Windows déjà installées, caches DirectX, fichiers de plantage',bytes:0,gain:fmtB(adv),sev:'Premium',prem:true});
  }
  if(R.space){
    const dupsAll=spItems('dups'), dups=spItemsVis('dups'), safe=dups.filter(x=>x.level==='safe'), perso=dups.filter(x=>x.level!=='safe'), lockedD=dupsAll.length-dups.length;
    const sb=safe.reduce((s,x)=>s+(x.size||0),0);
    if(safe.length)L.push({id:'dups',ico:'copy',cls:'warn',t:safe.length+' doublon'+(safe.length>1?'s':'')+' sans risque',d:'Copies identiques : la copie d’origine est toujours gardée'+(perso.length?' · '+perso.length+' photo(s)/vidéo(s) en double à vérifier dans Espace disque':'')+(lockedD?' · '+lockedD+' autre(s) doublon(s) visibles avec Premium':''),bytes:sb,gain:fmtB(sb),sev:'Sans risque',act:true,on:true,space:safe.map(x=>x.path)});
    else if(perso.length)L.push({id:'dupsp',ico:'copy',cls:'warn',t:perso.length+' photo(s), vidéo(s) ou document(s) en double',d:'Fichiers personnels : à vérifier vous-même avant de supprimer',bytes:0,gain:fmtB(perso.reduce((s,x)=>s+(x.size||0),0)),sev:'À vérifier',link:'space'});
    const ed=spItemsVis('empty');
    if(ed.length)L.push({id:'emptyd',ico:'folder',cls:'blue',t:ed.length+' dossier'+(ed.length>1?'s':'')+' vide'+(ed.length>1?'s':''),d:'Dossiers qui ne contiennent plus rien',bytes:0,gain:String(ed.length),sev:'Sans risque',act:true,on:true,space:ed.map(x=>x.path)});
    const ef=spItemsVis('emptyfiles').filter(x=>x.level==='safe');
    if(ef.length)L.push({id:'emptyf',ico:'file',cls:'blue',t:ef.length+' fichier'+(ef.length>1?'s':'')+' vide'+(ef.length>1?'s':''),d:'Fichiers de 0 octet, sans aucun contenu',bytes:0,gain:String(ef.length),sev:'Sans risque',act:true,on:true,space:ef.map(x=>x.path)});
    const dl=spItemsVis('downloads').filter(x=>x.level==='safe'), db=dl.reduce((s,x)=>s+(x.size||0),0);
    if(dl.length)L.push({id:'olddl',ico:'download',cls:'warn',t:dl.length+' vieux installateur'+(dl.length>1?'s':'')+' et archive'+(dl.length>1?'s':''),d:'Fichiers téléchargés il y a plus de 2 mois, déjà installés ou décompressés',bytes:db,gain:fmtB(db),sev:'Sans risque',act:true,on:true,space:dl.map(x=>x.path)});
    const big=spItems('big'), bb=big.reduce((s,x)=>s+(x.size||0),0);
    if(bb>1073741824)L.push({id:'big',ico:'big',cls:'acc',t:big.length+' gros fichiers',d:'Les fichiers qui prennent le plus de place : à regarder dans Espace disque',bytes:0,gain:fmtB(bb),sev:'À regarder',link:'space'});
  }
  if(R.start){
    const u=(R.start.items||[]).filter(isUselessStartup);
    if(u.length)L.push({id:'start',ico:'rocket',cls:'bad',t:u.length+' programme'+(u.length>1?'s':'')+' inutile'+(u.length>1?'s':'')+' au démarrage',d:u.slice(0,4).map(x=>x.name).join(', ')+(u.length>4?'…':'')+' : retirés du démarrage, ils restent installés',bytes:0,gain:'−'+u.length,sev:'Important',act:true,on:true,startItems:u});
  }
  if(R.ram){ const p=R.ram.pct||R.ram.usedPct||0; if(p>=70)L.push({id:'ram',ico:'cpu',cls:'blue',t:'Mémoire vive chargée ('+p+' %)',d:'OptiPC libère la mémoire occupée inutilement',bytes:0,gain:p+' %',sev:'Automatique',act:true,on:true}); }
  if(R.sec){
    const s=secIssueList(R.sec);
    if(s.length)L.push({id:'sec',ico:'shield',cls:'bad',t:s.length+' protection'+(s.length>1?'s':'')+' de Windows désactivée'+(s.length>1?'s':''),d:'Antivirus, pare-feu, contrôle des comptes ou SmartScreen : OptiPC les réactive',bytes:0,gain:s.length+' fix',sev:'Important',act:true,on:true,fixes:s});
    const other=R.sec.otherAV===true;
    if(!other&&(R.sec.defSigAge||0)>3)L.push({id:'av',ico:'refresh',cls:'warn',t:'Antivirus pas à jour',d:'Dernière mise à jour il y a '+R.sec.defSigAge+' jours',bytes:0,gain:'MAJ',sev:'Important',act:true,on:true});
    if(!s.length&&!(!other&&(R.sec.defSigAge||0)>3))L.push({id:'secok',ico:'shield',cls:'ok',t:'Protection de Windows active',d:other?('Antivirus : '+(R.sec.otherAVName||'autre antivirus')):'Antivirus à jour, pare-feu actif',bytes:0,gain:'OK',sev:'OK'});
  }
  if(R.web&&R.web.count){ const c=(R.web.items||[]).filter(x=>x.level==='crit'); L.push({id:'web',ico:'alert',cls:'bad',t:'Navigateur détourné ('+[...new Set(c.map(x=>x.browser))].slice(0,3).join(', ')+')',d:[...new Set(c.map(x=>x.detail).filter(Boolean))].slice(0,3).join(', ')+' : page de démarrage ou recherche imposée. Les navigateurs seront fermés quelques secondes.',bytes:0,gain:String(c.length),sev:_isPro?'Important':'Premium',act:_isPro,on:_isPro,prem:!_isPro}); }
  if(R.upd&&R.upd.available&&R.upd.count)L.push({id:'upd',ico:'refresh',cls:'acc',t:R.upd.count+' logiciel'+(R.upd.count>1?'s':'')+' à mettre à jour',d:(R.upd.items||[]).slice(0,3).map(x=>x.name).join(', ')+' : les anciennes versions sont la porte d’entrée des virus',bytes:0,gain:String(R.upd.count),sev:'Premium',prem:!_isPro,link:'upd'});
  if(R.health){ const dk=R.health.disks||{}; if(dk.worst==='crit'||dk.worst==='warn'){ const bad=(dk.disks||[]).find(x=>x.level!=='ok')||{}; L.push({id:'disk',ico:'health',cls:dk.worst==='crit'?'bad':'warn',t:(dk.worst==='crit'?'Disque en danger : ':'Disque à surveiller : ')+(bad.name||''),d:((bad.reasons||[]).join(' · ')||'Usure ou température élevée')+'. Pensez à sauvegarder vos fichiers.',bytes:0,gain:(bad.pct!=null?bad.pct+' %':'!'),sev:'Conseil',link:'health'}); } }
  _issues=L;
}
function renderIssues(){
  const el=$('res-list'); if(!el)return;
  el.innerHTML=_issues.map((x,i)=>{
    const ctl=x.act?'<input type="checkbox" '+(x.on?'checked ':'')+'onchange="issueToggle('+i+',this.checked)" aria-label="'+esc(x.t)+'">':'<span style="width:18px"></span>';
    const pill=x.sev==='Premium'?'<span class="prem-badge">Premium</span>':'<span class="lvl '+(x.sev==='OK'||x.sev==='Sans risque'?'ok':x.sev==='Important'?'crit':'warn')+'">'+esc(x.sev)+'</span>';
    const btn=x.prem?'<button class="btn-su btn-soft" onclick="openPremium()">Débloquer</button>':x.link?'<button class="btn-su btn-ghost" onclick="issueLink(\''+x.link+'\')">Voir</button>':'';
    return '<div class="issue" style="animation-delay:'+(i*0.05)+'s">'+ctl+'<span class="ib '+x.cls+'">'+svgI(x.ico)+'</span><div class="it"><b>'+esc(x.t)+'</b><div>'+esc(x.d)+'</div></div>'+pill+'<span class="ig">'+esc(x.gain)+'</span>'+btn+'</div>';
  }).join('')||'<div class="empty-note" style="padding:18px">Rien à corriger : votre PC est en pleine forme.</div>';
  updateGains();
}
function issueLink(k){ if(k==='space'){ goSec('space'); if(_space)renderSpace(); } else if(k==='upd'){ goSec('apps'); setTimeout(()=>appFilter('upd'),60); } else goSec(k); }
function issueToggle(i,on){ if(_issues[i])_issues[i].on=on; updateGains(); }
function updateGains(){
  const sel=_issues.filter(x=>x.act&&x.on);
  const bytes=sel.reduce((s,x)=>s+(x.bytes||0),0);
  const g=$('done-gain'); if(g)countUp(g,bytes,900,v=>fmtB(v));
  const rs=$('res-sel'); if(rs)rs.textContent=fmtB(bytes);
  const nIss=_issues.filter(x=>x.act||x.prem).length;
  const pill=$('done-pill'); if(pill){ pill.innerHTML=svgI('alert',14)+' '+(nIss?nIss+' point'+(nIss>1?'s':'')+' à améliorer':'Tout est en ordre'); }
  const R=_scanR||{}, score=(R.junk&&R.junk.score)||60;
  const st=sel.find(x=>x.id==='start'), sc=sel.find(x=>x.id==='sec'), sp=sel.filter(x=>x.space);
  const files=sp.reduce((s,x)=>s+x.space.length,0);
  let est=score+3+Math.min(12,Math.round(bytes/1073741824*3))+(st?Math.min(10,st.startItems.length*2):0)+(sc?sc.fixes.length*4:0)+(sel.find(x=>x.id==='ram')?2:0)+(sel.find(x=>x.id==='av')?3:0);
  est=Math.max(score,Math.min(95,est));
  const c=(_drives||[]).find(x=>x.letter==='C:')||(_drives||[])[0];
  const G=[];
  G.push(['disk',fmtB(bytes),'d’espace récupéré']);
  G.push(['gauge',score+' → '+est,'score estimé après']);
  if(st)G.push(['rocket','−'+st.startItems.length+' programme'+(st.startItems.length>1?'s':''),'au démarrage : Windows démarre plus vite']);
  if(files)G.push(['folder',files+' élément'+(files>1?'s':''),'doublons et vides rangés à la Corbeille']);
  if(sc)G.push(['shield','Protection max','réglages de sécurité réactivés']);
  if(sel.find(x=>x.id==='ram'))G.push(['cpu','Mémoire libérée','PC plus réactif']);
  if(c&&c.totalBytes&&bytes>0){ const after=Math.max(0,Math.round((c.totalBytes-c.freeBytes-bytes)/c.totalBytes*100)); G.push(['disk',c.pct+' % → '+after+' %','disque C: occupé']); }
  const gl=$('done-gains'); if(gl)gl.innerHTML=G.slice(0,6).map((x,i)=>'<div class="gain" style="animation-delay:'+(i*0.07)+'s"><span class="gi">'+svgI(x[0],20)+'</span><div><b>'+esc(x[1])+'</b><span>'+esc(x[2])+'</span></div></div>').join('');
  const b=$('btn-boost'); if(b)b.disabled=!sel.length;
  if(!_isPro&&sp.reduce((t,x)=>t+(x.bytes||0),0)>500*1048576){ const n=$('done-gains'); if(n)n.insertAdjacentHTML('beforeend','<div class="gain" style="grid-column:1/-1;border-color:rgba(255,140,60,.35)"><span class="gi">'+svgI('crown',20)+'</span><div><b>Version gratuite : 500 Mo de fichiers à la fois</b><span>Premium récupère tout en un seul clic. <a href="#" onclick="openPremium();return false" style="color:#FFB27A;font-weight:700">Passer en Premium</a></span></div></div>'); }
}
async function startOptimize(){
  if(_optRunning)return;
  const sel=_issues.filter(x=>x.act&&x.on); if(!sel.length)return;
  _optRunning=true; setPhase('opt');
  const has=id=>sel.find(x=>x.id===id);
  const S=[['rp','Point de restauration']];
  if(has('junk'))S.push(['junk','Fichiers inutiles']);
  if(sel.some(x=>x.space))S.push(['space','Doublons, dossiers et fichiers vides']);
  if(has('start'))S.push(['start','Démarrage allégé']);
  if(has('ram'))S.push(['ram','Mémoire vive']);
  if(has('web'))S.push(['web','Navigateurs remis en état']);
  if(has('sec'))S.push(['sec','Protections de Windows']);
  if(has('av'))S.push(['av','Mise à jour de l’antivirus']);
  S.push(['score','Nouveau score']);
  $('opt-steps').innerHTML=stepsHtml(S,'os-');
  const before=((_scanR||{}).junk||{}).score||60;
  let doneN=0; const tick=()=>{ doneN++; const p=Math.round(doneN/S.length*100); $('opt-bar').style.width=p+'%'; $('orb-pct').textContent=p+'\u202F%'; };
  $('orb-pct').textContent='0 %'; $('orb-scan-lbl').textContent='OPTIMISATION'; $('opt-bar').style.width='0%';
  const K={freed:0,files:0,start:0,sec:0,limited:0,recycled:0,junkLim:0};
  const step=async(k,fn)=>{ stepSet('os-',k,'run'); try{ const f=await fn(); stepSet('os-',k,'done',f||''); }catch(e){ stepSet('os-',k,'err','non effectué'); } tick(); };
  await step('rp',async()=>{ const r=await API.post('/api/restorepoint',{desc:'OptiPC - avant optimisation'},300000); return r&&r.ok?(r.created?'créé':'déjà récent'):'impossible'; });
  if(has('junk'))await step('junk',async()=>{ const ids=((_scanR.junk||{}).items||[]).filter(i=>i.size>0&&((i.cat==='Windows'&&i.id!=='recent')||i.cat==='Navigateurs'||(_isPro&&i.cat==='Avance'&&i.id!=='winold'&&i.id!=='prefetch'))).map(i=>i.id); if(!ids.length)return 'déjà propre'; const r=await API.post('/api/clean',{selected:ids},600000); K.freed+=Number(r.cleanedBytes||0); K.junkLim=Number(r.limitedBytes||0); return String(r.cleaned||'').replace(' GB',' Go').replace(' MB',' Mo')+' libérés'; });
  if(sel.some(x=>x.space))await step('space',async()=>{ const paths=[].concat(...sel.filter(x=>x.space).map(x=>x.space)); const r=await API.post('/api/space/remove',{paths},900000); K.recycled+=Number(r.freed||0); K.files+=Number(r.count||r.done||0); K.limited=Number(r.limited||0); return (r.count||r.done||0)+' à la Corbeille'; });
  if(has('start'))await step('start',async()=>{ let n=0; for(const it of has('start').startItems){ try{ const r=await API.post('/api/startup/toggle',{name:it.name,regPath:it.regPath,enable:false},30000); if(r&&r.ok)n++; }catch(e){} } K.start=n; return n+' retiré'+(n>1?'s':''); });
  if(has('ram'))await step('ram',async()=>{ await API.post('/api/ram/optimize',{},60000); return 'libérée'; });
  if(has('web'))await step('web',async()=>{ const r=await API.post('/api/browsers/repair',{},180000); return r.msg||''; });
  if(has('sec'))await step('sec',async()=>{ let n=0; for(const f of has('sec').fixes){ try{ const r=await API.post('/api/security/fix',{action:f},180000); if(r&&(r.ok||r.success))n++; }catch(e){} } K.sec=n; return n+' corrigé'+(n>1?'s':''); });
  if(has('av'))await step('av',async()=>{ const r=await API.post('/api/security/fix',{action:'update_defender'},300000); return r&&r.ok?'à jour':'non disponible'; });
  let after=before;
  await step('score',async()=>{ const d=await API.get('/api/analyze',180000); _cleanItems=d.items||[]; window._lastScanData=d; after=Math.max(d.score||before,before); return before+' → '+after; });
  _optRunning=false;
  setPhase('fixed'); setScore(after); burst();
  const r=$('home-results'); if(r)r.style.display='none';
  const dsh=$('home-dash'); if(dsh)dsh.style.display='flex';
  const total=K.freed+K.recycled;
  $('fix-kpis').innerHTML='<div class="kpi"><b>'+fmtB(total)+'</b><span>récupérés</span></div>'
    +'<div class="kpi"><b class="g">+'+Math.max(0,after-before)+'</b><span>points de score ('+after+'/100)</span></div>'
    +(K.start?'<div class="kpi"><b>'+K.start+'</b><span>programme'+(K.start>1?'s':'')+' retiré'+(K.start>1?'s':'')+' du démarrage</span></div>':'')
    +(K.files?'<div class="kpi"><b>'+K.files+'</b><span>doublons et éléments vides rangés</span></div>':'')
    +(has('sec')||has('av')?'<div class="kpi"><b class="g">100 %</b><span>protection active</span></div>':'');
  let note='';
  if(K.recycled>0||K.files>0){ note+='Les doublons et éléments vides sont dans la Corbeille : vous pouvez encore les récupérer. Videz-la pour libérer réellement la place. '; const fr=$('fix-recycle'); if(fr)fr.style.display=''; }
  if(K.junkLim>0&&!_isPro)note+='<br><b style="color:#FFB27A">Version gratuite : '+fmtB(K.junkLim)+' de fichiers inutiles restent à nettoyer.</b> <a href="#" onclick="openPremium();return false" style="color:#FFB27A">Tout nettoyer avec Premium</a>';
  if(K.limited&&!_isPro)note+='<br><b style="color:#FFB27A">'+K.limited+' élément(s) non traités : la version gratuite est limitée à 500 Mo par passage.</b> <a href="#" onclick="openPremium();return false" style="color:#FFB27A">Passer en Premium</a>';
  $('fix-note').innerHTML=note;
  addLog('Optimisation : '+fmtB(total)+' récupérés, score '+before+' → '+after);
  loadScoreHistory(); loadSecStatusQuiet(); loadDiskInfo();
  if(notifOn('notifClean'))setTimeout(()=>toast(fmtB(total)+' récupérés · score '+after+'/100','ok'),900);
  if(!_isPro)setTimeout(showWelcomeOnce,3500);
}
async function emptyRecycle(){
  showConfirm('Vider la Corbeille ?','Les fichiers de la Corbeille seront supprimés définitivement et la place sera libérée sur le disque.',async()=>{
    loading(true,'Vidage de la Corbeille…');
    try{ const r=await API.post('/api/clean',{selected:['recycle']},300000); toast('Corbeille vidée : '+String(r.cleaned||'').replace(' GB',' Go').replace(' MB',' Mo'),'ok'); const fr=$('fix-recycle'); if(fr)fr.style.display='none'; }catch(e){ toast('Erreur','err'); }
    loading(false); loadDiskInfo();
  });
}
function burst(){
  const b=$('burst'); if(!b||document.body.classList.contains('opti-lite'))return;
  const cols=['#FF7A1A','#FFB06A','#3DD47F','#FFD2A8','#A78BFA','#6EA8FF'];
  let h=''; for(let i=0;i<28;i++){ const a=Math.random()*Math.PI*2, d=90+Math.random()*120; h+='<i style="--dx:'+Math.round(Math.cos(a)*d)+'px;--dy:'+Math.round(Math.sin(a)*d)+'px;background:'+cols[i%cols.length]+';animation-delay:'+(Math.random()*0.15).toFixed(2)+'s"></i>'; }
  b.innerHTML=h; setTimeout(()=>{ b.innerHTML=''; },1500);
}

function setTopStatus(level,txt){
  const p=$('tb-status'), t=$('top-status-txt'); if(!p||!t)return;
  p.classList.remove('warn','crit'); if(level==='warn')p.classList.add('warn'); if(level==='crit')p.classList.add('crit');
  t.textContent=txt;
}
async function loadSecStatusQuiet(){
  try{
    const d=await API.get('/api/security/status',60000);
    const other=d.otherAV===true;
    const defOk=d.defEnabled===true||other, sigOk=(d.defSigAge>=0?d.defSigAge:0)<=7||other;
    const issues=[!defOk,!sigOk,!d.fwOk,d.uacOk===false,d.ssOk===false].filter(Boolean).length;
    const pv=$('st-prot'), ps=$('st-prot-sub');
    if(pv){ pv.textContent=issues?issues+' point'+(issues>1?'s':'')+' à corriger':'Active'; pv.style.color=issues?'var(--red)':'var(--green)'; }
    if(ps)ps.textContent=other?('Antivirus : '+(d.otherAVName||'autre antivirus')):(defOk?(sigOk?'Defender à jour':'Defender pas à jour'):'Antivirus désactivé')+(d.fwOk?' · pare-feu activé':' · pare-feu désactivé');
    setTopStatus(issues?(issues>1?'crit':'warn'):'ok',issues?'À vérifier':'PC protégé');
    const b=$('sb-prot-badge'); if(b){ b.style.display=issues?'inline-block':'none'; b.textContent=issues; }
    window._secIssues=issues; window._secData=d;
  }catch(e){}
}
async function loadHomeStatus(){
  loadSecStatusQuiet();
  loadDiskInfo();
  loadScoreHistory();
  try{ const h=await API.get('/api/health',90000); renderHomeHealth(h); window._health=h; }catch(e){}
  loadBootCard();
}
function renderHomeHealth(h){
  const dk=(h&&h.disks)||{}, disks=dk.disks||[];
  const v=$('st-disk'), s=$('st-disk-sub');
  if(disks.length){
    const sys=disks.find(x=>(x.letters||[]).indexOf('C:')>=0)||disks[0];
    const worst=dk.worst||'ok';
    if(v){ v.textContent=(worst==='crit'?'Critique':worst==='warn'?'Attention':'Bonne')+' · '+sys.pct+' %'; v.style.color=worst==='crit'?'var(--red)':worst==='warn'?'var(--orange)':'var(--green)'; }
    if(s)s.textContent=(sys.name||'Disque')+' · '+(sys.size||'')+(sys.temp!=null?' · '+sys.temp+' °C':'');
  } else { if(v){v.textContent='N/D';v.style.color='var(--muted)';} if(s)s.textContent='État non disponible sur ce PC'; }
  const b=(h&&h.boot)||{}; if(b.available)renderBootStat(b);
}
function renderBootStat(b){
  const bv=$('st-boot'), bs=$('st-boot-sub');
  if(b.available&&b.lastSec){
    if(bv){ bv.textContent=fmtSec(b.lastSec); bv.style.color=b.lastSec<=45?'var(--green)':b.lastSec<=90?'var(--acc-text)':'var(--orange)'; }
    if(bs)bs.textContent=(b.firstSec&&b.firstSec>b.lastSec+3)?('contre '+fmtSec(b.firstSec)+' au premier relevé'):'dernier démarrage de Windows';
  } else { if(bv){bv.textContent='N/D';bv.style.color='var(--muted)';} if(bs)bs.textContent=b.lastBoot?'Démarré le '+b.lastBoot:'Mesure disponible au prochain démarrage'; }
}
async function loadBootCard(){ try{ const b=await API.get('/api/boot',60000); renderBootStat(b); }catch(e){} }
function fmtSec(s){ s=Math.round(s); if(s<60)return s+' s'; return Math.floor(s/60)+' min '+String(s%60).padStart(2,'0'); }
async function loadScoreHistory(){
  try{ const d=await API.get('/api/score/history',20000); window._histItems=d.items||[]; renderHistory(window._histItems); }catch(e){}
}
function renderHistory(items){
  const svg=$('hist-svg'); if(!svg)return;
  items=(items||[]).slice().sort((a,b)=>a.d<b.d?-1:1);
  const delta=$('hist-delta'), f=$('hist-first'), l=$('hist-last');
  const pill=$('last-scan-pill');
  if(pill&&items.length){ const last=items[items.length-1]; const days=Math.round((Date.now()-new Date(last.d+'T12:00:00').getTime())/86400000); pill.textContent='Dernière analyse : '+(days<=0?'aujourd’hui':days===1?'hier':'il y a '+days+' jours')+' · score '+last.s+'/100'; }
  const border=cssVar('--border')||'#333', acc=cssVar('--purple')||'#FF7A1A';
  let h='<defs><linearGradient id="hg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="'+acc+'" stop-opacity=".45"/><stop offset="1" stop-color="'+acc+'" stop-opacity="0"/></linearGradient></defs>';
  [40,90,140].forEach(y=>{ h+='<line x1="0" y1="'+y+'" x2="600" y2="'+y+'" stroke="'+border+'" stroke-width="1"/>'; });
  if(items.length<2){
    h+='<text x="300" y="86" text-anchor="middle" fill="'+(cssVar('--muted')||'#888')+'" font-size="15" font-family="Segoe UI">L’historique se remplit au fil de vos analyses</text>';
    svg.innerHTML=h; if(delta)delta.textContent=''; if(f)f.textContent=items.length?('Première analyse : '+items[0].s):'--'; if(l)l.textContent='Aujourd’hui'; return;
  }
  const n=items.length, X=i=>Math.round(i*600/(n-1)), Y=v=>Math.round(150-(Math.max(30,Math.min(100,v))-30)*1.9);
  const pts=items.map((it,i)=>X(i)+','+Y(it.s));
  h+='<path d="M'+pts.join(' L').replace(/,/g,' ')+' L600 160 L0 160 Z" fill="url(#hg)"/>';
  h+='<polyline class="hist-line" points="'+pts.join(' ')+'" fill="none" stroke="'+acc+'" stroke-width="3" stroke-linejoin="round" vector-effect="non-scaling-stroke" style="filter:drop-shadow(0 0 6px '+hexToRgba(acc,.7)+')"/>';
  h+='<circle cx="'+X(n-1)+'" cy="'+Y(items[n-1].s)+'" r="5" fill="#FFD2A8" style="filter:drop-shadow(0 0 8px '+acc+')"/>';
  svg.innerHTML=h;
  const dv=items[n-1].s-items[0].s;
  if(delta){ delta.textContent=(dv>=0?'+':'')+dv+' point'+(Math.abs(dv)>1?'s':''); delta.className='hpill '+(dv>=0?'ok':'warn'); }
  const fd=new Date(items[0].d+'T12:00:00');
  if(f)f.textContent=fd.toLocaleDateString('fr-FR',{day:'numeric',month:'long'})+' · '+items[0].s;
  if(l)l.textContent='Aujourd’hui · '+items[n-1].s;
}

/* ── Tout réparer (compatibilité : lance l'analyse puis l'optimisation) ── */
async function fixAll(){ goSec('home'); await startHomeScan(); }
async function _runFixAll(){ return fixAll(); }

/* ── Nettoyage rapide ──────────────────────────────────────────────── */
const QC_LABELS={temp_win:['Fichiers temporaires',''],thumbnails:['Miniatures','Aperçus des images, recréés automatiquement'],recent:['Fichiers récents','Liste des documents ouverts récemment'],recycle:['Corbeille',''],chrome:['Cache de Chrome',''],edge:['Cache d’Edge',''],firefox:['Cache de Firefox',''],brave:['Cache de Brave',''],opera:['Cache d’Opera',''],wu_dl:['Téléchargements Windows Update','Mises à jour déjà installées'],prefetch:['Préchargement (Prefetch)','Déconseillé : ralentit le démarrage suivant'],minidump:['Fichiers de plantage',''],delivery:['Optimisation de la distribution','Copies de mises à jour partagées'],d3d:['Cache DirectX',''],teams:['Cache de Teams',''],logs:['Journaux Windows',''],wu_cache:['Cache Windows Update',''],upgrade_logs:['Journaux de mise à niveau',''],downloaded_prog:['Programmes téléchargés',''],wer:['Rapports d’erreurs',''],shader_cache:['Cache de nuanceur DirectX','']};
let _qcSel=null;
async function loadQuickClean(force){
  if(force||!window._lastScanData){
    const l=$('qc-list'); if(l)l.innerHTML=spinner('Analyse des fichiers inutiles…');
    try{ const d=await API.get('/api/analyze',180000); _cleanItems=d.items||[]; window._lastScanData=d; setRing(d.score); buildRecs(d); _qcSel=null; }
    catch(e){ if(l)l.innerHTML='<div class="empty-note" style="color:var(--red)">Analyse impossible. <button class="btn-su btn-ghost" onclick="loadQuickClean(true)">Réessayer</button></div>'; return; }
  }
  renderQuickClean();
}
function renderQuickClean(){
  const l=$('qc-list'); if(!l||!window._lastScanData)return;
  const items=(_cleanItems||[]).filter(i=>i.id!=='winold');
  if(!_qcSel){ _qcSel=new Set(items.filter(i=>i.checked&&i.size>0&&(i.cat!=='Avance'||_isPro)).map(i=>i.id)); }
  const cats=[['Windows','Windows'],['Navigateurs','Navigateurs'],['Avance','Nettoyage avancé']];
  let h='', zero=0;
  cats.forEach(([c,lbl])=>{
    const its=items.filter(i=>i.cat===c);
    const vis=its.filter(i=>i.size>0); zero+=its.length-vis.length;
    if(!vis.length)return;
    const locked=c==='Avance'&&!_isPro;
    h+='<div class="cat-h">'+lbl+(c==='Avance'?' <span class="prem-badge">Premium</span>':'')+'</div><div class="ci-grid" style="margin-bottom:10px">';
    h+=vis.map(i=>{
      const L=QC_LABELS[i.id]||[i.label,''];
      const on=_qcSel.has(i.id)&&!locked;
      return '<label class="ci'+(locked?' locked':'')+'"'+(locked?' onclick="event.preventDefault();showProGate(\'Le nettoyage avancé est réservé à Premium : mises à jour Windows téléchargées, caches DirectX, fichiers de plantage…\')"':'')+'><input type="checkbox" '+(on?'checked ':'')+(locked?'disabled ':'')+'onchange="qcToggle(\''+i.id+'\',this.checked)"><span class="n">'+esc(L[0])+(L[1]?'<small>'+esc(L[1])+'</small>':'')+'</span><span class="s">'+fmtB(i.size)+'</span></label>';
    }).join('')+'</div>';
  });
  if(!h)h='<div class="note green">Votre PC est propre : aucun fichier inutile à supprimer.</div>';
  if(zero)h+='<div class="muted" style="font-size:12.5px">'+zero+' autre(s) catégorie(s) déjà propre(s).</div>';
  l.innerHTML=h;
  qcUpdateTotal();
}
function qcToggle(id,on){ if(!_qcSel)_qcSel=new Set(); if(on)_qcSel.add(id); else _qcSel.delete(id); qcUpdateTotal(); }
function qcUpdateTotal(){
  const tot=(_cleanItems||[]).filter(i=>_qcSel&&_qcSel.has(i.id)).reduce((s,i)=>s+(i.size||0),0);
  const t=$('qc-total'); if(t)t.textContent=fmtB(tot);
  const b=$('qc-go'); if(b)b.disabled=!tot;
}
async function runQuickClean(){
  const sel=[...(_qcSel||[])].filter(id=>{ const it=(_cleanItems||[]).find(i=>i.id===id); return it&&(it.cat!=='Avance'||_isPro); });
  if(!sel.length){ toast('Cochez au moins une catégorie','info'); return; }
  loading(true,'Nettoyage en cours…');
  try{
    const r=await API.post('/api/clean',{selected:sel},600000);
    loading(false);
    const c=String(r.cleaned||'0 B').replace(' GB',' Go').replace(' MB',' Mo').replace(' KB',' Ko');
    if(notifOn('notifClean'))showSuccess(c+' libérés !','Nettoyage terminé');
    addLog('Nettoyage rapide : '+r.cleaned+' libérés');
    _qcSel=null; loadQuickClean(true);
  }catch(e){ loading(false); toast('Erreur pendant le nettoyage','err'); }
}
function cleanTab(t){
  if(t==='space'){ goSec('space'); return; }
  if(!window._lastScanData)loadQuickClean(false); else renderQuickClean();
}

/* ── Espace disque ─────────────────────────────────────────────────── */
const SP_CATS=[['dups','Doublons','copy','Fichiers identiques présents plusieurs fois. On garde toujours une copie.'],['big','Gros fichiers','big','Les fichiers qui prennent le plus de place (100 Mo et plus).'],['downloads','Vieux téléchargements','download','Fichiers téléchargés il y a plus de 2 mois.'],['empty','Dossiers vides','folder','Dossiers qui ne contiennent plus rien.'],['emptyfiles','Fichiers vides','file','Fichiers de 0 octet, sans aucun contenu.'],['old','Fichiers anciens','refresh','Pas modifiés depuis plus de 2 ans. À vérifier avant de supprimer.']];
const SP_TILE_COL={dups:['rgba(255,122,26,.15)','#FF9B52'],big:['rgba(167,139,250,.16)','#A78BFA'],downloads:['rgba(255,181,71,.15)','#FFB547'],empty:['rgba(124,120,140,.2)','#A29EB3'],emptyfiles:['rgba(110,168,255,.15)','#6EA8FF'],old:['rgba(61,212,127,.14)','#3DD47F']};
const SP_COLORS={Videos:'#A78BFA',Images:'#FF7A1A',Telechargements:'#FFB547',Musique:'#6EA8FF',Documents:'#3DD47F',Archives:'#8F89A3',Installateurs:'#F08BC2',Autres:'#5C5869'};
const SP_LABELS={Videos:'Vidéos',Images:'Images',Telechargements:'Téléchargements',Musique:'Musique',Documents:'Documents',Archives:'Archives',Installateurs:'Installateurs',Autres:'Autres'};
let _space=null,_spSel=new Set(),_spSize={},_spCat='dups';
// Version gratuite : seuls 20 % des fichiers trouvés sont visibles (au moins 3) ; le reste est réservé à Premium.
function spFreeCount(n){ return _isPro?n:Math.min(n,Math.max(3,Math.ceil(n*0.2))); }
function spVisible(items){ return (items||[]).slice(0,spFreeCount((items||[]).length)); }
function _spIndex(d){
  _spSel=new Set(); _spSize={};
  Object.keys(d.groups||{}).forEach(k=>{ const all=d.groups[k].items||[], vis=new Set(spVisible(all).map(x=>x.path)); all.forEach(it=>{ _spSize[it.path]=it.size||0; if(it.level==='safe'&&vis.has(it.path))_spSel.add(it.path); }); });
  const first=SP_CATS.find(c=>((d.groups[c[0]]||{}).items||[]).length); _spCat=first?first[0]:'dups';
}
async function loadSpace(force){
  $('sp-start').style.display='none'; const res=$('sp-results'); res.style.display='flex';
  $('sp-list').innerHTML=spinner('Recherche dans vos dossiers personnels… (jusqu’à 2 minutes)');
  $('sp-cats').innerHTML=''; $('sp-tiles').innerHTML=''; $('sp-total').textContent='…'; $('sp-cats-bar').innerHTML='<i style="flex:1;background:rgba(255,255,255,.08)"></i>';
  try{
    const d=await API.post('/api/space/scan',{force:!!force},300000);
    _space=d; window._space=d; _spRendered=null;
    if(!_drives)await loadDiskInfo();
    renderSpace();
    addLog('Analyse de l’espace disque : '+(d.scanned||0)+' fichiers');
  }catch(e){
    $('sp-list').innerHTML='<div class="empty-note" style="color:var(--red)">La recherche n’a pas pu se terminer. <button class="btn-su btn-ghost" onclick="loadSpace(true)">Réessayer</button></div>';
  }
}
let _spRendered=null;
function spaceTotal(){ let t=0; _spSel.forEach(p=>{ t+=_spSize[p]||0; }); return t; }
function renderSpace(){
  const d=_space; if(!d)return;
  if(_spRendered!==d){ _spIndex(d); _spRendered=d; }
  $('sp-start').style.display='none'; $('sp-results').style.display='flex';
  const cats=(d.cats||[]).filter(c=>c.size>0).sort((a,b)=>b.size-a.size);
  const c=(_drives||[]).find(x=>x.letter==='C:')||(_drives||[])[0];
  const tot=c&&c.totalBytes?c.totalBytes:cats.reduce((s,x)=>s+x.size,0)||1;
  let bar=cats.map(x=>'<i title="'+esc((SP_LABELS[x.name]||x.name)+' · '+fmtB(x.size))+'" style="flex:'+Math.max(1,Math.round(x.size/tot*1000))+' 1 0;background:'+(SP_COLORS[x.name]||'#999')+';box-shadow:0 0 12px '+(SP_COLORS[x.name]||'#999')+'55"></i>').join('');
  if(c&&c.totalBytes){ const other=Math.max(0,c.totalBytes-c.freeBytes-cats.reduce((s,x)=>s+x.size,0)); bar+='<i title="Windows et programmes · '+fmtB(other)+'" style="flex:'+Math.max(1,Math.round(other/tot*1000))+' 1 0;background:#3A3F4E"></i><i title="Libre · '+fmtB(c.freeBytes)+'" style="flex:'+Math.max(1,Math.round(c.freeBytes/tot*1000))+' 1 0;background:repeating-linear-gradient(135deg,rgba(255,255,255,.08) 0 6px,transparent 6px 12px)"></i>'; }
  $('sp-cats-bar').innerHTML=bar;
  $('sp-cats').innerHTML=cats.map(x=>'<span><i style="background:'+(SP_COLORS[x.name]||'#999')+'"></i>'+(SP_LABELS[x.name]||x.name)+' <b>'+fmtB(x.size)+'</b></span>').join('')+(c&&c.totalBytes?'<span><i style="background:#3A3F4E"></i>Windows et programmes</span><span><i style="border:1px dashed #7C788C"></i>Libre <b>'+fmtB(c.freeBytes)+'</b></span>':'');
  $('sp-disk-cap').textContent=c?('Disque '+c.letter+' · '+fmtB(c.totalBytes-c.freeBytes)+' utilisés sur '+fmtB(c.totalBytes)):'Vos dossiers personnels';
  $('sp-meta').textContent=(d.scanned||0).toLocaleString('fr-FR')+' fichiers examinés'+(d.partial?' · recherche limitée dans le temps':'');
  $('sp-tiles').innerHTML=SP_CATS.map(([k,n,ic])=>{
    const g=(d.groups||{})[k]||{}, cnt=(g.items||[]).length, col=SP_TILE_COL[k]||SP_TILE_COL.old;
    const v=(k==='empty'||k==='emptyfiles')?String(cnt):fmtB(g.size||0);
    return '<button class="cat-tile'+(k===_spCat?' active':'')+'" onclick="spaceCat(\''+k+'\')"><span class="t"><i style="background:'+col[0]+';color:'+col[1]+'">'+svgI(ic,20)+'</i>'+n+'</span><span class="v">'+v+'</span><span class="h">'+(k==='empty'?'dossiers':k==='emptyfiles'?'fichiers de 0 octet':cnt+' élément'+(cnt>1?'s':''))+'</span></button>';
  }).join('');
  renderSpaceList(); spaceUpdate();
}
function spaceCat(k){ _spCat=k; renderSpace(); }
function lvlBadge(l){ return l==='safe'?'<span class="lvl safe">Sans risque</span>':l==='check'?'<span class="lvl check">À vérifier</span>':'<span class="lvl perso">Personnel</span>'; }
function renderSpaceList(){
  const d=_space, cat=SP_CATS.find(c=>c[0]===_spCat)||SP_CATS[0];
  $('sp-list-title').textContent=cat[1]; $('sp-list-desc').textContent=cat[3];
  const items=(((d.groups||{})[_spCat]||{}).items)||[];
  if(!items.length){ $('sp-list').innerHTML='<div class="empty-note" style="padding:18px">Rien à signaler dans cette catégorie.</div>'; return; }
  const vis=spVisible(items), hidden=items.slice(vis.length);
  let h=vis.map((it,i)=>{
    const on=_spSel.has(it.path);
    return '<label class="frow"><input type="checkbox" '+(on?'checked ':'')+'data-p="'+esc(it.path)+'" onchange="spaceToggle(this)">'
      +'<span style="min-width:0"><span class="fn" style="display:block">'+esc(it.name||it.path)+'</span><span class="fp" style="display:block" title="'+esc(it.detail||it.dir||'')+'">'+esc(it.detail||it.dir||'')+'</span></span>'
      +'<span>'+lvlBadge(it.level)+'</span><span class="fd">'+esc(it.date||'')+' <a href="#" onclick="event.preventDefault();event.stopPropagation();spaceOpen(\''+i+'\')" title="Montrer dans l’Explorateur">Voir</a></span><span class="fs">'+(it.size?fmtB(it.size):'—')+'</span></label>';
  }).join('');
  if(hidden.length){
    const hb=hidden.reduce((t,x)=>t+(x.size||0),0);
    h+='<div class="sp-lock"><div class="sp-blur" aria-hidden="true">'+hidden.slice(0,4).map(it=>'<div class="frow"><input type="checkbox" disabled><span><span class="fn" style="display:block">'+esc(it.name||'')+'</span><span class="fp" style="display:block">'+esc(it.dir||'')+'</span></span><span>'+lvlBadge(it.level)+'</span><span class="fd">'+esc(it.date||'')+'</span><span class="fs">'+(it.size?fmtB(it.size):'—')+'</span></div>').join('')+'</div>'
      +'<div class="sp-lock-in"><div class="sp-lock-ico">'+svgI('crown',26)+'</div><div class="sp-lock-t">'+hidden.length+' autre'+(hidden.length>1?'s':'')+' élément'+(hidden.length>1?'s':'')+(hb?' · '+fmtB(hb):'')+' à libérer</div><div class="sp-lock-d">La version gratuite affiche 20 % des résultats. Premium montre tout et libère tout en un clic.</div><div class="row" style="justify-content:center;flex-wrap:wrap;gap:10px"><button class="btn-big shine" style="min-height:46px;font-size:15px" onclick="openPremium()">Tout voir avec Premium</button>'+(_trialAvailable()?'<button class="btn-ghost-dark" style="min-height:46px" onclick="openTrial()">Essai gratuit 5 jours</button>':'')+'</div></div></div>';
  }
  $('sp-list').innerHTML=h;
}
function spaceOpen(i){ const it=((((_space||{}).groups||{})[_spCat]||{}).items||[])[+i]; if(!it)return; API.post('/api/security/open',{path:it.path}).then(r=>{ if(!(r&&r.ok))toast('Impossible d’ouvrir le dossier','err'); }).catch(()=>{}); }
function spaceToggle(cb){ const p=cb.dataset.p; if(cb.checked)_spSel.add(p); else _spSel.delete(p); spaceUpdate(); }
function spaceSelect(mode){
  const items=(((_space||{}).groups||{})[_spCat]||{}).items||[];
  items.forEach(it=>{ if(mode==='none')_spSel.delete(it.path); });
  if(mode!=='none')spVisible(items).forEach(it=>{ if(it.level==='safe')_spSel.add(it.path); });
  renderSpaceList(); spaceUpdate();
}
let _drives=null;
function spaceUpdate(){
  const tot=spaceTotal(), n=_spSel.size;
  countUp($('sp-total'),tot,700,v=>fmtB(v));
  $('sp-count').textContent=n+' élément'+(n>1?'s':'')+' coché'+(n>1?'s':'');
  const dn=$('sp-dock-n'); if(dn)dn.textContent=n+' élément'+(n>1?'s':'');
  const dv=$('sp-dock-v'); if(dv)dv.textContent=fmtB(tot);
  const go=$('sp-go'); if(go){ go.textContent=tot?'Libérer '+fmtB(tot):(n?'Ranger '+n+' élément(s) vide(s)':'Libérer'); go.disabled=!n; }
  const items=(((_space||{}).groups||{})[_spCat]||{}).items||[];
  $('sp-cat-sel').textContent=fmtB(items.filter(it=>_spSel.has(it.path)).reduce((s,it)=>s+(it.size||0),0));
  const pr=$('sp-prem'); if(pr)pr.style.display=_isPro?'none':'';
}
async function spaceRemove(){
  // Les éléments vides d'abord : la limite gratuite ne porte que sur la taille.
  const paths=[..._spSel].sort((a,b)=>(_spSize[a]||0)-(_spSize[b]||0)); if(!paths.length)return;
  const tot=spaceTotal();
  let msg=paths.length+' élément(s) ('+fmtB(tot)+') vont être envoyés dans la Corbeille de Windows. Vous pourrez les restaurer tant qu’elle n’est pas vidée.';
  if(!_isPro&&tot>500*1048576)msg+='<br><br><b>Version gratuite :</b> seuls les 500 premiers Mo seront traités. Premium libère tout en une fois.';
  showConfirm('Libérer '+fmtB(tot)+' ?',msg,async()=>{
    loading(true,'Envoi dans la Corbeille…');
    try{
      const r=await API.post('/api/space/remove',{paths},600000);
      loading(false);
      addLog('Espace disque : '+(r.msg||''));
      if(r.done){
        showConfirm('🗑️ '+String(r.freedStr||'').replace(' GB',' Go').replace(' MB',' Mo')+' dans la Corbeille','Pour récupérer réellement la place sur le disque, il faut vider la Corbeille. Voulez-vous la vider maintenant ?'+(r.limited?'<br><br><b style="color:var(--acc-text)">'+r.limited+' élément(s) non traités : la version gratuite est limitée à 500 Mo par nettoyage.</b>':''),async()=>{
          loading(true,'Vidage de la Corbeille…');
          try{ await API.post('/api/clean',{selected:['recycle']},300000); toast('Corbeille vidée','ok'); }catch(e){}
          loading(false); loadDiskInfo();
        });
      } else toast(r.msg||'Rien n’a été supprimé','info');
      loadSpace(true);
    }catch(e){ loading(false); toast('Erreur pendant la suppression','err'); }
  });
}
async function spaceMove(){
  const paths=[..._spSel].filter(p=>(_spSize[p]||0)>0);
  if(!paths.length){ toast('Cochez d’abord les fichiers à déplacer','info'); return; }
  toast('Choisissez la clé USB ou le disque de destination…','info');
  try{
    const b=await API.get('/api/browse?type=dest',300000);
    if(!b||!b.success||!b.path){ toast('Déplacement annulé','info'); return; }
    loading(true,'Déplacement des fichiers…');
    const r=await API.post('/api/space/move',{paths,dest:b.path},1800000);
    loading(false);
    toast(r.msg||'Terminé',r.ok?'ok':'err'); addLog('Déplacement : '+(r.msg||''));
    if(r.ok)loadSpace(true);
  }catch(e){ loading(false); toast('Erreur pendant le déplacement','err'); }
}

/* ── Disques (espace par lecteur) ──────────────────────────────────── */
async function loadDiskInfo(){
  try{
    const d=await API.get('/api/diskinfo',30000); _drives=d.drives||[];
    const el=$('disk-info');
    if(el)el.innerHTML=_drives.map(dr=>{ const p=dr.pct||0; return '<div style="flex:1 1 220px"><div class="flex-b" style="margin-bottom:6px"><b>'+esc(dr.letter)+'</b><span class="dim" style="font-size:13px">'+esc(String(dr.free).replace(' GB',' Go'))+' libres sur '+esc(String(dr.total).replace(' GB',' Go'))+'</span></div><div class="bar"><i style="width:'+p+'%;background:'+(p>90?'var(--red)':p>75?'var(--orange)':'var(--c-disk)')+'"></i></div><div class="muted" style="font-size:12px;margin-top:4px">'+p+' % utilisé</div></div>'; }).join('');
    const c=_drives.find(x=>x.letter==='C:')||_drives[0];
    if(c){ const s=$('stat-disk'); if(s)s.textContent=String(c.free).replace(' GB',' Go').replace(' MB',' Mo'); const b=$('stat-disk-bar'); if(b)b.style.width=Math.max(2,100-(c.pct||0))+'%'; }
    if(_space)spaceUpdate();
  }catch(e){}
}

/* ── Applications ──────────────────────────────────────────────────── */
function appIni(n){ const c=['#E8650C','#2E9A5A','#6A55D6','#1F9AB0','#C2408A','#C77700','#2563EB']; let h=0; for(const ch of String(n))h=(h*31+ch.charCodeAt(0))&0xffff; return c[h%c.length]; }
function appGroup(a){
  const n=String(a.name||''), p=String(a.publisher||'');
  if(/Visual C\+\+|\.NET (Runtime|Framework|Desktop|Host)|WebView2|Redistributable|Microsoft Edge Update|Update Health|Windows (SDK|Driver|App Certification|Software Development)|DirectX|Microsoft Edge$|Microsoft Edge \(/i.test(n))return 'win';
  if(a.type==='uwp'&&/^(Microsoft|Windows)/i.test(p)&&!/Teams|To Do|OneNote|Office|Outlook|Whiteboard|Clipchamp|Xbox|Solitaire|Bing|News|Weather|Météo|Get Help|Tips|Cortana|Feedback|People|Maps|Skype|Family|Mixed Reality|3D|Paint 3D|Zune|Groove|Films|Movies/i.test(n))return 'win';
  if(a.kind==='oem')return 'oem';
  if(a.type==='uwp'&&/^(Microsoft|Windows)/i.test(p))return 'msbloat';
  return 'user';
}
function renderApps(){
  const q=(window._appQ||'').toLowerCase();
  const force=false;
  const tech=!!($('apps-tech')&&$('apps-tech').checked);
  let list=_appsData.filter(a=>!q||(a.name||'').toLowerCase().includes(q)||(a.publisher||'').toLowerCase().includes(q));
  if(window._appF==='oem')list=list.filter(a=>appGroup(a)==='oem');
  const s=window._appSort||{key:'size',dir:-1};
  list=list.slice().sort((a,b)=>{ let va,vb; if(s.key==='size'){va=a.sizeBytes||0;vb=b.sizeBytes||0;}else{va=(a.name||'').toLowerCase();vb=(b.name||'').toLowerCase();} return va<vb?-s.dir:va>vb?s.dir:0; });
  const tgt=$(force?'force-list':'apps-list'); if(!tgt)return;
  const groups={oem:[],msbloat:[],user:[],win:[]};
  list.forEach(a=>groups[appGroup(a)].push(a));
  const visible=_appsData.filter(a=>appGroup(a)!=='win');
  const tot=visible.reduce((t,a)=>t+(a.sizeBytes||0),0);
  const totalEl=$('apps-total-size'); if(totalEl)totalEl.textContent=visible.length+' logiciel(s) · '+fmtBytes(tot);
  const cards=$('ap-cards');
  if(cards){
    const cnt=g=>_appsData.filter(a=>appGroup(a)===g).length;
    const ns=(window._startItems||[]).filter(x=>x.enabled).length, nu=((window._softUpd||{}).count)||0;
    cards.innerHTML='<div class="stat-card lift"><div class="stat-lbl">'+svgI('folder',16)+'Programmes installés</div><div class="stat-val">'+visible.length+'</div><div class="stat-sub">'+fmtB(tot)+' · composants Windows masqués</div></div>'
      +'<div class="stat-card link lift" onclick="appFilter(\'start\')"><div class="stat-lbl">'+svgI('rocket',16)+'Au démarrage</div><div class="stat-val" style="color:'+(ns>6?'var(--red)':'var(--acc-text)')+'">'+ns+'</div><div class="stat-sub">programmes se lancent avec Windows</div></div>'
      +'<div class="stat-card link lift" onclick="appFilter(\'upd\')"><div class="stat-lbl">'+svgI('refresh',16)+'Mises à jour</div><div class="stat-val" style="color:var(--acc-text)">'+(window._softUpd&&window._softUpd.available?nu:'--')+'</div><div class="stat-sub">logiciels à mettre à jour</div></div>'
      +'<div class="stat-card link lift" onclick="appFilter(\'oem\')"><div class="stat-lbl">'+svgI('alert',16)+'Logiciels du fabricant</div><div class="stat-val" style="color:var(--orange)">'+cnt('oem')+'</div><div class="stat-sub">souvent inutiles</div></div>';
  }
  const maxSz=Math.max(1,...list.map(a=>a.sizeBytes||0));
  const row=a=>{
    const i=_appsData.indexOf(a), col=appIni(a.name||'?');
    const badge=(a.type==='uwp'?' <span class="lvl" style="background:rgba(37,99,235,.12);color:var(--blue);padding:2px 8px;font-size:10.5px">STORE</span>':'')+(a.kind==='oem'?' <span class="lvl check" style="padding:2px 8px;font-size:10.5px">FABRICANT</span>':'');
    const meta=[a.version?('v'+a.version):'',a.publisher||'',a.installDate||''].filter(Boolean).join(' · ');
    const sz=a.sizeBytes?fmtBytes(a.sizeBytes):(a.size&&a.size!=='?'?a.size:'—');
    const btns='<button class="btn-su btn-ghost" onclick="uninstallApp('+i+')">Désinstaller</button><button class="btn-su btn-force" title="Désinstalle puis efface toutes les traces : dossiers, registre, services, tâches" onclick="forceApp('+i+')">Supprimer de force</button>';
    return '<div class="app-row">'+(force?'':'<input type="checkbox" class="app-cb" data-i="'+i+'" onchange="updateSel()">')
      +'<div class="app-init" style="background:'+col+'22;color:'+col+'">'+esc((a.name||'?').substring(0,2).toUpperCase())+'</div>'
      +'<div style="flex:1;min-width:0"><div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+esc(a.name)+badge+'</div><div class="muted" style="font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+esc(meta)+'</div></div>'
      +'<div class="app-size-bar" title="'+esc(sz)+'"><i style="width:'+Math.max(3,Math.round((a.sizeBytes||0)/maxSz*100))+'%"></i></div>'
      +'<div style="width:70px;text-align:right;font-weight:700;font-size:13px">'+esc(sz)+'</div>'
      +'<div style="display:flex;gap:6px">'+btns+'</div></div>';
  };
  const sec=(t,arr,note)=>arr.length?'<div class="app-group-h"><span>'+t+'</span><span>'+arr.length+(note?' · '+note:'')+'</span></div>'+arr.map(row).join(''):'';
  let h=sec('Logiciels du fabricant',groups.oem,'souvent inutiles')+sec('Vos programmes',groups.user)+sec('Applications Microsoft',groups.msbloat,'jeux et applis préinstallés');
  if(tech)h+=sec('Composants Windows (mode technicien)',groups.win,'à ne retirer qu’en connaissance de cause');
  tgt.innerHTML=h||'<div class="empty-note" style="padding:16px">Aucun logiciel trouvé.</div>';
  appCounts();
}
function setAppSortSel(v){ window._appSort=v==='size_desc'?{key:'size',dir:-1}:v==='size_asc'?{key:'size',dir:1}:{key:'name',dir:1}; renderApps(); }
function switchAppTab(name){ appFilter(name==='startup'?'start':name==='updates'?'upd':'all'); }
function appFilter(f){
  window._appF=f;
  document.querySelectorAll('.segb[data-f]').forEach(b=>b.classList.toggle('on',b.dataset.f===f));
  const show=(id,on)=>{ const e=$(id); if(e)e.style.display=on?'block':'none'; };
  show('app-tab-installed',f==='all'||f==='oem'); show('app-tab-startup',f==='start'); show('app-tab-updates',f==='upd');
  const tools=$('apps-tools'); if(tools)tools.style.display=(f==='all'||f==='oem')?'flex':'none';
  window._appMode=f==='start'?'startup':f==='upd'?'updates':'installed';
  if(f==='start'){ loadStartup(); return; }
  if(f==='upd'){ loadSoftUpdates(false); return; }
  if(!_appsData.length)loadApps(); else renderApps();
}
function appCounts(){
  const set=(id,v)=>{ const e=$(id); if(e)e.textContent=v; };
  set('cnt-all',_appsData.filter(a=>appGroup(a)!=='win').length||'--');
  set('cnt-oem',_appsData.filter(a=>appGroup(a)==='oem').length);
  set('cnt-start',(window._startItems||[]).filter(x=>x.enabled).length);
  set('cnt-upd',window._softUpd&&window._softUpd.available?window._softUpd.count:'--');
}
async function loadStartup(){
  const el=$('startup-list-apps');
  try{
    const d=await API.get('/api/startup',60000);
    const items=(d.items||[]).slice().sort((a,b)=>(b.enabled-a.enabled)||(isUselessStartup(b)-isUselessStartup(a)));
    window._startItems=items;
    if(_appsData.length&&$('ap-cards'))renderApps();
    const useless=items.filter(isUselessStartup);
    let h=useless.length?'<div class="st-row" style="background:var(--acc-soft2)"><span style="flex:1"><b>'+useless.length+' programme'+(useless.length>1?'s':'')+' inutile'+(useless.length>1?'s':'')+' au démarrage</b><br><span class="muted" style="font-size:13px">Ils restent installés, ils ne se lancent simplement plus tout seuls.</span></span><button class="btn-su btn-primary" onclick="disableUseless()">Tout désactiver</button></div>':'';
    h+=items.map(i=>{ const col=appIni(i.name||'?'), u=isUselessStartup(i);
      return '<div class="st-row"><div class="app-init" style="background:'+col+'22;color:'+col+'">'+esc(String(i.name||'?').substring(0,2).toUpperCase())+'</div><div style="flex:1;min-width:0"><div style="font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+esc(i.name)+(u?' <span class="tag-useless">Inutile au démarrage</span>':'')+'</div><div style="font-size:12.5px;color:'+(i.enabled?'var(--acc-text)':'var(--muted)')+'">'+(i.enabled?'Se lance avec Windows':'Désactivé du démarrage')+'</div></div>'
        +'<label class="tog" title="'+(i.enabled?'Désactiver du démarrage':'Activer au démarrage')+'"><input type="checkbox" '+(i.enabled?'checked':'')+' onchange="toggleStartup(\''+escS(i.name)+'\',\''+escS(i.regPath||'')+'\',this.checked,this.parentElement)"><span class="tog-sl"></span></label></div>'; }).join('')||'<div class="empty-note" style="padding:16px">Aucun programme au démarrage.</div>';
    if(el)el.innerHTML=h;
    const sl=$('startup-list'); if(sl)sl.innerHTML='';
    appCounts();
  }catch(e){ if(el)el.innerHTML='<div class="empty-note" style="color:var(--red);padding:16px">Lecture impossible.</div>'; }
}
async function disableUseless(){
  const list=(window._startItems||[]).filter(isUselessStartup); if(!list.length)return;
  loading(true,'Désactivation au démarrage…'); let n=0;
  for(const it of list){ try{ const r=await API.post('/api/startup/toggle',{name:it.name,regPath:it.regPath,enable:false},30000); if(r&&r.ok)n++; }catch(e){} }
  loading(false); toast(n+' programme'+(n>1?'s':'')+' retiré'+(n>1?'s':'')+' du démarrage','ok'); addLog('Démarrage allégé : '+n+' programme(s)');
  loadStartup();
}
function updateSel(){
  const s=document.querySelectorAll('.app-cb:checked').length, b=$('btn-del-sel'); if(!b)return;
  b.disabled=!s; const bytes=_selApps().reduce((t,a)=>t+(a.sizeBytes||0),0);
  b.textContent=s?('Désinstaller ('+s+(bytes?' · '+fmtBytes(bytes):'')+')'):'Désinstaller la sélection';
}
async function loadSoftUpdatesCount(){
  try{
    const d=await API.post('/api/softupdates',{force:false},180000);
    const v=$('st-upd'), s=$('st-upd-sub');
    if(!d.available){ if(v){v.textContent='N/D';v.style.color='var(--muted)';} if(s)s.textContent='Outil Windows absent'; return; }
    if(v){ v.textContent=d.count; v.style.color=d.count?'var(--orange)':'var(--green)'; }
    if(s)s.textContent=d.count?(d.items||[]).slice(0,3).map(x=>x.name).join(', '):'Tous vos logiciels sont à jour';
    window._softUpd=d; appCounts();
  }catch(e){ const s=$('st-upd-sub'); if(s)s.textContent='Recherche impossible'; }
}
async function loadSoftUpdates(force){
  const el=$('upd-list'); if(!el)return;
  if(!force&&window._softUpd){ renderSoftUpdates(window._softUpd); return; }
  el.innerHTML=spinner('Recherche des mises à jour (jusqu’à 1 minute)…');
  try{ const d=await API.post('/api/softupdates',{force:!!force},180000); window._softUpd=d; renderSoftUpdates(d); const v=$('st-upd'); if(v&&d.available)v.textContent=d.count; }
  catch(e){ el.innerHTML='<div class="empty-note" style="color:var(--red)">Recherche impossible.</div>'; }
}
function renderSoftUpdates(d){
  const el=$('upd-list'); if(!el)return;
  if(!d.available){ el.innerHTML='<div class="note">'+esc(d.msg||'Fonction indisponible sur ce PC.')+'</div>'; return; }
  const it=d.items||[];
  if(!it.length){ el.innerHTML='<div class="note green">Tous vos logiciels sont à jour.</div>'; return; }
  el.innerHTML=(_isPro?'':'<div class="note acc" style="margin-bottom:10px">La mise à jour en un clic est réservée à <b style="color:var(--acc-text)">Premium</b>. <a href="#" onclick="openPremium();return false" style="font-weight:800">Passer en Premium</a></div>')
    +it.map((u,i)=>'<div class="app-row"><div class="app-init" style="background:'+appIni(u.name)+'22;color:'+appIni(u.name)+'">'+esc(String(u.name).substring(0,2).toUpperCase())+'</div><div style="flex:1;min-width:0"><div style="font-weight:600">'+esc(u.name)+'</div><div class="muted" style="font-size:12px">Version '+esc(u.current)+' → <b style="color:var(--green)">'+esc(u.available)+'</b></div></div><button class="btn-su '+(_isPro?'btn-primary':'btn-soft')+'" onclick="installSoftUpdate('+i+',this)">'+(_isPro?'Mettre à jour':'🔒 Mettre à jour')+'</button></div>').join('')
    +(_isPro&&it.length>1?'<div style="margin-top:12px"><button class="btn-su btn-primary" onclick="installAllSoftUpdates()">Tout mettre à jour</button></div>':'');
}
async function installSoftUpdate(i,btn){
  if(!_isPro){ showProGate('Mettez à jour tous vos logiciels en un clic avec Premium : les anciennes versions sont la première porte d’entrée des virus.'); return; }
  const u=((window._softUpd||{}).items||[])[i]; if(!u)return;
  if(btn){ btn.disabled=true; btn.innerHTML='<span class="spin" style="width:14px;height:14px;border-width:2px"></span> En cours…'; }
  try{ const r=await API.post('/api/softupdates/install',{id:u.id},1300000); toast(r.ok?(u.name+' est à jour'):(r.msg||'Échec'),r.ok?'ok':'err'); addLog('Mise à jour logiciel : '+u.name+(r.ok?' OK':' échec')); if(r.ok&&btn){btn.textContent='À jour ✓';} else if(btn){btn.disabled=false;btn.textContent='Réessayer';} }
  catch(e){ toast('Erreur','err'); if(btn){btn.disabled=false;btn.textContent='Réessayer';} }
}
async function installAllSoftUpdates(){ const its=(window._softUpd||{}).items||[]; for(let i=0;i<its.length;i++){ const b=document.querySelectorAll('#upd-list .app-row button')[i]; await installSoftUpdate(i,b); } loadSoftUpdates(true); }

/* ── Performances : démarrage ──────────────────────────────────────── */
async function loadBootCard(){
  const el=$('perf-boot'); if(!el)return;
  try{
    const b=await API.get('/api/boot',60000);
    if(b.available&&b.lastSec){
      el.innerHTML='<div class="row" style="align-items:baseline;gap:12px"><span style="font-size:30px;font-weight:800;color:var(--acc-text)">'+fmtSec(b.lastSec)+'</span><span class="dim">'+((b.firstSec&&b.firstSec>b.lastSec+3)?'contre '+fmtSec(b.firstSec)+' au premier relevé':'au dernier démarrage')+'</span></div><div class="muted" style="font-size:12.5px;margin:4px 0 8px">Pour démarrer plus vite, désactivez ci-dessous les programmes inutiles au démarrage.</div>';
    } else el.innerHTML='<div class="muted" style="font-size:13px;margin-bottom:8px">La mesure sera disponible après le prochain démarrage de Windows.</div>';
  }catch(e){ el.textContent=''; }
}

/* ── Santé du PC ───────────────────────────────────────────────────── */
function gaugeSvg(pct,level){
  const col=level==='crit'?cssVar('--red'):level==='warn'?cssVar('--orange'):cssVar('--green');
  const c=2*Math.PI*40, dash=(c*Math.max(0,Math.min(100,pct))/100).toFixed(1);
  return '<svg width="96" height="96" viewBox="0 0 96 96" aria-hidden="true"><circle cx="48" cy="48" r="40" fill="none" stroke="'+cssVar('--track')+'" stroke-width="9"/><circle cx="48" cy="48" r="40" fill="none" stroke="'+col+'" stroke-width="9" stroke-linecap="round" stroke-dasharray="'+dash+' '+c.toFixed(1)+'" transform="rotate(-90 48 48)"/></svg>';
}
async function loadHealth(force){
  if(force){ $('hl-disks').innerHTML='<div class="card">'+spinner('Lecture de l’état des disques…')+'</div>'; }
  try{ const h=await API.post('/api/health',{force:!!force},120000); window._health=h; renderHealth(h); renderHomeHealth(h); }
  catch(e){ $('hl-disks').innerHTML='<div class="card"><div class="empty-note" style="color:var(--red)">Lecture impossible.</div></div>'; }
}
function renderHealth(h){
  const dk=(h&&h.disks)||{}, disks=dk.disks||[];
  const sum=$('hl-summary');
  if(sum){
    if(dk.worst==='crit')sum.innerHTML='<div class="note red"><b>Un disque montre des signes de panne.</b> Sauvegardez vos photos et documents importants dès maintenant (clé USB, disque externe ou cloud), puis faites remplacer le disque. <a href="#" onclick="openCallback();return false" style="font-weight:800">Être rappelé par un technicien</a></div>';
    else if(dk.worst==='warn')sum.innerHTML='<div class="note" style="border-color:rgba(var(--orange-rgb),.4)"><b style="color:var(--orange)">À surveiller :</b> un disque montre une usure ou une température élevée. Pensez à sauvegarder vos fichiers importants.</div>';
    else sum.innerHTML=disks.length?'<div class="note green">Vos disques sont en bonne santé.</div>':'';
  }
  $('hl-disks').innerHTML=disks.length?disks.map(d=>'<div class="card disk-card"><div class="disk-head"><div class="gauge">'+gaugeSvg(d.pct,d.level)+'<div class="gv">'+d.pct+'<small>%</small></div></div><div style="min-width:0"><div style="font-size:17px;font-weight:800;word-break:break-word">'+esc(d.name)+'</div><div class="dim" style="font-size:13px">'+esc(d.type)+' · '+esc(d.size)+((d.letters||[]).length?' · '+esc(d.letters.join(' ')):'')+'</div><div style="margin-top:6px"><span class="lvl '+(d.level==='ok'?'ok':d.level)+'">Santé : '+esc(d.label)+'</span></div></div></div>'
    +((d.reasons||[]).length?'<div class="note '+(d.level==='crit'?'red':'')+'">'+d.reasons.map(esc).join('<br>')+'</div>':'')
    +(_isPro?'<div class="kv">'+(d.rows||[]).map(r=>'<div>'+esc(r.k)+'</div><div>'+esc(r.v)+'</div>').join('')+'</div>':'<div class="note acc" style="margin-top:8px">🔒 Le détail du disque (heures d’utilisation, température, erreurs, données écrites…) est inclus dans Premium. <a href="#" onclick="openPremium();return false" style="font-weight:800;color:var(--acc-text)">Débloquer</a></div>')+'</div>').join('')
    :'<div class="card"><div class="empty-note">L’état des disques n’est pas disponible sur ce PC (disque virtuel ou pilote ancien).</div></div>';
  const b=(h&&h.battery)||{}, bb=$('hl-batt');
  if(bb){
    if(!b.present)bb.innerHTML='<div class="card-title">Batterie</div><div class="empty-note">Pas de batterie : ordinateur de bureau.</div>';
    else bb.innerHTML='<div class="card-title">Batterie</div><div class="disk-head">'+(b.health!=null?'<div class="gauge">'+gaugeSvg(b.health,b.level)+'<div class="gv">'+b.health+'<small>%</small></div></div>':'')+'<div><div style="font-weight:800;font-size:16px">'+(b.health!=null?(b.level==='crit'?'Batterie usée':b.level==='warn'?'Batterie fatiguée':'Batterie en bonne santé'):'Batterie')+'</div><div class="dim" style="font-size:13px">Charge actuelle : '+(b.charge!=null?b.charge+' %':'--')+(b.plugged?' · branchée':'')+'</div></div></div>'
      +'<div class="kv" style="margin-top:12px">'+(b.design?'<div>Capacité d’origine</div><div>'+esc(b.design)+'</div>':'')+(b.full?'<div>Capacité actuelle</div><div>'+esc(b.full)+'</div>':'')+(b.cycles?'<div>Cycles de charge</div><div>'+b.cycles+'</div>':'')+'<div>Charge</div><div>'+(b.charge!=null?b.charge+' %':'--')+'</div></div>';
  }
  const bo=(h&&h.boot)||{}, be=$('hl-boot');
  if(be){
    be.innerHTML='<div class="card-title">Démarrage</div>'+(bo.available&&bo.lastSec?'<div class="row" style="align-items:baseline;gap:12px"><span style="font-size:30px;font-weight:800;color:var(--acc-text)">'+fmtSec(bo.lastSec)+'</span><span class="dim">au dernier démarrage</span></div>'+((bo.firstSec&&bo.firstSec>bo.lastSec+3)?'<div class="note green" style="margin-top:10px">Gain depuis le premier relevé : '+fmtSec(bo.firstSec-bo.lastSec)+'</div>':''):'<div class="empty-note">Mesure disponible après le prochain démarrage.</div>')
      +(bo.lastBoot?'<div class="muted" style="font-size:12.5px;margin-top:8px">Dernier démarrage : '+esc(bo.lastBoot)+'</div>':'')
      +'<div style="margin-top:10px"><button class="btn-su btn-ghost" onclick="goSec(\'apps\');setTimeout(()=>appFilter(\'start\'),60)">Accélérer le démarrage</button></div>';
  }
}

/* ── Réseau ────────────────────────────────────────────────────────── */
const DEV_ICONS={pc:'<rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>',box:'<rect x="2" y="13" width="20" height="8" rx="2"/><path d="M6 17h.01M10 17h.01M6 13l3-6M18 13l-3-6"/>',phone:'<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>',apple:'<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>',printer:'<path d="M6 9V2h12v7"/><rect x="2" y="9" width="20" height="8" rx="2"/><rect x="6" y="14" width="12" height="8"/>',tv:'<rect x="2" y="5" width="20" height="13" rx="2"/><path d="M8 21h8"/>',iot:'<circle cx="12" cy="12" r="3"/><path d="M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14"/>',unknown:'<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>'};
async function loadNetwork(force){
  const b=$('net-scan'); if(b){ b.disabled=true; b.textContent='Analyse en cours…'; }
  $('net-devs').innerHTML=spinner('Recherche des appareils connectés à votre box (10 à 30 secondes)…');
  const rd=$('net-radar'); if(rd)rd.classList.add('busy');
  try{ const d=await API.post('/api/network',{force:!!force},120000); renderNetwork(d); }
  catch(e){ $('net-devs').innerHTML='<div class="empty-note" style="color:var(--red)">Analyse impossible.</div>'; }
  if(b){ b.disabled=false; b.textContent='Analyser le réseau'; }
  const rd2=$('net-radar'); if(rd2)rd2.classList.remove('busy');
}
function renderNetwork(d){
  if(!d||!d.ok){ $('net-devs').innerHTML='<div class="note">'+esc((d&&d.msg)||'Aucune connexion réseau.')+'</div>'; return; }
  const w=d.wifi||{};
  const wl=w.connected?(w.level||'ok'):'none';
  $('net-cards').innerHTML='<div class="stat-card"><div class="stat-lbl">Appareils connectés</div><div class="stat-val" style="color:var(--acc-text)">'+d.count+'</div><div class="stat-sub">sur votre réseau</div></div>'
    +'<div class="stat-card"><div class="stat-lbl">Nouveaux appareils</div><div class="stat-val" style="color:'+(d.newCount?'var(--orange)':'var(--green)')+'">'+(_isPro?d.newCount:(d.newCount?'🔒':'0'))+'</div><div class="stat-sub">'+(d.newCount?'à vérifier ci-dessous':'aucun inconnu depuis la dernière fois')+'</div></div>'
    +'<div class="stat-card"><div class="stat-lbl">Wi-Fi</div><div class="stat-val" style="color:'+(wl==='crit'?'var(--red)':wl==='warn'?'var(--orange)':wl==='none'?'var(--muted)':'var(--green)')+'">'+(w.connected?(wl==='ok'?'Protégé':wl==='warn'?'Faible':'Non protégé'):'Câble')+'</div><div class="stat-sub">'+esc(w.connected?(w.ssid||''):'Connexion par câble')+'</div></div>'
    +'<div class="stat-card"><div class="stat-lbl">Serveurs DNS</div><div class="stat-val" style="color:'+(d.dnsLevel==='ok'?'var(--green)':'var(--orange)')+'">'+(d.dnsLevel==='ok'?'Normaux':'À vérifier')+'</div><div class="stat-sub">'+esc((d.dns||[]).join(', '))+'</div></div>';
  $('net-wifi').innerHTML='<div class="card-title">Sécurité du Wi-Fi</div>'+(w.connected?'<div class="row" style="margin-bottom:10px"><span class="lvl '+(wl==='ok'?'ok':wl)+'">'+esc(w.verdict||'')+'</span></div><div class="kv"><div>Réseau</div><div>'+esc(w.ssid||'--')+'</div><div>Protection</div><div>'+esc(w.auth||'--')+'</div><div>Chiffrement</div><div>'+esc(w.cipher||'--')+'</div><div>Signal</div><div>'+(w.signal!=null?w.signal+' %':'--')+'</div></div>':'<div class="note">Ce PC est relié à la box par un câble : pas de Wi-Fi à vérifier.</div>')
    +(d.dnsLevel!=='ok'?'<div class="note" style="margin-top:10px;border-color:rgba(var(--orange-rgb),.4)">Les serveurs DNS de ce PC ne sont pas ceux de votre box ni d’un service connu. Si vous ne les avez pas choisis vous-même, faites vérifier votre PC.</div>':'');
  $('net-meta').textContent='Analysé le '+(d.date||'')+' · votre PC : '+(d.myIp||'');
  const devs=(d.devices||[]).slice().sort((a,b)=>(b.isNew-a.isNew)||(b.isGateway-a.isGateway)||(b.isSelf-a.isSelf));
  window._netDevs=devs;
  $('net-devs').innerHTML=devs.map((x,i)=>'<div class="dev'+(x.isNew?' new':'')+'" style="animation:rise .4s ease both;animation-delay:'+(i*0.04)+'s"><div class="dev-ico"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(DEV_ICONS[x.type]||DEV_ICONS.unknown)+'</svg></div><div style="min-width:0;flex:1"><div class="dev-n">'+esc(x.isSelf?'Ce PC':(x.display||x.label))+(x.isNew?' <span class="lvl crit" style="padding:2px 8px;font-size:11px">Nouveau</span>':'')+'</div><div class="dev-d">'+(_isPro?(esc([x.display&&!x.isSelf?x.label:'',x.vendor,x.model&&x.model!==x.label?x.model:'',x.isSelf?x.name:''].filter(Boolean).join(' · ')||(x.privateMac?'Adresse privée (téléphone ou tablette récent)':'Nom inconnu'))+'<br>'+esc(x.ip)+(x.mac?' · '+esc(x.mac):'')):'🔒 Fabricant, modèle, adresse IP et adresse MAC avec Premium')+'</div>'
    +(x.isNew&&!_isPro?'<div class="dev-acts"><button class="btn-su btn-soft" onclick="openPremium()">🔒 Alerte nouvel appareil : Premium</button></div>':'')+(x.isNew&&_isPro?'<div class="dev-acts"><button class="btn-su btn-ghost" onclick="devMine('+i+',this)">C’est à moi</button><button class="btn-su btn-red" onclick="devUnknown()">Je ne le connais pas</button></div>':'')+'</div></div>').join('')||'<div class="empty-note">Aucun appareil trouvé.</div>';
  // Radar : la box au centre, les autres appareils autour
  const bl=$('net-blips');
  if(bl){
    const others=devs.filter(x=>!x.isGateway);
    let h='';
    const gw=devs.find(x=>x.isGateway);
    if(gw)h+='<span class="blip g" style="left:50%;top:50%"></span><span class="blab" style="left:50%;top:50%">'+esc(gw.name&&!/^\d/.test(gw.name)?gw.label:'Box internet')+'</span>';
    others.forEach((x,i)=>{
      let hsh=0; for(const ch of String(x.ip))hsh=(hsh*31+ch.charCodeAt(0))&0xffff;
      const ang=(i/Math.max(1,others.length))*Math.PI*2+(hsh%60)/100, rad=24+((hsh>>4)%14)+(i%2?8:0);
      const L=50+Math.cos(ang)*rad, T=50+Math.sin(ang)*rad;
      const cls=x.isNew?'r':x.isSelf?'g':(x.type==='phone'||x.type==='apple')?'b':'';
      const SHORT={phone:'Téléphone',apple:'Appareil Apple',tv:'TV / multimédia',printer:'Imprimante',pc:'Ordinateur',box:'Équipement réseau',iot:'Objet connecté',unknown:'Inconnu'};
      const nm=x.isSelf?'Ce PC':(x.display||SHORT[x.type]||x.label);
      h+='<span class="blip '+cls+'" style="left:'+L.toFixed(1)+'%;top:'+T.toFixed(1)+'%;animation-delay:'+(i*0.08)+'s"></span><span class="blab'+(L>55?' left':'')+'" style="left:'+L.toFixed(1)+'%;top:'+T.toFixed(1)+'%">'+esc(nm)+'</span>';
    });
    bl.innerHTML=h;
  }
}
function devMine(i,btn){ const card=btn.closest('.dev'); if(card){ card.classList.remove('new'); const a=card.querySelector('.dev-acts'); if(a)a.remove(); const t=card.querySelector('.lvl'); if(t)t.remove(); } toast('Appareil reconnu : il ne sera plus signalé','ok'); }
function devUnknown(){ showConfirm('Un appareil inconnu sur votre Wi-Fi','Si vous ne reconnaissez pas cet appareil (pensez à la télé, la tablette des petits-enfants, l’imprimante…), changez le mot de passe de votre Wi-Fi depuis votre box.<br><br>Un technicien SecureeTech peut le faire avec vous : appelez le <b>05 54 54 23 43</b> ou demandez à être rappelé.',()=>openCallback()); }
async function runSpeed(){
  const b=$('net-speed-btn'), el=$('net-speed'); b.disabled=true; b.textContent='Mesure…'; el.innerHTML=spinner('Mesure de la vitesse…');
  try{ const r=await API.post('/api/network/speed',{},90000);
    el.innerHTML=r.ok?'<div class="row" style="align-items:baseline;gap:10px"><span style="font-size:32px;font-weight:800;color:var(--acc-text)">'+String(r.mbps).replace('.',',')+'</span><span class="dim">Mbit/s en téléchargement</span></div><div style="margin-top:6px"><span class="lvl '+r.level+'">'+esc(r.text)+'</span></div>':'<div class="note">'+esc(r.msg)+'</div>';
  }catch(e){ el.innerHTML='<div class="note">Test impossible.</div>'; }
  b.disabled=false; b.textContent='Tester';
}

/* ── Outils ────────────────────────────────────────────────────────── */
async function loadRestorePoints(){
  const el=$('rp-list'); if(!el)return; el.innerHTML=spinner('Lecture…');
  try{ const d=await API.get('/api/restorepoints',60000);
    el.innerHTML=(d.items||[]).length?'<div class="kv">'+d.items.slice(0,6).map(p=>'<div>'+esc(p.desc)+'</div><div>'+esc(p.date)+'</div>').join('')+'</div>':'<div class="note">Aucun point de restauration pour le moment. Créez-en un avant toute modification importante.</div>';
  }catch(e){ el.innerHTML=''; }
}
async function createRestorePoint(){
  loading(true,'Création du point de restauration (jusqu’à 1 minute)…');
  try{ const r=await API.post('/api/restorepoint',{desc:'OptiPC - point manuel'},300000); toast(r.msg||'Terminé',r.ok?'ok':'err'); addLog('Point de restauration : '+(r.msg||'')); }catch(e){ toast('Erreur','err'); }
  loading(false); loadRestorePoints();
}
function openRestore(){ showConfirm('Revenir à un point de restauration ?','L’outil de restauration de Windows va s’ouvrir. Choisissez le point voulu : Windows redémarrera pour l’appliquer. Vos documents et photos ne sont pas touchés.',async()=>{ try{ await API.post('/api/restore/open',{}); }catch(e){} }); }
async function loadWinOld(){
  const s=$('winold-sub'); if(!s)return;
  const d=window._lastScanData; const it=d&&(d.items||[]).find(i=>i.id==='winold');
  if(it)s.textContent=it.size>0?('Ancienne version de Windows : '+fmtB(it.size)+'. Retour à l’ancienne version impossible ensuite.'):'Aucun dossier Windows.old sur ce PC.';
}
function cleanWinOld(){
  const d=window._lastScanData; const it=d&&(d.items||[]).find(i=>i.id==='winold');
  if(it&&!it.size){ toast('Aucun dossier Windows.old sur ce PC','info'); return; }
  ifPro(()=>showConfirm('Supprimer Windows.old ?','Vous ne pourrez plus revenir à la version précédente de Windows. L’opération peut durer plusieurs minutes.',async()=>{
    loading(true,'Suppression de Windows.old…');
    try{ const r=await API.post('/api/clean',{selected:['winold']},1800000); showSuccess(String(r.cleaned).replace(' GB',' Go')+' libérés','Windows.old supprimé'); addLog('Windows.old supprimé : '+r.cleaned); }catch(e){ toast('Erreur','err'); }
    loading(false); loadQuickClean(true);
  }),'La suppression de Windows.old est réservée à Premium (souvent 15 à 25 Go libérés).');
}
async function doForceDelete(){
  const path=$('force-del-path').value.trim();
  if(!path){ toast('Indiquez ou choisissez un fichier ou un dossier','info'); return; }
  showConfirm('Supprimer définitivement ?','« '+esc(path)+' »<br><br>Les programmes qui l’utilisent seront arrêtés. Action irréversible.',()=>_doForceDelete(path));
}
async function _doForceDelete(path){
  const st=$('force-del-status');
  if(st)st.innerHTML='<span style="color:var(--orange)">Suppression en cours… suivez le détail dans la fenêtre.</span>';
  const nm=path.split(/[\\\/]/).filter(Boolean).pop()||path;
  showLiveLogModal('Suppression forcée de '+_esc(nm));
  _renderLiveLines(['Démarrage de la suppression, veuillez patienter...']);
  let last=0;
  const pull=async()=>{ try{ const d=await API.get('/api/force-log',10000); if(d.lines&&d.lines.length&&d.lines.length!==last){last=d.lines.length;_renderLiveLines(d.lines);} }catch(e){} };
  const poll=setInterval(pull,700);
  const finish=(ok,msg)=>{
    const body=$('_livelog-body');
    if(body){ body.insertAdjacentHTML('beforeend','<div style="margin-top:6px;padding-top:6px;border-top:1px solid var(--border);font-weight:700;color:'+(ok?'var(--green)':'var(--red)')+'">'+(ok?'✅ ':'❌ ')+_esc(msg)+'</div>'); body.scrollTop=body.scrollHeight; }
    const cb=$('_livelog-close'); if(cb){ cb.disabled=false; cb.style.opacity='1'; cb.textContent='Fermer'; cb.onclick=()=>{ const m=$('_livelog'); if(m)m.remove(); }; }
    if(st)st.innerHTML='<span style="color:'+(ok?'var(--green)':'var(--red)')+'">'+(ok?'✅ ':'❌ ')+_esc(msg)+'</span>';
  };
  try{
    const r=await API.post('/api/force-delete',{path},600000);
    clearInterval(poll); await pull();
    if(r.success){ finish(true,r.message); $('force-del-path').value=''; toast('Supprimé !','ok'); addLog('Suppression forcée : '+r.message); }
    else { finish(false,r.error||'Échec'); toast('Échec','err'); addLog('❌ Suppression forcée : '+(r.error||'échec')); }
  }catch(e){ clearInterval(poll); await pull(); finish(false,e.name==='AbortError'?'Délai dépassé — redémarrez le PC et réessayez':'Erreur de communication avec le moteur d’OptiPC'); }
}
function setTelemetry(on){ setAccess('tel',on); const s=$('tel-sub'); if(s)s.textContent=on?'Données envoyées à Microsoft':'Télémétrie désactivée'; }

/* Rapport technicien (impression ou PDF) */
async function makeReport(){
  if(!_isPro){ showProGate('Le rapport technicien (PDF) est réservé à Premium : un état complet du PC à envoyer à votre technicien SecureeTech.'); return; }
  loading(true,'Préparation du rapport…');
  try{
    const [si,sec,h,dk]=await Promise.all([API.get('/api/sysinfo',60000).catch(()=>({})),API.get('/api/security/status',60000).catch(()=>({})),API.get('/api/health',90000).catch(()=>({})),API.get('/api/diskinfo',30000).catch(()=>({}))]);
    const an=window._lastScanData||{};
    const row=(k,v)=>'<tr><td>'+esc(k)+'</td><td>'+esc(v==null||v===''?'--':v)+'</td></tr>';
    let r='<h1>Rapport OptiPC — '+esc(si.hostname||'')+'</h1><div>Établi le '+new Date().toLocaleString('fr-FR')+' · OptiPC '+esc(document.querySelector('.opti-ver')?document.querySelector('.opti-ver').textContent:'2.0')+'</div>';
    r+='<h2>Ordinateur</h2><table>'+row('Système',(si.os||'')+' ('+(si.build||'')+')')+row('Processeur',si.cpu)+row('Mémoire',si.ram)+row('Carte graphique',si.gpu)+row('Fabricant / modèle',(si.manufacturer||'')+' '+(si.model||''))+row('BIOS',si.bios)+row('Allumé depuis',si.uptime)+row('Utilisateur',si.user)+'</table>';
    r+='<h2>Protection</h2><table>'+row('Antivirus',sec.otherAV?(sec.otherAVName||'autre antivirus'):(sec.defEnabled?'Windows Defender actif':'Windows Defender désactivé'))+row('Âge des signatures',sec.defSigAge>=0?sec.defSigAge+' jour(s)':'--')+row('Pare-feu',sec.fwOk?'activé':'désactivé')+row('Contrôle des comptes',sec.uacOk===false?'désactivé':'activé')+row('SmartScreen',sec.ssOk===false?'désactivé':'activé')+'</table>';
    r+='<h2>Disques</h2><table>'+(((h.disks||{}).disks)||[]).map(d=>row(d.name+' ('+d.type+', '+d.size+')','Santé '+d.label+' · '+d.pct+' %'+(d.temp!=null?' · '+d.temp+' °C':'')+(d.hours!=null?' · '+d.hours+' h':''))).join('')+(dk.drives||[]).map(x=>row('Lecteur '+x.letter,x.free+' libres sur '+x.total+' ('+x.pct+' % utilisé)')).join('')+'</table>';
    if((h.battery||{}).present)r+='<h2>Batterie</h2><table>'+row('Santé',h.battery.health!=null?h.battery.health+' %':'--')+row('Cycles',h.battery.cycles)+'</table>';
    r+='<h2>Entretien</h2><table>'+row('Score OptiPC',an.score!=null?an.score+'/100':'--')+row('Fichiers inutiles',an.total)+row('Démarrage',(h.boot||{}).lastSec?fmtSec(h.boot.lastSec):'--')+'</table>';
    r+='<p style="margin-top:8mm;font-size:9pt;color:#666">SecureeTech · secureetech.com · 05 54 54 23 43</p>';
    $('report').innerHTML=r;
    loading(false);
    setTimeout(()=>window.print(),200);
    addLog('Rapport technicien créé');
  }catch(e){ loading(false); toast('Rapport impossible','err'); }
}

/* ── Rappel par un technicien ──────────────────────────────────────── */
function openCallback(){ $('cb-msg').textContent=''; $('cb-ov').classList.add('show'); setTimeout(()=>{ const p=$('cb-prenom'); if(p)p.focus(); },80); }
function closeCallback(){ $('cb-ov').classList.remove('show'); }
async function sendCallback(){
  const prenom=$('cb-prenom').value.trim(), telephone=$('cb-tel').value.trim(), sujet=$('cb-sujet').value, m=$('cb-msg'), b=$('cb-go');
  if(!prenom){ m.style.color='var(--red)'; m.textContent='Indiquez votre prénom.'; return; }
  if(telephone.replace(/\D/g,'').length<9){ m.style.color='var(--red)'; m.textContent='Indiquez un numéro de téléphone valide.'; return; }
  b.disabled=true; b.textContent='Envoi…';
  try{ const r=await API.post('/api/callback',{prenom,telephone,sujet},45000); m.style.color=r.ok?'var(--green)':'var(--red)'; m.textContent=r.msg||''; if(r.ok){ addLog('Demande de rappel envoyée'); setTimeout(closeCallback,2500); } }
  catch(e){ m.style.color='var(--red)'; m.textContent='Envoi impossible. Appelez le 05 54 54 23 43.'; }
  b.disabled=false; b.textContent='Envoyer ma demande';
}

/* ── Gratuit / Premium : affichage ─────────────────────────────────── */
function _setFreeUI(){
  const tp=$('tb-prem'); if(tp){ tp.classList.remove('is-on'); tp.querySelector('span').textContent='Passer en Premium'; tp.onclick=openPremium; }
  const t=$('sb-prem-title'); if(t)t.textContent='OptiPC Premium';
  const de=$('sb-prem-desc'); if(de)de.textContent='Nettoyage automatique chaque semaine, mises à jour des logiciels, aucune limite.';
  const spp=$('sb-prem-price'); if(spp)spp.style.display='';
  const ba=$('btn-activate-pro'); if(ba){ ba.style.display=''; ba.textContent='Passer en Premium'; }
  const pb=$('prem-banner'); if(pb)pb.style.display='';
  const pt=$('pb-trial'); if(pt)pt.style.display=_trialAvailable()?'':'none';
  const hp=$('hist-prem'); if(hp)hp.style.display='';
  const label=$('lic-plan-label'); if(label){ label.textContent='Version gratuite'; label.style.color='var(--text)'; }
  const sub=$('lic-plan-sub'); if(sub)sub.textContent='Fonctionnalités limitées';
  const bf=$('btn-lic-free'), bp=$('btn-lic-pro'); if(bf)bf.classList.add('on'); if(bp)bp.classList.remove('on');
  const az=$('lic-activate-zone'); if(az)az.style.display=''; const pz=$('lic-pro-zone'); if(pz)pz.style.display='none';
  document.querySelectorAll('.badge-pro,.prem-badge').forEach(b=>b.style.display='');
  renderPlanCompare();
  if(window._lastScanData){ _qcSel=null; renderQuickClean(); }
  if(_scanR){ buildIssues(); renderIssues(); }
  if(_space){ _spRendered=null; renderSpace(); }
}
// Date de fin de la licence (26/10/2026) : ISO (2027-10-26T...) ou JJ/MM/AAAA selon la machine
function finLicence(s){ s=String(s||'').trim(); if(!s) return null; let m=s.match(/^(\d{4})-(\d{2})-(\d{2})/); if(m) return new Date(+m[1],+m[2]-1,+m[3],12); m=s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/); if(m) return new Date(+m[3],+m[2]-1,+m[1],12); const d=new Date(s); return isNaN(d)?null:d; }
function joursRestants(f){ const t=new Date(); t.setHours(12,0,0,0); return Math.round((f-t)/864e5); }
function _setProUI(info){
  const trial=info&&info.trial;
  const tp=$('tb-prem'); if(tp){ tp.classList.add('is-on'); tp.querySelector('span').textContent=trial?'Essai Premium':'Premium actif'; tp.onclick=()=>goSec('params'); }
  const t=$('sb-prem-title'); if(t)t.textContent=trial?'Essai Premium en cours':'Premium actif';
  const spp=$('sb-prem-price'); if(spp)spp.style.display=trial?'':'none';
  const de=$('sb-prem-desc'); if(de){ let s='Toutes les fonctions sont débloquées. Merci de votre confiance !'; if(trial&&info.expires_at){ try{ s='Votre essai se termine le '+new Date(info.expires_at+'T12:00:00').toLocaleDateString('fr-FR',{day:'numeric',month:'long'})+'.'; }catch(e){} } de.textContent=s; }
  const ba=$('btn-activate-pro'); if(ba){ if(trial){ ba.style.display=''; ba.textContent='Garder Premium · 99,80 €/an'; ba.onclick=openBuyPage; } else ba.style.display='none'; }
  const pb=$('prem-banner'); if(pb)pb.style.display='none';
  const hp=$('hist-prem'); if(hp)hp.style.display='none';
  const label=$('lic-plan-label'); if(label){ label.textContent=trial?'Essai Premium gratuit':'✅ Premium actif'; label.style.color='var(--acc-text)'; }
  const sub=$('lic-plan-sub');
  if(sub&&info){
    if(trial&&info.expires_at){ let fin=info.expires_at; try{ fin=new Date(info.expires_at+'T12:00:00').toLocaleDateString('fr-FR',{day:'numeric',month:'long'}); }catch(e){} sub.textContent='Se termine le '+fin; }
    else if(finLicence(info.period_end)){ const f=finLicence(info.period_end), j=joursRestants(f); sub.textContent=(j>=0?'Expire le ':'Expirée le ')+f.toLocaleDateString('fr-FR',{day:'numeric',month:'long',year:'numeric'})+(j>=0?' · '+j+' jour'+(j>1?'s':'')+' restant'+(j>1?'s':''):''); sub.style.color=j<=30?'#e67e00':''; }
    else if(info.days_active!=null&&info.days_active>=0){ const d=info.days_active; sub.textContent='Actif depuis '+(d===0?'aujourd’hui':d+' jour'+(d>1?'s':'')); }
    else sub.textContent='Licence active';
  }
  const bf=$('btn-lic-free'), bp=$('btn-lic-pro'); if(bf)bf.classList.remove('on'); if(bp)bp.classList.add('on');
  const az=$('lic-activate-zone'); if(az)az.style.display='none';
  const pz=$('lic-pro-zone');
  if(pz){ pz.style.display=''; const det=$('lic-pro-details');
    if(det&&info){ let h=''; if(info.activated_at){ const d=new Date(info.activated_at); h+='<div>Activé le <b style="color:var(--text)">'+d.toLocaleDateString('fr-FR',{day:'2-digit',month:'long',year:'numeric'})+'</b></div>'; } { const f=finLicence(info.period_end); if(f){ const j=joursRestants(f); h+='<div>Expire le <b style="color:var(--text)">'+f.toLocaleDateString('fr-FR',{day:'2-digit',month:'long',year:'numeric'})+'</b>'+(j>=0?' · <b style="color:'+(j<=30?'#e67e00':'var(--acc-text)')+'">'+j+' jour'+(j>1?'s':'')+' restant'+(j>1?'s':'')+'</b>':' · <b style="color:#c62828">expirée</b>')+'</div>'; } } if(info.key_display)h+='<div>Clé : <span style="font-family:Consolas,monospace;color:var(--acc-text)">'+esc(info.key_display)+'</span></div>'; det.innerHTML=h; } }
  document.querySelectorAll('.badge-pro').forEach(b=>b.style.display='none');
  renderPlanCompare();
  if(window._lastScanData){ _qcSel=null; renderQuickClean(); }
  if(_scanR){ buildIssues(); renderIssues(); }
  if(_space){ _spRendered=null; renderSpace(); }
}
function renderPlanCompare(){
  const el=$('plan-compare'); if(!el)return;
  const free=[['Analyse complète de l’ordinateur',1],['Nettoyage de la moitié des fichiers inutiles',1],['Espace disque : 500 Mo par nettoyage',1],['État des disques et liste des appareils du réseau',1],['3 désinstallations par mois, 2 programmes retirés du démarrage',1],['Détection des virus et logiciels espions',1],['Suppression et quarantaine des menaces',0],['Nettoyage avancé, Windows.old et registre',0],['Nettoyage automatique planifié',0],['Mises à jour des logiciels en un clic',0],['Assistance téléphonique prioritaire',0]];
  const prem=[['Tout ce que contient la version gratuite',0],['Supprime réellement les menaces détectées',1],['Quarantaine réversible : zéro risque de fausse alerte',1],['Espace disque sans limite + nettoyage avancé',1],['Nettoyage automatique : PC propre sans y penser',1],['Mises à jour des logiciels en un clic',1],['Rapport technicien en PDF',1],['Assistance téléphonique prioritaire au '+EDITEUR.tel,1]];
  el.innerHTML='<div class="cmp-wrap">'
    +'<div class="cmp-col"><div class="cmp-head">Gratuit'+(_isPro?'':' <span class="cmp-badge-cur">Votre version</span>')+'</div><div class="cmp-sub">Pour voir ce qui ne va pas et faire le ménage de base.</div><div class="cmp-price" style="color:var(--dim)">0 €<small>Sans limite de durée, sans publicité</small></div><ul class="cmp-list">'+free.map(f=>'<li class="cmp-li'+(f[1]?'':' no')+'"><span>'+(f[1]?'✅':'🔒')+'</span><span>'+esc(f[0])+'</span></li>').join('')+'</ul>'
    +(_isPro?'<button class="cmp-cta ghost" onclick="revokeLicense()">Revenir à la version gratuite</button>':'<button class="cmp-cta ghost" disabled>Version actuelle</button>')+'</div>'
    +'<div class="cmp-col pro"><div class="cmp-ribbon">⭐ Recommandé</div><div class="cmp-head">⭐ Premium'+(_isPro?' <span class="cmp-badge-cur">Votre version</span>':'')+'</div><div class="cmp-sub">Pour qu’OptiPC répare vraiment, tout seul, et que quelqu’un décroche quand vous appelez.</div>'
    +'<div class="plans"><div class="plan"><b>'+PRICES.month+'</b><span>par mois</span></div><div class="plan best"><b>'+PRICES.year+'</b><span>par an</span></div></div>'
    +'<ul class="cmp-list">'+prem.map(f=>'<li class="cmp-li'+(f[1]?' hot':'')+'"><span>'+(f[1]?'⭐':'✅')+'</span><span>'+esc(f[0])+'</span></li>').join('')+'</ul>'
    +(_isPro?'<button class="cmp-cta buy" disabled>✅ Premium actif</button>':'<button class="cmp-cta buy" onclick="openBuyPage()">Passer en Premium</button>'+(_trialAvailable()?'<button class="cmp-cta ghost" onclick="openTrial()">Essayer gratuitement 5 jours</button>':'')+'<button class="cmp-cta ghost" onclick="goActivate()">J’ai déjà une clé</button>')
    +'<div class="cmp-foot">'+(_isPro?'Merci de votre confiance.':'Une question ? Appelez le <b>'+EDITEUR.tel+'</b>, un technicien répond en français.')+'</div></div></div>';
  const ab=$('about-editeur');
  if(ab)ab.innerHTML='Édité par <b>'+esc(EDITEUR.societe)+'</b><br>'+(_edAdresse()?esc(_edAdresse())+'<br>':'')+'© 2026 '+esc(EDITEUR.societe)+' — marque '+esc(EDITEUR.marque);
}
function showLicPro(){ if(_isPro){ toast('Premium est déjà actif','info'); return; } const k=$('lic-key'); if(k){ k.focus(); } showProGate('Entrez votre clé Premium dans Paramètres, ou appelez-nous au 05 54 54 23 43 pour en obtenir une.'); }
function showWelcomeOnce(){ if(_welcomeAlreadyShown)return; const ph=($('hero')||{dataset:{}}).dataset.phase; if(ph&&ph!=='idle'&&ph!=='fixed')return; _welcomeAlreadyShown=true; try{ if(localStorage.getItem('optipc_welcome2'))return; localStorage.setItem('optipc_welcome2','1'); }catch(e){} const ov=$('welcome-ov'); if(ov)ov.classList.add('show'); }
function closeWelcome(){ const ov=$('welcome-ov'); if(ov){ ov.classList.remove('show'); ov.style.display=''; } }

/* ── Démarrage de l'interface ──────────────────────────────────────── */
window.onload=async()=>{
  applyTheme(); syncSettingsUI();
  loadPersistedLogs();
  try{ await loadProStatus(); }catch(e){}
  setTimeout(async()=>{ try{ const h=await API.post('/api/license/heartbeat',{force:false},30000); if(h&&h.revoked){ _isPro=false; _setFreeUI(); toast(h.message||'Licence désactivée','err'); } else if(h&&h.warning){ toast(h.warning,'info'); } }catch(e){} },8000);
  let ok=true;
  try{ const c=await API.get('/api/consent',30000); ok=!!(c&&c.accepted&&c.version===CONSENT_VERSION); }catch(e){ ok=true; }
  if(!ok)setTimeout(showConsentGate,300); else if(!_isPro)setTimeout(()=>{ if(_trialAvailable())firstLaunchOffer(); else showWelcomeOnce(); },2500);
  pollPerf(); loadScheduleStatus(); loadNotifSetting();
  loadHomeStatus();
  // Recherche silencieuse d'une mise à jour à chaque ouverture : proposée si disponible.
  setTimeout(async()=>{ const u=await checkUpdate(false); if(u)showUpdatePrompt(u); },4000);
  setInterval(()=>checkUpdate(false),6*3600*1000);
  setInterval(()=>{ if(!document.hidden)loadCleanLog(); },180000);
  setInterval(()=>{ if(!document.hidden)loadSecStatusQuiet(); },600000);
  try{ const v=await API.get('/api/version',8000); if(v&&v.version)document.querySelectorAll('.opti-ver').forEach(e=>e.textContent=v.version); }catch(e){}
};

/* ── Essai Premium 5 jours : automatique, sans formulaire (depuis la 2.1) ── */
function openTrial(){
  if(!_trialAvailable()){ openBuyPage(); return; }
  $('trial-form-zone').style.display=''; $('trial-ok-zone').style.display='none';
  $('trial-err').style.display='none';
  $('trial-ov').classList.add('show');
  startTrial();
}
async function startTrial(){
  const btn=$('trial-go'), wait=$('trial-wait');
  btn.style.display='none'; if(wait)wait.style.display='';
  $('trial-err').style.display='none';
  try{
    const d=await API.post('/api/license/trial',{},90000);
    if(d&&d.ok){
      try{ localStorage.setItem('optipc_trial_used','1'); }catch(e){}
      _trialUsed=true; _isPro=true; _setProUI(d);
      let fin=''; if(d.expires_at){ try{ fin=new Date(d.expires_at+'T12:00:00').toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long'}); }catch(e){} }
      $('trial-ok-msg').innerHTML='Toutes les fonctions Premium sont débloquées'+(fin?' jusqu’au <strong style="color:var(--text)">'+fin+'</strong>':' pendant 5 jours')+'.<br>Lancez l’analyse et cliquez sur <b>BOOSTER MON PC</b> : tout sera nettoyé, sans limite.';
      $('trial-form-zone').style.display='none'; $('trial-ok-zone').style.display='';
      addLog('Essai Premium gratuit activé');
      if(_scanR){ buildIssues(); renderIssues(); }
    } else {
      if(d&&d.already){ try{ localStorage.setItem('optipc_trial_used','1'); }catch(e){} _trialUsed=true; _syncTrialButtons(); }
      _trialErr((d&&d.message)||"L'essai n'a pas pu démarrer. Appelez le 05 54 54 23 43.");
      if(!(d&&d.already))btn.style.display='';
    }
  }catch(e){ _trialErr("L'essai n'a pas pu démarrer. Vérifiez votre connexion internet."); btn.style.display=''; }
  if(wait)wait.style.display='none';
}
function firstLaunchOffer(){
  try{ if(localStorage.getItem('optipc_offer_shown'))return; }catch(e){}
  if(_isPro||!_trialAvailable())return;
  const ph=($('hero')||{dataset:{}}).dataset.phase; if(ph&&ph!=='idle')return;
  try{ localStorage.setItem('optipc_offer_shown','1'); localStorage.setItem('optipc_welcome2','1'); }catch(e){}
  _welcomeAlreadyShown=true; openTrial();
}

/* ── Navigateurs détournés ─────────────────────────────────────────── */
function renderBrowserHijack(d){
  const el=$('brw-list'); if(!el)return;
  const it=(d&&d.items)||[], crit=it.filter(x=>x.level==='crit');
  window._brw=d;
  if(!it.length){ el.innerHTML='<div class="note green">Aucun détournement : vos navigateurs sont sains.</div>'; return; }
  el.innerHTML=(crit.length?'<div class="note red" style="margin-bottom:10px"><b>'+crit.length+' détournement'+(crit.length>1?'s':'')+' trouvé'+(crit.length>1?'s':'')+'.</b> '+(_isPro?'Cliquez sur « Réparer en un clic ».':'La réparation en un clic est incluse dans Premium. <a href="#" onclick="openPremium();return false" style="font-weight:800">Débloquer</a>'+(_trialAvailable()?' · <a href="#" onclick="openTrial();return false" style="font-weight:800">Essai gratuit 5 jours</a>':''))+'</div>':'')
    +'<div class="kv">'+it.map(x=>'<div><b>'+esc(x.browser)+'</b> · '+esc(x.title)+'</div><div style="color:'+(x.level==='crit'?'var(--red)':'var(--orange)')+'">'+esc(x.detail||'—')+'</div>').join('')+'</div>';
}
async function loadBrowserHijack(){
  const el=$('brw-list'); if(el)el.innerHTML=spinner('Vérification des navigateurs…');
  try{ const d=await API.get('/api/browsers/hijack',90000); renderBrowserHijack(d); return d; }catch(e){ if(el)el.innerHTML='<div class="empty-note" style="color:var(--red)">Vérification impossible.</div>'; }
}
function repairBrowsers(){
  if(!_isPro){ showProGate('Réparez vos navigateurs détournés en un clic avec Premium : page de démarrage, moteur de recherche, « Géré par votre organisation », raccourcis piégés.'); return; }
  showConfirm('Réparer les navigateurs ?','Chrome, Edge, Brave et Firefox vont être fermés quelques secondes. Vos favoris, mots de passe et historique ne sont pas touchés. Chrome peut ensuite afficher « paramètres réinitialisés » : c’est normal.',async()=>{
    loading(true,'Réparation des navigateurs…');
    try{ const r=await API.post('/api/browsers/repair',{},180000); loading(false); toast(r.msg||'Terminé',r.ok?'ok':'err'); addLog('Navigateurs : '+(r.msg||'')); loadBrowserHijack(); }
    catch(e){ loading(false); toast('Erreur pendant la réparation','err'); }
  });
}

/* ── Mise à jour proposée à l'ouverture ───────────────────────────── */
function showUpdatePrompt(u){
  if(!u||!u.version)return;
  try{ if(sessionStorage.getItem('optipc_upd_asked')===u.version)return; sessionStorage.setItem('optipc_upd_asked',u.version); }catch(e){}
  showConfirm('🎉 Nouvelle version d’OptiPC : '+esc(u.version),(u.notes?esc(u.notes)+'<br><br>':'')+'L’installation prend moins d’une minute. OptiPC se ferme puis redémarre tout seul, vos réglages et votre licence sont conservés.',()=>installUpdate());
  setTimeout(()=>{ const ok=document.getElementById('_mokbtn'); if(ok)ok.textContent='Installer maintenant'; const c=document.getElementById('_mcancelbtn'); if(c)c.textContent='Plus tard'; },30);
}
