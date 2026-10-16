const OPTI_TOKEN='';
async function _req(url,opt,ms){
  opt=Object.assign({},opt||{});opt.headers=Object.assign({},opt.headers||{},{'X-OptiPC-Token':OPTI_TOKEN});
  const c=new AbortController();
  const t=setTimeout(()=>{try{c.abort()}catch(e){}},ms);
  try{
    const r=await fetch(url,Object.assign({signal:c.signal},opt));
    clearTimeout(t);
    if(r.status===403&&String(url).indexOf('/api/')===0){_optiReloadSoon();}
    if(!r.ok)throw new Error('HTTP '+r.status);
    return await r.json();
  }catch(e){clearTimeout(t);if(e&&e.name==='TypeError')_optiWatchServer();throw e;}
}
/* Le moteur d'OptiPC a redemarre (mise a jour, relance) : la page affichee est
   perimee. On attend qu'il reponde de nouveau, puis on recharge la page. */
let _optiReloading=false,_optiWatch=null;
function _optiReloadSoon(){
  if(_optiReloading)return;_optiReloading=true;
  try{toast('Mise à jour d\u2019OptiPC appliquée : rechargement…','info');}catch(e){}
  setTimeout(()=>{try{location.reload();}catch(e){}},1200);
}
function _optiWatchServer(){
  if(_optiWatch||_optiReloading)return;
  _optiWatch=setInterval(async()=>{
    try{
      const r=await fetch('/api/version',{headers:{'X-OptiPC-Token':OPTI_TOKEN},cache:'no-store'});
      if(r.status===403){clearInterval(_optiWatch);_optiReloadSoon();}
      else if(r.ok){clearInterval(_optiWatch);_optiWatch=null;}
    }catch(e){}
  },2500);
}
const API={
  async get(p,ms){return _req(p,{method:'GET'},ms||30000)},
  async post(p,d,ms){return _req(p,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)},ms||180000)}
};
let _cleanItems=[],_appsData=[],_regItems=[],_isPro=false,_logs=[];

/* ════════════════════════════════════════════════════════════════════
   IDENTITÉ DE L'ÉDITEUR ET TARIF — MODIFIEZ UNIQUEMENT CE BLOC.
   Il alimente les conditions générales, la fenêtre « À propos »
   et l'argumentaire commercial Pro.
   ════════════════════════════════════════════════════════════════════ */
const EDITEUR={
  societe   : 'H2OCONSULTING - FZCO',
  forme     : 'société de zone franche (FZCO) de droit émirien',
  marque    : 'SecureeTech',
  /* Donnees personnelles et coordonnees detaillees retirees le 15/09/2026.
     Chaque champ laisse vide ci-dessous est AUTOMATIQUEMENT omis dans les
     CGU, le contrat de licence, la politique de confidentialite et la
     fenetre « A propos » : aucune mention vide, aucune virgule orpheline.
     Pour en reafficher un, il suffit de le renseigner ici. */
  licence   : '',
  autorite  : '',
  registre  : '',
  trn       : '',
  gerant    : '',
  ville     : 'Dubaï, Émirats arabes unis',
  adresse   : '',            /* ← laisser vide : la ville ci-dessus sert alors d'adresse */
  repUE     : '',            /* ← représentant RGPD dans l'UE (article 27). Voir COMPILATION.md */
  tel       : '05 54 54 23 43',
  mail      : 'optipc@secureetech.com',
  site      : 'secureetech.com',
  versionCG : '1.1',
  dateCG    : '14 septembre 2026',
  prixPro   : '',            /* ← ex. '49,90 €'. Si vide, l'app invite simplement à appeler. */
  dureePro  : 'Abonnement, 1 ordinateur'
};
function _edAdresse(){ return EDITEUR.adresse ? EDITEUR.adresse : EDITEUR.ville; }
/* Suite de l'identite de l'editeur (forme juridique, registre, TRN, siege).
   Les champs vides du bloc EDITEUR sont purement et simplement omis. */
function _edIdentiteSuite(){
  const p=[];
  if(EDITEUR.forme)    p.push(EDITEUR.forme);
  if(EDITEUR.registre) p.push(EDITEUR.registre);
  if(EDITEUR.trn)      p.push('numéro d’enregistrement fiscal (TRN) '+EDITEUR.trn);
  const a=_edAdresse();
  if(a) p.push('siège social : '+a);
  return p.length ? ', '+p.join(', ') : '';
}
function _edLigne(label,val){ return val ? '&bull; '+label+' : '+val+'<br>' : ''; }
function _edRepUE(){
  return EDITEUR.repUE
    ? EDITEUR.repUE
    : 'représentant en cours de désignation — écrivez à ' + EDITEUR.mail;
}

/* Page de vente : c'est ici qu'arrivent les clients qui veulent payer. */
const BUY_URL='https://www.secureetech.com/optipc/';
/* Version des documents juridiques. En l'incrementant, tous les clients
   devront accepter a nouveau au prochain lancement. */
const CONSENT_VERSION='1.0';

async function openBuyPage(){
  try{
    const r=await API.post('/api/openurl',{url:BUY_URL},15000);
    if(r&&r.success){ toast('Page d\u2019achat ouverte dans votre navigateur','ok'); return; }
  }catch(e){}
  try{ window.open(BUY_URL,'_blank'); }catch(e){ toast('Rendez-vous sur secureetech.com/optipc','info'); }
}
function _edPrix(){ return EDITEUR.prixPro ? EDITEUR.prixPro : ''; }
const SVC_INFO={
  DiagTrack:{n:'Télémétrie Windows',d:'Envoie vos données à Microsoft'},
  dmwappushservice:{n:'Collecte de données Microsoft',d:'Remontée d infos vers Microsoft'},
  XblAuthManager:{n:'Xbox - Connexion',d:'Inutile si vous n utilisez pas Xbox'},
  XblGameSave:{n:'Xbox - Sauvegardes',d:'Sauvegarde cloud Xbox inutile'},
  XboxNetApiSvc:{n:'Xbox - Réseau',d:'Fonctions réseau Xbox inutiles'},
  XboxGipSvc:{n:'Xbox - Manette',d:'Service manette Xbox inutile'},
  WMPNetworkSvc:{n:'Windows Media Player Réseau',d:'Partage multimédia inutile'},
  Fax:{n:'Service Fax',d:'Envoi/réception de fax (obsolète)'},
  RemoteRegistry:{n:'Registre à distance',d:'Accès externe au registre — risque sécurité'},
  MapsBroker:{n:'Téléchargement de cartes',d:'Mise à jour cartes hors-ligne inutile'},
  RetailDemo:{n:'Mode démo magasin',d:'Service de démonstration en magasin'},
  WpcMonSvc:{n:'Contrôle parental',d:'Inutile si pas de compte enfant'},
  lfsvc:{n:'Géolocalisation',d:'Service de localisation Windows'},
  SharedAccess:{n:'Partage de connexion',d:'Partage internet via ce PC'},
  SysMain:{n:'Préchargement applications',d:'Consomme RAM pour anticiper les lancements'},
  WSearch:{n:'Indexation et recherche',d:'Indexe vos fichiers — ralentit le disque'},
  Spooler:{n:'File d impression',d:'Désactivez si pas d imprimante'},
  TabletInputService:{n:'Service tablette tactile',d:'Inutile sur PC de bureau'},
  WbioSrvc:{n:'Biométrie Windows',d:'Fingerprint/visage — inutile si non utilisé'},
  wisvc:{n:'Programme Insider Windows',d:'Mises à jour beta de Windows'},
  diagnosticshub:{n:'Hub de diagnostics',d:'Collecte de données performances'},
  DPS:{n:'Service de stratégie diagnostic',d:'Surveillance erreurs — peut être désactivé'},
};

// ── UTILS ────────────────────────────────────────────────────────────────────
function loading(s,m){
  m=m||'Traitement...';
  var el=document.getElementById('_loadbar');
  if(s){
    if(!el){
      el=document.createElement('div');
      el.id='_loadbar';
      el.style.cssText='position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:var(--card);border:1px solid rgba(var(--acc-rgb),.4);border-radius:10px;padding:10px 20px;display:flex;align-items:center;gap:10px;z-index:9997;font-size:12px;color:var(--text);box-shadow:0 8px 24px rgba(0,0,0,.5)';
      document.body.appendChild(el);
    }
    el.innerHTML='<div class="spin" style="width:16px;height:16px;border-width:2px"></div><span>'+m+'</span>';
    el.style.display='flex';
    el.style.opacity='1';
    if(window._loadWatch)clearTimeout(window._loadWatch);
    window._loadWatch=setTimeout(function(){loading(false);toast("L'operation prend trop de temps - reessayez",'err');},90000);
  } else {
    if(window._loadWatch){clearTimeout(window._loadWatch);window._loadWatch=null;}
    if(el){
      el.style.opacity='0';
      el.style.transition='opacity .3s';
      setTimeout(function(){if(el&&el.parentNode)el.remove();},300);
    }
  }
}
function toast(m,t='ok'){const el=document.createElement('div');el.className='toast t-'+t;el.textContent=m;document.getElementById('toasts').appendChild(el);setTimeout(()=>{el.style.opacity='0';el.style.transition='opacity .3s';setTimeout(()=>el.remove(),300)},3200);}
function showSuccess(t,s){const o=document.getElementById('success-ov');document.getElementById('success-title').textContent=t;document.getElementById('success-sub').textContent=s;o.style.display='flex';setTimeout(()=>o.classList.add('show'),50);setTimeout(()=>{o.classList.remove('show');setTimeout(()=>o.style.display='none',400)},3000);}
function confirm2(t,m,ok){document.getElementById('modal-title').textContent=t;document.getElementById('modal-msg').textContent=m;document.getElementById('modal').style.display='flex';document.getElementById('modal-ok').onclick=()=>{closeModal();ok()};}
function closeModal(){document.getElementById('modal').style.display='none';}
function addLog(m){
  const n=new Date().toLocaleTimeString('fr-FR');
  const entry='['+n+'] '+m;
  _logs.unshift(entry);
  // Persister dans localStorage pour survivre au rechargement
  try{
    const stored=JSON.parse(localStorage.getItem('optipc_logs')||'[]');
    stored.unshift({t:Date.now(),m:entry});
    localStorage.setItem('optipc_logs',JSON.stringify(stored.slice(0,200)));
  }catch(e){}
  renderActivityLog();
}
function renderActivityLog(){
  const el=document.getElementById('activity-log');
  if(!el)return;
  el.innerHTML=_logs.slice(0,50).map(l=>{
    const isOk=l.includes('libér')||l.includes('optimis')||l.includes('activé')||l.includes('terminé');
    const isErr=l.includes('Erreur')||l.includes('échec');
    const color=isErr?'var(--red)':isOk?'var(--green)':'var(--dim)';
    return '<div style="padding:2px 0;border-bottom:1px solid rgba(var(--inv-rgb),.03);color:'+color+'">'+l+'</div>';
  }).join('');
}
function loadPersistedLogs(){
  try{
    const stored=JSON.parse(localStorage.getItem('optipc_logs')||'[]');
    _logs=stored.map(e=>e.m);
    renderActivityLog();
  }catch(e){}
}
function clearLogs(){_logs=[];try{localStorage.removeItem('optipc_logs');}catch(e){}document.getElementById('activity-log').innerHTML='';}
function fmtSz(b){if(!b||b<=0)return'0 B';if(b>=1073741824)return(b/1073741824).toFixed(1)+' GB';if(b>=1048576)return Math.round(b/1048576)+' MB';if(b>=1024)return Math.round(b/1024)+' KB';return b+' B';}
function escS(s){return(s||'').replace(/\\/g,'\\\\').replace(/'/g,"\\'")}

// ── NAVIGATION ───────────────────────────────────────────────────────────────
// Son de navigation
let _soundEnabled=true;
function _playNav(){
  if(!_soundEnabled)return;
  try{
    const ac=new(window.AudioContext||window.webkitAudioContext)();
    const o=ac.createOscillator();
    const g=ac.createGain();
    o.connect(g);g.connect(ac.destination);
    o.frequency.setValueAtTime(660,ac.currentTime);
    o.frequency.exponentialRampToValueAtTime(880,ac.currentTime+0.06);
    g.gain.setValueAtTime(0.08,ac.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001,ac.currentTime+0.12);
    o.start(ac.currentTime);o.stop(ac.currentTime+0.12);
  }catch(e){}
}
function toggleSound(){
  _soundEnabled=!_soundEnabled;
  const btn=document.getElementById('btn-sound');
  if(btn)btn.textContent=_soundEnabled?'🔊':'🔇';
  localStorage.setItem('optipc_sound',_soundEnabled?'1':'0');
}
function showSec(name,el){
  _playNav();
  document.querySelectorAll('.sec').forEach(s=>s.classList.remove('active'));
  document.querySelectorAll('.sb-item').forEach(n=>n.classList.remove('active'));
  const sec=document.getElementById('sec-'+name);if(sec)sec.classList.add('active');
  if(el)el.classList.add('active');
  if(name==='speedup'){loadRam();loadPowerPlans();loadStartup();loadServices();}
  if(name==='protect'){loadSecStatus();loadAccessStatus();}
  if(name==='apps'){loadApps();}
  if(name==='monpc'){loadSysInfo();loadDiskInfo();}
  if(name==='params'){renderPlanCompare();}
  if(name==='params'){loadScheduleStatus();loadQuarantine();loadNotifSetting();}
}

// ── CARE ─────────────────────────────────────────────────────────────────────
let _careMode='auto',_scanning=false;
function setMode(m){
  _careMode=m;
  document.getElementById('mode-auto').classList.toggle('active',m==='auto');
  document.getElementById('mode-manual').classList.toggle('active',m==='manual');
  document.getElementById('checklist').style.display=m==='manual'?'grid':'none';
}
function toggleCi(inp){inp.closest('.ci').classList.toggle('checked',inp.checked);}
async function doCare(){
  if(_scanning)return;_scanning=true;
  const btn=document.getElementById('scan-main-btn');
  const ring=document.getElementById('scan-ring');
  const txt=document.getElementById('scan-txt');
  const sub=document.getElementById('scan-sub');
  if(btn){btn.disabled=true;btn.textContent='Analyse...';}
  if(txt)txt.textContent='...';if(sub)sub.textContent='Patientez';
  if(ring)ring.style.borderColor='rgba(var(--acc-rgb),.8)';
  document.getElementById('top-status-txt').textContent='Analyse en cours...';
  loading(true,'Analyse de votre PC...');
  try{
    const d=await API.get('/api/analyze');
    loading(false);
    _cleanItems=d.items||[];
    window._lastScanData=d;
    document.getElementById('care-idle').style.display='none';
    document.getElementById('care-results').style.display='flex';
    document.getElementById('stat-total').textContent=d.total||'0 B';
    document.getElementById('stat-procs').textContent=(d.heavyCount||0);
    loadRam();loadDiskInfo();
    buildRecs(d);
    document.getElementById('top-status-txt').textContent=d.score>=80?'Tout va bien':'Optimisation recommandee';
    addLog('Analyse: score '+(d.score||0));
    toast('Analyse terminée','ok');
  }catch(e){loading(false);toast("Erreur d'analyse",'err');if(txt)txt.textContent='SCAN';if(sub)sub.textContent='Cliquez pour analyser';}
  if(btn){btn.disabled=false;btn.innerHTML='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg> Analyser maintenant';}
  _scanning=false;
}
function resetCare(){
  document.getElementById('care-idle').style.display='flex';
  document.getElementById('care-results').style.display='none';
  document.getElementById('scan-txt').textContent='SCAN';
  document.getElementById('scan-sub').textContent='Cliquez pour analyser';
}
function buildRecs(d){
  const items=d.items||[];const el=document.getElementById('rec-list');if(!el)return;
  const recs=[];
  const bItems=items.filter(i=>i.cat==='Navigateurs'&&i.size>0);
  const sB=bItems.reduce((s,i)=>s+i.size,0);
  if(sB>0)recs.push({id:'browser',n:'Nettoyer cache navigateurs',det:fmtSz(sB)+' récupérables',col:'var(--orange)',pro:false});
  const wItems=items.filter(i=>i.cat==='Windows'&&i.size>0);
  const sW=wItems.reduce((s,i)=>s+i.size,0);
  if(sW>0)recs.push({id:'windows',n:'Fichiers temporaires Windows',det:fmtSz(sW)+' à supprimer',col:'#E8650C',pro:false});
  const aItems=items.filter(i=>i.cat==='Avance'&&i.size>0);
  const sA=aItems.reduce((s,i)=>s+i.size,0);
  if(sA>0)recs.push({id:'avance',n:'Nettoyage avancé',det:fmtSz(sA)+' disponibles',col:'var(--purple)',pro:true});
  el.innerHTML=recs.map(r=>{
    const locked=r.pro&&!_isPro;
    const nameLbl=locked?`${r.n} <span style="font-size:9px;background:linear-gradient(135deg,var(--purple2),var(--purple2));color:#fff;padding:1px 6px;border-radius:4px;font-weight:700;vertical-align:middle">PREMIUM</span>`:r.n;
    const btnCls=locked?'rec-action ra-pro':'rec-action ra-go';
    const btnLbl=locked?'🔒 Premium':'Corriger';
    const btnAct=locked?`ifPro(()=>execRec('${r.id}'),'Fonction Premium')`:`execRec('${r.id}')`;
    return `<div class="rec-item"><div class="rec-ico" style="background:${r.col}22"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${r.col}" stroke-width="2"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg></div><div class="rec-body"><div class="rec-name">${nameLbl}</div><div class="rec-det">${r.det}</div></div><button class="${btnCls}" onclick="${btnAct}">${btnLbl}</button></div>`;
  }).join('');
}
async function execRec(id){
  loading(true,'Nettoyage...');
  try{
    let filt;
    if(id==='browser'){ filt=i=>i.cat==='Navigateurs'; }
    else if(id==='avance'){ filt=i=>i.cat==='Avance'&&i.id!=='winold'; }
    else { filt=i=>i.cat==='Windows'; }
    const sel=_cleanItems.filter(i=>i.size>0&&filt(i)).map(i=>i.id);
    if(!sel.length){loading(false);toast('Déjà propre','info');return;}
    const r=await API.post('/api/clean',{selected:sel});
    loading(false);if(notifOn('notifClean'))showSuccess(r.cleaned+' libérés !','Nettoyage terminé');addLog('Nettoyage: '+r.cleaned);
    setTimeout(doCare,600);
  }catch(e){toast('Erreur','err');loading(false);}
}
async function doOptimize(){
  const btn=document.getElementById('optim-btn');if(btn){btn.disabled=true;btn.textContent='Optimisation...';}
  loading(true,'Optimisation...');
  try{if(!_cleanItems.length){const d=await API.get('/api/analyze');_cleanItems=d.items||[];}
    const sel=_cleanItems.filter(i=>(i.cat==='Windows'||i.cat==='Navigateurs')&&i.size>0).map(i=>i.id);
    if(sel.length){const r=await API.post('/api/clean',{selected:sel});loading(false);if(notifOn('notifClean'))showSuccess(r.cleaned+' libérés !','Optimisation terminée');addLog('Optimisation: '+r.cleaned);setTimeout(doCare,600);}
    else{loading(false);toast('PC déjà propre','ok');}
  }catch(e){toast('Erreur','err');loading(false);}
  if(btn){btn.disabled=false;btn.innerHTML='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg> Optimiser maintenant';}
}

// ── SPEED UP ─────────────────────────────────────────────────────────────────
async function loadRam(){
  try{const d=await API.get('/api/ram');
    const pct=d.pct||d.usedPct||0;
    const bar=document.getElementById('ram-bar');if(bar){bar.style.width=pct+'%';bar.style.background=pct>80?'var(--red)':pct>60?'var(--orange)':'var(--purple)';}
    const desc=document.getElementById('ram-desc');if(desc)desc.textContent=(d.freeMB||0)+' Mo libres sur '+(d.totalMB||0)+' Mo ('+pct+'% utilisée)';
    document.getElementById('stat-ram').textContent=pct+'%';
    const sb=document.getElementById('sb-cpu-pct');
  }catch(e){}
}
async function doRamOptimize(){loading(true,'Liberation RAM...');try{const r=await API.post('/api/ram/optimize',{});toast('RAM libérée','ok');addLog('RAM optimisée');loadRam();}catch(e){toast('Erreur','err');}loading(false);}
const PP_EMOJI={battery:'\uD83D\uDD0B',balance:'\u2696\uFE0F',rocket:'\uD83D\uDE80'};
const PP_LABEL={battery:'Économie d\u2019énergie',balance:'Équilibré',rocket:'Performances'};
async function loadPowerPlans(){
  const el=document.getElementById('pp-list');if(!el)return;
  el.innerHTML='<div style="color:var(--muted);font-size:11px"><span class="spin" style="width:11px;height:11px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:7px"></span>Lecture du mode actuel...</div>';
  try{
    const d=await API.get('/api/powerplan',25000);
    const plans=d.plans||[];
    if(!plans.length)throw new Error('aucun mode');
    let h=plans.map(function(p){
      const emo=PP_EMOJI[p.icon]||'';
      const lbl=PP_LABEL[p.icon]||p.name;
      return '<div class="pp-item '+(p.active?'active':'')+'" onclick="setPowerPlan(\''+p.guid+'\')">'
        +'<div class="pp-dot"></div>'
        +'<div style="flex:1"><div class="pp-name">'+emo+' '+lbl+'</div>'
        +'<div class="pp-desc">'+(p.desc||'')+'</div></div>'
        +(p.active?'<span class="pp-badge">Actif</span>':'')+'</div>';
    }).join('');
    if(d.customName){
      h+='<div style="font-size:10px;color:var(--muted);margin-top:7px;line-height:1.5">Mode actuellement actif sur ce PC : <strong style="color:var(--dim)">'+d.customName+'</strong>. Choisissez un mode ci-dessus pour le remplacer.</div>';
    }
    el.innerHTML=h;
  }catch(e){
    el.innerHTML='<div style="color:var(--red);font-size:11.5px">Lecture des modes impossible. <button class="btn-su btn-ghost" style="font-size:10px;margin-left:6px" onclick="loadPowerPlans()">Réessayer</button></div>';
  }
}
async function setPowerPlan(guid){
  loading(true,'Application du mode...');
  try{
    const r=await API.post('/api/powerplan/set',{guid},40000);
    if(r&&r.success){toast('Mode d\u2019alimentation appliqué','ok');addLog('Mode d\u2019alimentation modifié');}
    else{toast((r&&r.error)||'Changement refusé par Windows','err');}
  }catch(e){toast('Erreur de connexion','err');}
  loading(false);
  loadPowerPlans();
}
async function loadStartup(){
  try{
    const d=await API.get('/api/startup');
    const items=d.items||[];
    const render=items.length?items.map(i=>{
      const isOn=i.enabled;
      return `<div style="display:flex;align-items:center;padding:8px 0;border-bottom:1px solid var(--border);gap:10px">
        <div style="flex:1;min-width:0">
          <div style="font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${i.name}</div>
          <div style="font-size:10px;color:${isOn?'var(--orange)':'var(--muted)'};margin-top:2px">
            ${isOn?'⚠️ Lance au démarrage':'✓ Désactivé du démarrage'}
          </div>
        </div>
        <label class="tog-svc" title="${isOn?'Désactiver du démarrage':'Activer au démarrage'}">
          <input type="checkbox" ${isOn?'checked':''} onchange="toggleStartup('${escS(i.name)}','${escS(i.regPath||'')}',this.checked,this.parentElement)">
          <span class="tog-svc-sl"></span>
        </label>
      </div>`;
    }).join(''):'<div style="color:var(--muted);font-size:11px;padding:8px 0">Aucun programme au démarrage détecté</div>';
    ['startup-list','startup-list-apps'].forEach(id=>{const e=document.getElementById(id);if(e)e.innerHTML=render;});
  }catch(e){console.error('loadStartup error:',e);}
}

async function toggleStartup(name,regPath,enable,toggleEl){
  if(toggleEl){toggleEl.style.opacity='0.5';toggleEl.style.pointerEvents='none';}
  loading(true,enable?'Activation au démarrage...':'Désactivation du démarrage...');
  try{
    const r=await API.post('/api/startup/toggle',{name,regPath,enable});
    if(r&&r.ok){
      toast((enable?'✅ Activé':'✅ Désactivé')+' au démarrage : '+name,'ok');
      setTimeout(()=>loadStartup(),400);
    }else{
      toast('❌ '+(r&&r.msg||'Impossible de modifier'),'err');
      if(toggleEl){toggleEl.style.opacity='1';toggleEl.style.pointerEvents='';}
    }
  }catch(e){
    toast('❌ '+e.message,'err');
    if(toggleEl){toggleEl.style.opacity='1';toggleEl.style.pointerEvents='';}
  }
  loading(false);
}

async function loadServices(){
  try{
    const d=await API.get('/api/services');
    const el=document.getElementById('svc-list');if(!el)return;
    const svcs=d.services||[];
    // Afficher TOUS les services de SVC_INFO + ceux remontés par l'API
    const allNames=[...new Set([...Object.keys(SVC_INFO),...svcs.map(s=>s.name)])];
    el.innerHTML=allNames.map(name=>{
      const svc=svcs.find(s=>s.name===name)||{name,state:'Unknown',status:'unknown'};
      const info=SVC_INFO[name]||{n:name,d:'Service Windows'};
      const isRunning=svc.state==='Running';
      const col=isRunning?'var(--orange)':'var(--green)';
      const stateLabel=isRunning?'Actif':'Inactif';
      return`<div style="background:rgba(var(--inv-rgb),.03);border:1px solid var(--border);border-radius:8px;padding:10px 12px">
        <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:6px;margin-bottom:6px">
          <div>
            <div style="font-size:11.5px;font-weight:700;color:var(--text);line-height:1.3">${info.n}</div>
            <div style="font-size:9.5px;color:var(--muted);margin-top:2px;line-height:1.3">${info.d}</div>
          </div>
          <span style="font-size:9px;font-weight:700;padding:2px 7px;border-radius:4px;background:${col}22;color:${col};flex-shrink:0;margin-top:1px">${stateLabel}</span>
        </div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-top:8px">
          <span style="font-size:10px;color:${isRunning?'var(--orange)':'var(--muted)'}">
            ${isRunning?'⚠️ Actif — peut être désactivé':'✓ Désactivé'}
          </span>
          <label class="tog-svc" title="${isRunning?'Désactiver ce service':'Activer ce service'}">
            <input type="checkbox" ${isRunning?'checked':''} onchange="toggleSvc('${name}',this.checked,this.parentElement)">
            <span class="tog-svc-sl"></span>
          </label>
        </div>
      </div>`;
    }).join('');
  }catch(e){const el=document.getElementById('svc-list');if(el)el.innerHTML='<div style="color:var(--muted);font-size:11px;padding:8px">Impossible de charger les services</div>';}
}

async function toggleSvc(name,enable,toggleEl){
  if(toggleEl){toggleEl.style.opacity='0.5';toggleEl.style.pointerEvents='none';}
  const info=(typeof SVC_INFO!=='undefined'&&SVC_INFO[name])?SVC_INFO[name].n:name;
  loading(true,(enable?'Activation':'Désactivation')+' : '+info+'...');
  try{
    const r=await API.post('/api/services/toggle',{name,enable});
    if(r&&(r.ok||r.success)){
      toast((enable?'✅ Activé':'✅ Désactivé')+' : '+info,'ok');
      setTimeout(()=>loadServices(),600);
    }else{
      toast('❌ '+(r&&r.msg||'Impossible de modifier'),'err');
      if(toggleEl){toggleEl.style.opacity='1';toggleEl.style.pointerEvents='';}
    }
  }catch(e){
    toast('❌ '+e.message,'err');
    if(toggleEl){toggleEl.style.opacity='1';toggleEl.style.pointerEvents='';}
  }
  loading(false);
}
async function doVisualFX(mode){loading(true,mode==='reduce'?'Réduction effets...':'Restauration...');try{await API.post('/api/visual',{mode});toast(mode==='reduce'?'Effets réduits':'Effets restaurés','ok');}catch(e){toast('Erreur','err');}loading(false);}

// ── PROTECT ──────────────────────────────────────────────────────────────────
function setPill(id,cls,txt){const e=document.getElementById(id);if(e){e.className='pill-'+cls;e.textContent=txt;}}
async function loadSecStatus(){
  try{const d=await API.get('/api/security/status');
    // Si autre AV actif, Defender désactivé est NORMAL
    const hasOtherAV=d.otherAV===true;
    const defOk=d.defEnabled===true||hasOtherAV;const sa=d.defSigAge>=0?d.defSigAge:0;const sigOk=sa<=7||hasOtherAV;
    setPill('def-pill',defOk&&sigOk?'ok':'warn',defOk?sigOk?'Activé':'Sig '+sa+'j':'Désactivé');
    const dd=document.getElementById('def-sub');if(dd)dd.textContent=defOk?sigOk?'Protection active, signatures à jour':'MAJ signatures recommandée':'PROTECTION DÉSACTIVÉE';
    const db=document.getElementById('def-fix-btn');if(db)db.style.display=(!defOk||!sigOk)?'block':'none';
    setPill('fw-pill',d.fwOk?'ok':'warn',d.fwOk?'Activé':'Désactivé');
    const fd=document.getElementById('fw-sub');if(fd)fd.textContent=d.fwOk?'Tous profils actifs':'Pare-feu désactivé';
    const fb=document.getElementById('fw-fix-btn');if(fb)fb.style.display=d.fwOk?'none':'block';
    const uacOk=d.uacOk!==false;
    setPill('uac-pill',uacOk?'ok':'warn',uacOk?'Activé':'Désactivé');
    const ud=document.getElementById('uac-sub');if(ud)ud.textContent=uacOk?'Contrôle comptes actif':'UAC désactivé';
    const ssOk=d.ssOk!==false;
    setPill('ss-pill',ssOk?'ok':'warn',ssOk?'Activé':'Désactivé');
    const sd=document.getElementById('ss-sub');if(sd)sd.textContent=ssOk?'Protection navigateur active':'SmartScreen désactivé';
    const issues=[!defOk,!sigOk,!d.fwOk,!uacOk].filter(Boolean).length;
    const sc=Math.max(0,100-issues*20);
    const sce=document.getElementById('sec-score');if(sce){sce.textContent=sc;sce.style.color=sc>=80?'var(--green)':sc>=60?'var(--orange)':'var(--red)';}
  }catch(e){}
}
async function loadAccessStatus(){
  try{const d=await API.get('/api/access/status');
    const t=(id,v)=>{const e=document.getElementById(id);if(e)e.checked=v===true;};
    t('tog-cam',d.cam);t('tog-mic',d.mic);t('tog-tel',d.tel);
    const d1=document.getElementById('cam-sub');if(d1)d1.textContent=d.cam!==false?'Accès autorisé':'Accès bloqué';
    const d2=document.getElementById('mic-sub');if(d2)d2.textContent=d.mic!==false?'Accès autorisé':'Accès bloqué';
    const d3=document.getElementById('tel-sub');if(d3)d3.textContent=d.tel!==false?'Données envoyées à Microsoft':'Télémétrie désactivée';
  }catch(e){}
}
async function setAccess(feature,enable){try{await API.post('/api/access/toggle',{feature,enable});toast('Mis à jour','ok');}catch(e){toast('Erreur','err');}}
const FIX_MSGS={'enable_defender':'Activation de Windows Defender...','update_defender':'Mise à jour de Windows Defender...','enable_firewall':'Activation du pare-feu Windows...','defender_scan':'Analyse Defender en cours...','flush_dns':'Vidage du cache DNS...','reset_firewall':'Réinitialisation du pare-feu...','enable_uac':'Activation du contrôle des comptes utilisateurs...','enable_smartscreen':'Activation de SmartScreen...'};
async function doFix(action,btn){
  const msg=FIX_MSGS[action]||'Correction en cours...';
  showRepairProgress(msg,null);
  if(btn){btn.disabled=true;const orig=btn.innerHTML;btn.innerHTML='<div class="spin" style="width:12px;height:12px;border-width:2px;display:inline-block;vertical-align:middle"></div>';
    try{const r=await API.post('/api/security/fix',{action});toast(r.ok?'✅ '+r.msg:'❌ Erreur','ok');if(r.ok){addLog(r.msg);setTimeout(loadSecStatus,800);}}catch(e){toast('❌ Erreur de connexion','err');}
    hideRepairProgress();btn.disabled=false;btn.innerHTML=orig;
  } else {
    try{const r=await API.post('/api/security/fix',{action});toast(r.ok?'✅ '+r.msg:'❌ Erreur','ok');if(r.ok){addLog(r.msg);setTimeout(loadSecStatus,800);}}catch(e){toast('❌ Erreur','err');}
    hideRepairProgress();
  }
}
async function doAntiTrack(){
  loading(true,'Anti-tracking...');
  try{const r=await API.post('/api/antitracking',{});toast(r.msg||'Terminé','ok');addLog('Anti-tracking: '+r.cleaned+' fichiers');}catch(e){toast('Erreur','err');}
  loading(false);
}
async function doAntiTrackBtn(btn){
  loading(true,'Nettoyage des traceurs...');
  const orig=btn.innerHTML;btn.disabled=true;btn.innerHTML='<div class="spin" style="width:12px;height:12px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:6px"></div>En cours...';
  try{const r=await API.post('/api/antitracking',{});toast('✅ '+(r.msg||'Nettoyage terminé'),'ok');addLog('Anti-tracking: '+r.cleaned+' fichiers');}catch(e){toast('❌ Erreur','err');}
  loading(false);btn.disabled=false;btn.innerHTML=orig;
}

let _sP=null,_sT=null;
function switchPTab(tab){
  document.getElementById('ptab-scan').style.display=tab==='scan'?'flex':'none';
  document.getElementById('ptab-prot').style.display=tab==='prot'?'flex':'none';
  document.getElementById('ptab-scan-btn').classList.toggle('ptab-active',tab==='scan');
  document.getElementById('ptab-prot-btn').classList.toggle('ptab-active',tab==='prot');
}
function _ssb(d){
  ['btn-scan-quick','btn-scan-full','btn-scan-def'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=d;});
  const c=document.getElementById('btn-scan-cancel');
  if(c)c.style.display=d?'flex':'none';
  if(!d){const cc=document.getElementById('btn-scan-cancel');if(cc)cc.disabled=false;}
}
function _sz2(h){const z=document.getElementById('prot-scan-zone');if(z)z.innerHTML=h;}

const PHASE_ICONS={
  'Windows Defender et Menaces':'🛡️',
  'Processus en memoire':'⚙️',
  'Programmes indesirables':'🗑️',
  'Registre Demarrage':'🔑',
  'Taches planifiees':'📅',
  'Services Windows':'🔧',
  'Fichiers dangereux':'📁',
  'Reseau et Hosts':'🌐',
  'Navigateurs':'🌍',
  'WMI Persistance':'⚠️',
  'IFEO Hijacking':'🔴',
  'DLL suspectes':'📦',
  'Indicateurs Rootkit':'🚨',
  'Crypto Miners':'⛏️',
  'Adware et Trackers':'📣',
  'Ransomware':'🔒',
  'Score final':'📊'
};

function _buildScanner(mode, phase, tot, phaseName, threats, files, elapsed, log){
  const pct=phase>0?Math.round((phase/tot)*100):0;
  const icon=PHASE_ICONS[phaseName]||'🔍';
  const donePhases=log||[];
  const checkList=donePhases.slice(-6).map((p,i)=>{
    const isLast=i===donePhases.slice(-6).length-1;
    const ico=PHASE_ICONS[p]||'🔍';
    return'<div class="scanner-check-item '+(isLast?'scanner-check-active':'scanner-check-done')+'">'+
      '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="'+(isLast?'var(--purple)':'var(--green)')+'" stroke-width="3"><polyline points="20 6 9 17 4 12"/></svg>'+
      '<span>'+ico+' '+p+'</span></div>';
  }).join('');

  return'<div class="scanner-active">'+
    '<div class="scanner-left">'+
      '<div class="scanner-svg-wrap">'+
        '<svg viewBox="0 0 150 150" xmlns="http://www.w3.org/2000/svg" width="150" height="150">'+
          '<defs>'+
            '<radialGradient id="beamGrad" cx="0%" cy="50%">'+
              '<stop offset="0%" stop-color="var(--purple2)" stop-opacity="0.6"/>'+
              '<stop offset="100%" stop-color="var(--purple2)" stop-opacity="0"/>'+
            '</radialGradient>'+
            '<radialGradient id="centerGlow" cx="50%" cy="50%" r="50%">'+
              '<stop offset="0%" stop-color="var(--purple2)" stop-opacity="0.3"/>'+
              '<stop offset="100%" stop-color="var(--purple2)" stop-opacity="0"/>'+
            '</radialGradient>'+
          '</defs>'+
          '<circle cx="75" cy="75" r="70" fill="rgba(var(--acc-rgb),0.04)" stroke="rgba(var(--acc-rgb),0.15)" stroke-width="1"/>'+
          '<circle cx="75" cy="75" r="52" fill="none" stroke="rgba(var(--acc-rgb),0.12)" stroke-width="1"/>'+
          '<circle cx="75" cy="75" r="34" fill="none" stroke="rgba(var(--acc-rgb),0.18)" stroke-width="1"/>'+
          '<circle cx="75" cy="75" r="16" fill="rgba(var(--acc-rgb),0.08)" stroke="rgba(var(--acc-rgb),0.3)" stroke-width="1.5"/>'+
          '<line x1="5" y1="75" x2="145" y2="75" stroke="rgba(var(--acc-rgb),0.08)" stroke-width="1"/>'+
          '<line x1="75" y1="5" x2="75" y2="145" stroke="rgba(var(--acc-rgb),0.08)" stroke-width="1"/>'+
          '<g class="scanner-beam-group">'+
            '<path d="M75 75 L145 75 A70 70 0 0 0 75 5 Z" fill="url(#beamGrad)" opacity="0.7"/>'+
            '<line x1="75" y1="75" x2="145" y2="75" stroke="var(--purple2)" stroke-width="2" opacity="0.9"/>'+
          '</g>'+
          '<circle cx="75" cy="75" r="5" fill="var(--purple2)" filter="url(#blur)"/>'+
          '<circle cx="75" cy="75" r="10" fill="url(#centerGlow)"/>'+
        '</svg>'+
      '</div>'+
      '<div class="scanner-pct">'+pct+'%</div>'+
      '<div class="scanner-pct-lbl">Phase '+phase+'/'+tot+'</div>'+
    '</div>'+
    '<div class="scanner-right">'+
      '<div class="scanner-phase-big">'+icon+' '+phaseName+'</div>'+
      '<div class="scanner-prog-wrap"><div class="scanner-prog-bar" id="s-pb" style="width:'+pct+'%"></div></div>'+
      '<div class="scanner-stats-row">'+
        '<div class="scanner-stat-card"><div class="scanner-stat-val" id="s-thr" style="color:'+(threats>0?'var(--red)':'var(--orange)')+'">'+threats+'</div><div class="scanner-stat-lbl">Menaces</div></div>'+
        '<div class="scanner-stat-card"><div class="scanner-stat-val" id="s-fi" style="color:var(--dim)">'+files+'</div><div class="scanner-stat-lbl">Fichiers</div></div>'+
        '<div class="scanner-stat-card"><div class="scanner-stat-val" id="s-tm" style="color:var(--muted)">'+elapsed+'s</div><div class="scanner-stat-lbl">Durée</div></div>'+
      '</div>'+
      '<div style="font-size:11px;font-weight:700;color:var(--muted);margin-bottom:4px;text-transform:uppercase;letter-spacing:.5px">En cours d\'analyse :</div>'+
      '<div class="scanner-checklist">'+checkList+'</div>'+
    '</div>'+
  '</div>';
}

async function startFullScan(mode){
  if(_sP){clearInterval(_sP);_sP=null;}if(_sT){clearInterval(_sT);_sT=null;}
  _ssb(true);
  let tot=(mode==='quick')?15:32,el=0,polling=false,stall=0;
  _sz2(_buildScanner(mode,0,tot,'Initialisation de l analyse...',0,0,0,[]));
  _sT=setInterval(()=>{el++;const tm=document.getElementById('s-tm');if(tm)tm.textContent=el+'s';},1000);
  try{
    const r=await API.post('/api/scanner/start',{mode},300000);
    if(!r||!r.started){
      clearInterval(_sT);_sT=null;_ssb(false);
      _sz2('<div style="text-align:center;padding:30px"><div style="font-size:18px;font-weight:800;color:var(--red);margin-bottom:10px">Echec du demarrage</div><div style="font-size:13px;color:var(--muted);margin-bottom:16px">'+((r&&r.error)?('OptiPC n\u2019a pas pu creer son fichier de travail dans :<br><span style=\"color:var(--dim);font-size:11.5px\">'+(r.workdir||'')+'</span><br><br><span style=\"font-size:11.5px\">Votre antivirus bloque peut-etre ce dossier. Ajoutez-y une exception, ou appelez le '+EDITEUR.tel+'.</span>'):'Verifiez que OptiPC est lance en administrateur')+'</div><button onclick="startFullScan(\''+mode+'\')" style="border:none;border-radius:10px;padding:12px 28px;background:var(--purple);color:#fff;font-size:14px;font-weight:700;cursor:pointer;font-family:inherit">Reessayer</button></div>');
      return;
    }
    tot=r.total||tot;
    let lastLog=[],lastThreats=0,lastFiles=0,lastPhase=0;
    _sP=setInterval(async()=>{
      if(polling)return;polling=true;
      try{
        const d=await API.get('/api/scanner/poll',240000);
        if(d&&!d.done){
          if(d.phase>0){
            if(d.phase===lastPhase){stall++;}else{stall=0;}
            lastPhase=d.phase;lastThreats=d.threats||0;lastFiles=d.files||0;
            if(d.log&&d.log.length)lastLog=d.log;
            _sz2(_buildScanner(mode,d.phase,d.total||tot,d.phaseName,lastThreats,lastFiles,el,lastLog));
          }
        }
        if(d&&d.done){
          clearInterval(_sP);clearInterval(_sT);_sP=null;_sT=null;_ssb(false);
          if(d.cancelled){
            _sz2('<div style="text-align:center;padding:40px"><div style="font-size:16px;font-weight:800;color:var(--muted);margin-bottom:8px">Analyse annulée</div><div style="font-size:12.5px;color:var(--muted)">Vous pouvez relancer une analyse à tout moment.</div></div>');
            toast('Analyse annulée','info');
          } else {
            _showRes(d);
          }
        }
      }catch(e){}
      polling=false;
    },1500);
  }catch(e){
    clearInterval(_sT);_sT=null;_ssb(false);
    _sz2('<div style="text-align:center;padding:30px"><div style="font-size:18px;font-weight:800;color:var(--red);margin-bottom:10px">Analyse interrompue</div><div style="font-size:13px;color:var(--muted);margin-bottom:16px">'+((e&&e.message&&e.message.indexOf('abort')>=0)?"Le PC n'a pas répondu à temps. Fermez quelques programmes et réessayez.":(e.message||'Erreur inconnue'))+'</div><button onclick="startFullScan(\''+mode+'\')" style="border:none;border-radius:10px;padding:12px 28px;background:var(--purple);color:#fff;font-size:14px;font-weight:700;cursor:pointer;font-family:inherit">Reessayer</button></div>');
  }
}
async function startDefenderFull(btn){
  showConfirm('Lancer l analyse complete Windows Defender ?','Le moteur antivirus officiel de Microsoft va analyser la totalite de vos disques. Duree : 20 a 60 minutes. Le PC reste utilisable, mais un peu plus lent.',async()=>{
    loading(true,'Demarrage du moteur Windows Defender...');
    try{
      const r=await API.post('/api/defender/fullscan',{},60000);
      loading(false);
      toast(r.msg||'Analyse lancee',r.ok?'ok':'err');
      if(r.ok){addLog('Analyse complete Defender lancee');pollDefender();}
    }catch(e){loading(false);toast('Erreur','err');}
  });
}

async function pollDefender(){
  const box=document.getElementById('def-full-status');
  try{
    const d=await API.get('/api/defender/status',20000);
    if(box){
      if(d.running){
        box.style.display='flex';
        box.innerHTML='<div class="spin" style="width:14px;height:14px;border-width:2px"></div><span style="font-size:12px;color:var(--text)">Analyse Windows Defender en cours &middot; '+(d.elapsed||'')+' &middot; '+((d.threats||[]).length)+' menace(s) trouvee(s)</span>';
        setTimeout(pollDefender,15000);
        return;
      }
      if((d.threats||[]).length){
        box.style.display='flex';
        box.innerHTML='<span style="font-size:12px;color:var(--red);font-weight:700">Analyse Defender terminee : '+d.threats.length+' menace(s) detectee(s) et mise(s) en quarantaine par Windows</span>';
      } else if(d.elapsed){
        box.style.display='flex';
        box.innerHTML='<span style="font-size:12px;color:var(--green);font-weight:700">Analyse Windows Defender terminee : aucune menace</span>';
      }
    }
  }catch(e){}
}
const THREAT_IMPACT={
 'Malware':"Ce type de programme peut voler vos mots de passe et vos identifiants bancaires, lire vos fichiers personnels, activer la webcam ou le micro, et donner le contrôle de votre PC à une personne extérieure.",
 'Fichier':"Un fichier de ce type peut, s'il est ouvert, installer un logiciel espion, chiffrer vos documents pour exiger une rançon, ou ouvrir un accès à distance à votre ordinateur.",
 'Script':"Un script malveillant peut télécharger d'autres virus, désactiver votre antivirus, copier vos documents vers un serveur extérieur ou modifier Windows en profondeur.",
 'Persistance':"Ce mécanisme relance un programme à chaque démarrage de Windows. Il sert à ce qu'un logiciel indésirable revienne systématiquement, même après avoir été supprimé.",
 'Rootkit':"Un rootkit dissimule la présence d'un intrus au cœur de Windows. Il peut espionner tout ce que vous faites sans apparaître dans les outils habituels, et survivre à un nettoyage classique.",
 'Service':"Un service se lance automatiquement avec Windows et tourne en permanence en arrière-plan, avec des droits élevés, sans que vous le voyiez.",
 'DLL':"Une bibliothèque détournée s'exécute à l'intérieur d'un programme légitime. Elle peut enregistrer ce que vous tapez au clavier et contourner les protections de sécurité.",
 'Reseau':"Une configuration réseau détournée permet de rediriger vos sites vers de fausses pages (banque, messagerie), d'intercepter vos connexions et de récupérer vos mots de passe.",
 'Navigateur':"Un détournement du navigateur peut vous rediriger vers des sites frauduleux, injecter des publicités et suivre l'intégralité de votre navigation.",
 'Certificat':"Un certificat racine non reconnu permet de déchiffrer et de lire vos connexions sécurisées : sites bancaires, e-mails, achats en ligne.",
 'Miner':"Un mineur utilise votre processeur en continu pour générer de la cryptomonnaie au profit d'un tiers. Conséquences : PC très lent, surchauffe, usure du matériel et facture d'électricité en hausse.",
 'Ransomware':"Un rançongiciel chiffre vos photos et vos documents puis exige un paiement. Sans sauvegarde, les fichiers sont le plus souvent perdus définitivement.",
 'PUP':"Ce programme ralentit le PC, affiche des alertes exagérées et pousse à souscrire un abonnement inutile. Il est souvent installé à votre insu avec un autre logiciel.",
 'Adware':"Un logiciel publicitaire injecte des publicités dans vos pages, modifie vos résultats de recherche et revend vos habitudes de navigation.",
 'Securite':"Une protection désactivée laisse la porte ouverte : un virus peut s'installer sans être ni détecté ni bloqué.",
 'Defender':"Sans base antivirus à jour, les virus apparus récemment ne sont pas reconnus et passent au travers de la protection.",
 'Integrite':"Un fichier modifié après sa signature indique qu'un programme d'origine a été altéré : c'est une méthode courante pour glisser du code malveillant dans un logiciel de confiance.",
 'Compte':"Un accès non maîtrisé permet à une autre personne de se connecter à votre PC, de consulter vos fichiers et d'y installer ce qu'elle veut.",
 'Suspect':"Ce programme a un comportement inhabituel. Il peut s'agir d'un logiciel légitime mal installé comme du début d'une infection."
};
function threatImpact(t){
  if(!t)return '';
  if(THREAT_IMPACT[t.cat])return THREAT_IMPACT[t.cat];
  if(t.sev==='critical')return THREAT_IMPACT['Malware'];
  if(t.sev==='high')return THREAT_IMPACT['Suspect'];
  return '';
}
function _showRes(data){
  const z=document.getElementById('prot-scan-zone');if(!z)return;
  const th=data.threats||[],sc=data.score||0,dur=data.duration||'?',fi=data.files||0;
  const scCol=sc>=80?'var(--green)':sc>=60?'var(--orange)':'var(--red)';
  const stats='<div class="scan-res-stats">'
    +'<div class="scan-res-card"><div class="scan-res-val" style="color:'+scCol+'">'+sc+'</div><div class="scan-res-lbl">Score</div></div>'
    +'<div class="scan-res-card"><div class="scan-res-val" style="color:'+(th.length?'var(--red)':'var(--green)')+'">'+th.length+'</div><div class="scan-res-lbl">Menaces</div></div>'
    +'<div class="scan-res-card"><div class="scan-res-val" style="color:var(--dim)">'+fi+'</div><div class="scan-res-lbl">Elements analyses</div></div>'
    +'<div class="scan-res-card"><div class="scan-res-val" style="color:var(--dim);font-size:18px">'+dur+'</div><div class="scan-res-lbl">Duree</div></div>'
  +'</div>';
  if(!th.length){
    z.innerHTML='<div class="scan-res-wrap">'+stats
      +'<div class="scan-res-clean">'
      +'<svg class="scan-res-clean-ico" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--green)" stroke-width="1.5"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10" stroke-width="2.5"/></svg>'
      +'<div class="scan-res-clean-title">PC propre : aucune menace detectee</div>'
      +'<div class="scan-res-clean-sub">Aucun signe d infection, de logiciel espion ou de programme indesirable</div>'
      +'</div></div>';
    if(notifOn('notifScan'))toast('PC propre - Score : '+sc+'/100','ok');
    addLog('Analyse terminee : aucune menace (score '+sc+')');
    return;
  }
  const so={critical:0,high:1,medium:2,low:3};
  const sevC={critical:'var(--red)',high:'var(--orange)',medium:'#fbbf24',low:'var(--dim)'};
  const sevL={critical:'CRITIQUE',high:'ELEVE',medium:'MOYEN',low:'FAIBLE'};
  const note = isPro()
    ? '<div style="background:rgba(var(--acc-rgb),.07);border:1px solid rgba(var(--acc-rgb),.2);border-radius:9px;padding:10px 14px;font-size:11.5px;color:var(--acc-text);line-height:1.6">'
      +'<strong>Conseil :</strong> mettez en quarantaine plutôt que de supprimer. Le fichier est déplacé dans un coffre et peut être restauré à tout moment depuis Paramètres si c\'était une fausse alerte.</div>'
    : '<div style="background:linear-gradient(135deg,rgba(249,115,22,.12),rgba(249,115,22,.05));border:1px solid rgba(249,115,22,.3);border-radius:9px;padding:12px 15px;font-size:12px;color:var(--acc-text);line-height:1.6;display:flex;align-items:center;gap:12px">'
      +'<span style="font-size:20px">&#128274;</span><div style="flex:1"><strong>Version gratuite :</strong> l\'analyse détecte et détaille les menaces, mais leur suppression et leur mise en quarantaine nécessitent la version Premium.</div>'
      +'<button class="btn-su" style="background:linear-gradient(135deg,#f97316,#ea580c);color:#fff;border:none;font-weight:700;flex-shrink:0" onclick="showProGate(\'Supprimez les menaces détectées et protégez durablement votre PC avec la version Premium.\')">Débloquer</button></div>';
  const nDel=th.filter(t=>t.canDel).length;
  const bulk='<div id="thr-bulk" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:10px 12px;margin:10px 0 8px;background:rgba(var(--inv-rgb),.03);border:1px solid var(--border);border-radius:9px;font-size:12px">'
    +'<label style="display:flex;align-items:center;gap:7px;cursor:pointer;font-weight:600"><input type="checkbox" id="thr-all" onchange="_thrAll(this.checked)" style="accent-color:var(--purple);width:14px;height:14px">Tout sélectionner</label>'
    +'<span id="thr-selcount" style="color:var(--muted)">0 sélectionnée(s)</span><span style="flex:1"></span>'
    +'<button class="tact" style="background:rgba(100,116,139,.15);color:var(--dim)" onclick="_thrBulk(\'ignore\')">Ignorer la sélection</button>'
    +(nDel?(isPro()
      ?'<button class="tact" style="background:rgba(240,136,62,.15);color:var(--orange)" onclick="_thrBulk(\'quar\')">Quarantaine (sélection)</button><button class="tact tact-del" onclick="_thrBulk(\'del\')">Supprimer (sélection)</button>'
      :'<button class="tact" style="background:rgba(var(--acc-rgb),.12);color:var(--acc-text)" onclick="showProGate(\'Mettez en quarantaine toutes les menaces en un clic avec la version Premium.\')">&#128274; Quarantaine (sélection)</button><button class="tact" style="background:rgba(var(--acc-rgb),.12);color:var(--acc-text)" onclick="showProGate(\'Supprimez toutes les menaces en un clic avec la version Premium.\')">&#128274; Supprimer (sélection)</button>'):'')
    +'</div>';
  const thrH=bulk+'<div class="threat-list-wrap">'+[...th].sort((a,b)=>(so[a.sev]||9)-(so[b.sev]||9)).map(t=>{
    const c=sevC[t.sev]||'var(--dim)',l=sevL[t.sev]||String(t.sev).toUpperCase();
    const imp=threatImpact(t);
    let ac='<div class="threat-actions"><button class="tact tact-view" onclick="_oTh(this,\''+escS(t.path)+'\')">Voir</button>';
    if(t.canDel){
      if(isPro()){
        ac+='<button class="tact" style="background:rgba(240,136,62,.15);color:var(--orange)" onclick="_qTh(this,\''+escS(t.path)+'\',\''+escS(t.name)+'\')">Quarantaine</button>';
        ac+='<button class="tact tact-del" onclick="_dTh(this,\''+escS(t.path)+'\')">Supprimer</button>';
      }else{
        ac+='<button class="tact" style="background:rgba(var(--acc-rgb),.12);color:var(--acc-text)" title="Disponible avec la version Premium" onclick="showProGate(\'La mise en quarantaine des menaces est réservée à la version Premium.\')">&#128274; Quarantaine</button>';
        ac+='<button class="tact" style="background:rgba(var(--acc-rgb),.12);color:var(--acc-text)" title="Disponible avec la version Premium" onclick="showProGate(\'La suppression des menaces est réservée à la version Premium.\')">&#128274; Supprimer</button>';
      }
    }
    ac+='<button class="tact" style="background:rgba(100,116,139,.15);color:var(--dim)" title="Ne plus signaler ce fichier" onclick="_iTh(this,\''+escS(t.path)+'\',\''+escS(t.name)+'\')">Ignorer</button>';
    ac+='</div>';
    return '<div class="threat-card" style="border-left-color:'+c+'">'
      +'<div class="threat-card-head">'
      +'<input type="checkbox" class="thr-cb" data-path="'+escS(t.path)+'" data-name="'+escS(t.name)+'" data-candel="'+(t.canDel?1:0)+'" onchange="_thrCount()" style="accent-color:var(--purple);width:14px;height:14px;cursor:pointer;flex-shrink:0;margin-right:4px">'
      +'<span class="threat-badge" style="background:'+c+'22;color:'+c+'">'+l+'</span>'
      +'<span class="threat-cat-badge">'+t.cat+'</span>'
      +'<span class="threat-name" style="color:'+c+'">'+t.name+'</span>'
      +'</div>'
      +'<div class="threat-detail">'+t.detail+'</div>'
      +(imp?'<div class="threat-risk"><span class="threat-risk-lbl">Risque encouru</span>'+imp+'</div>':'')
      +'<div class="threat-path-txt">'+t.path+'</div>'
      +ac+'</div>';
  }).join('')+'</div>';
  z.innerHTML='<div class="scan-res-wrap">'+stats+note+thrH+'</div>';
  if(notifOn('notifThreat'))toast(th.length+' menace(s) - Score : '+sc+'/100','err');
  addLog('Analyse : '+th.length+' menace(s), score '+sc);
  loadSecStatus();
}
async function runMalwareScan(){startFullScan('quick');}
function _thrCbs(){return [...document.querySelectorAll('.thr-cb')].filter(c=>c.closest('.threat-card')&&c.closest('.threat-card').style.opacity!=='0');}
function _thrAll(on){_thrCbs().forEach(c=>{if(!c.disabled)c.checked=on;});_thrCount();}
function _thrCount(){const sel=_thrCbs().filter(c=>c.checked).length;const el=document.getElementById('thr-selcount');if(el)el.textContent=sel+' sélectionnée(s)';}
async function _thrBulk(kind){
  const sel=_thrCbs().filter(c=>c.checked);
  if(!sel.length){toast('Cochez au moins une menace (ou « Tout sélectionner »)','info');return;}
  const targets=kind==='ignore'?sel:sel.filter(c=>c.dataset.candel==='1');
  if(!targets.length){toast('Ces éléments ne peuvent pas être supprimés : utilisez « Ignorer »','info');return;}
  const label={ignore:'Ignorer',quar:'Mettre en quarantaine',del:'Supprimer définitivement'}[kind];
  const txt={ignore:'Ces éléments ne seront plus signalés lors des prochaines analyses.',
    quar:'Les fichiers seront déplacés dans le coffre de quarantaine (restaurables depuis Paramètres).',
    del:'Les fichiers seront effacés sans retour possible. La quarantaine est plus sûre.'}[kind];
  showConfirm(label+' '+targets.length+' élément(s) ?',txt,async()=>{
    let ok=0,ko=0,n=0;
    for(const c of targets){
      n++;loading(true,label+' '+n+'/'+targets.length+'...');
      const path=c.dataset.path,name=c.dataset.name;
      try{
        let r;
        if(kind==='ignore'){r=await API.post('/api/security/ignore',{path,name},30000);}
        else if(kind==='quar'){r=await API.post('/api/security/quarantine',{path,reason:name},120000);}
        else{r=await API.post('/api/security/remove',{path},120000);}
        if(r&&r.ok){ok++;const card=c.closest('.threat-card');if(card){card.style.transition='.3s';card.style.opacity=kind==='ignore'?'.35':'0';c.checked=false;c.disabled=true;if(kind!=='ignore')setTimeout(()=>card.remove(),350);}}
        else ko++;
      }catch(e){ko++;}
    }
    loading(false);
    const all=document.getElementById('thr-all');if(all)all.checked=false;
    _thrCount();
    toast(ok+' élément(s) traité(s)'+(ko?' · '+ko+' échec(s)':''),ko?'info':'ok');
    addLog(label+' : '+ok+' élément(s)'+(ko?', '+ko+' échec(s)':''));
  });
}
async function _qTh(btn,path,name){
  const orig=btn.innerHTML;btn.disabled=true;btn.textContent='...';
  try{
    const r=await API.post('/api/security/quarantine',{path,reason:name},120000);
    if(r&&r.ok){
      toast('Mis en quarantaine (restaurable dans Parametres)','ok');
      addLog('Quarantaine : '+path);
      const c=btn.closest('.threat-card');if(c){c.style.opacity='0';c.style.transition='.4s';setTimeout(()=>c.remove(),400);}
    } else { toast((r&&r.msg)||'Echec','err');btn.disabled=false;btn.innerHTML=orig; }
  }catch(e){toast('Erreur : '+e.message,'err');btn.disabled=false;btn.innerHTML=orig;}
}
async function _iTh(btn,path,name){
  btn.disabled=true;
  try{
    const r=await API.post('/api/security/ignore',{path,name},30000);
    if(r&&r.ok){
      toast('Ajoute aux exceptions','ok');
      const c=btn.closest('.threat-card');if(c){c.style.opacity='.35';}
    } else { toast('Echec','err');btn.disabled=false; }
  }catch(e){toast('Erreur','err');btn.disabled=false;}
}
async function _dTh(btn,path){
  showConfirm('Supprimer definitivement ?','Le fichier sera efface sans possibilite de retour. La mise en quarantaine est plus sure.',async()=>{
    btn.disabled=true;
    try{
      const r=await API.post('/api/security/remove',{path},120000);
      if(r&&r.ok){
        toast('Supprime','ok');addLog('Supprime : '+path);
        const c=btn.closest('.threat-card,.threat-item');if(c){c.style.opacity='0';c.style.transition='.4s';setTimeout(()=>c.remove(),400);}
      } else { toast((r&&r.msg)||'Erreur','err');btn.disabled=false; }
    }catch(e){toast('Erreur : '+e.message,'err');btn.disabled=false;}
  });
}
async function loadQuarantine(){
  const el=document.getElementById('quar-list');if(!el)return;
  try{
    const d=await API.get('/api/quarantine',30000);
    const it=d.items||[];
    if(!it.length){el.innerHTML='<div style="color:var(--muted);font-size:11px;padding:6px 0">Le coffre de quarantaine est vide.</div>';return;}
    el.innerHTML=it.map(q=>'<div style="display:flex;align-items:center;gap:8px;padding:7px 0;border-bottom:1px solid rgba(var(--inv-rgb),.04)">'
      +'<div style="flex:1;min-width:0"><div style="font-size:11.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+(q.reason||'Fichier')+'</div>'
      +'<div style="font-size:9.5px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+q.original+' &middot; '+q.date+'</div></div>'
      +'<button class="btn-su btn-ghost" style="font-size:10px;padding:3px 9px" onclick="quarAct(\''+q.id+'\',\'restore\')">Restaurer</button>'
      +'<button class="btn-su btn-red" style="font-size:10px;padding:3px 9px" onclick="quarAct(\''+q.id+'\',\'delete\')">Effacer</button></div>').join('');
  }catch(e){el.innerHTML='<div style="color:var(--muted);font-size:11px">Indisponible</div>';}
}
async function quarAct(id,act){
  loading(true,act==='restore'?'Restauration...':'Suppression definitive...');
  try{
    const r=await API.post('/api/quarantine/'+act,{id},60000);
    toast((r&&r.msg)||'Termine',(r&&r.ok)?'ok':'err');
    loadQuarantine();
  }catch(e){toast('Erreur','err');}
  loading(false);
}
async function clearWhitelist(){
  try{await API.post('/api/security/ignore/clear',{},30000);toast('Exceptions effacees','ok');}catch(e){toast('Erreur','err');}
}
async function _oTh(btn,path){
  const orig=btn.innerHTML;btn.disabled=true;
  btn.innerHTML='<div class="spin" style="width:12px;height:12px;border-width:2px;display:inline-block;vertical-align:middle"></div> Ouverture...';
  try{
    const r=await API.post('/api/security/open',{path});
    if(r&&r.ok){toast('📂 Dossier ouvert','ok');}
    else{toast('❌ '+(r&&r.msg||'Impossible d\'ouvrir le dossier'),'err');}
  }catch(e){toast('❌ Erreur: '+e.message,'err');}
  btn.disabled=false;btn.innerHTML=orig;
}
const REPAIR_MSGS={'winsxs_analyze':"Mesure de l'espace occupé par les anciennes mises à jour (2 à 3 min)...",'winsxs_clean':'Suppression des anciennes mises à jour Windows (5 à 20 min)...','sfc':'Analyse et réparation des fichiers système Windows...','dism':'Réparation de l\'image système Windows...','chkdsk':'Vérification du disque en cours...'};
async function doRepair(action,btn){
  const msg=REPAIR_MSGS[action]||'Réparation en cours...';
  showRepairProgress(msg,null);
  if(btn){const orig=btn.innerHTML;btn.disabled=true;btn.innerHTML='<div class="spin" style="width:14px;height:14px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:6px"></div>En cours...';
    try{const r=await API.post('/api/repair',{action});toast('✅ '+(r.output||'Réparation terminée'),'ok');addLog('Réparation: '+action);}catch(e){toast('❌ Erreur','err');}
    hideRepairProgress();btn.disabled=false;btn.innerHTML=orig;
  } else {
    try{const r=await API.post('/api/repair',{action});toast('✅ '+(r.output||'Terminé'),'ok');addLog('Réparation: '+action);}catch(e){toast('❌ Erreur','err');}
    hideRepairProgress();
  }
}

// ── APPS ─────────────────────────────────────────────────────────────────────

function appIni(n){const c=['#E8650C','#3fb950','var(--orange)','var(--purple)','var(--red)','var(--green)','#38bdf8'];let h=0;for(const ch of n)h=(h*31+ch.charCodeAt(0))&0xffff;return c[h%c.length];}

function fmtBytes(b){
  b=Number(b)||0;
  if(b<=0)return '—';
  if(b>=1073741824)return (b/1073741824).toFixed(1)+' Go';
  if(b>=1048576)return Math.round(b/1048576)+' Mo';
  if(b>=1024)return Math.round(b/1024)+' Ko';
  return b+' o';
}
function setAppSort(key){
  const s=window._appSort||{key:'name',dir:1};
  if(s.key===key){s.dir=-s.dir;}else{s.key=key;s.dir=(key==='size'?-1:1);}
  window._appSort=s;
  const sel=document.getElementById('app-sort');
  if(sel)sel.value=s.key==='size'?(s.dir===-1?'size_desc':'size_asc'):'name';
  renderApps();
}
function setAppSortSel(v){
  window._appSort=v==='size_desc'?{key:'size',dir:-1}:v==='size_asc'?{key:'size',dir:1}:{key:'name',dir:1};
  renderApps();
}
function _selApps(){return [...document.querySelectorAll('.app-cb:checked')].map(c=>_appsData[parseInt(c.dataset.i,10)]).filter(Boolean);}

function renderApps(){
  const q=(window._appQ||'').toLowerCase();
  const force=(window._appMode==='force');
  let list=_appsData.filter(a=>!q||(a.name||'').toLowerCase().includes(q)||(a.publisher||'').toLowerCase().includes(q));
  const s=window._appSort||{key:'name',dir:1};
  list=list.slice().sort((a,b)=>{
    let va,vb;
    if(s.key==='size'){va=a.sizeBytes||0;vb=b.sizeBytes||0;}
    else{va=(a.name||'').toLowerCase();vb=(b.name||'').toLowerCase();}
    return va<vb?-s.dir:va>vb?s.dir:0;
  });
  const tgt=document.getElementById(force?'force-list':'apps-list');
  if(!tgt)return;
  const totalEl=document.getElementById('apps-total-size');
  if(totalEl)totalEl.textContent=_appsData.length+' logiciel(s) · '+fmtBytes(_appsData.reduce((t,a)=>t+(a.sizeBytes||0),0))+' au total';
  if(!list.length){tgt.innerHTML='<div style="color:var(--muted);font-size:12px;padding:14px">Aucun logiciel trouve.</div>';return;}
  const arrow=k=>s.key===k?(s.dir===1?' ▲':' ▼'):'';
  const header=force?'':'<div class="app-row" style="font-size:10px;color:var(--muted);font-weight:700;cursor:pointer;user-select:none">'
    +'<div style="width:13px"></div><div style="width:26px"></div>'
    +'<div style="flex:1" onclick="setAppSort(\'name\')">NOM'+arrow('name')+'</div>'
    +'<div style="flex-shrink:0;width:70px;text-align:right;padding-right:10px" onclick="setAppSort(\'size\')">TAILLE'+arrow('size')+'</div>'
    +'<div style="flex-shrink:0"></div></div>';
  tgt.innerHTML=header+list.map(a=>{
    const i=_appsData.indexOf(a);
    const col=appIni(a.name||'?');
    const badge=(a.type==='uwp'?'<span style="font-size:8.5px;background:rgba(56,189,248,.15);color:#38bdf8;border-radius:4px;padding:1px 6px;margin-left:6px;font-weight:700">STORE</span>':'')
      +(a.kind==='oem'?'<span title="Logiciel preinstalle par le fabricant du PC : il peut generalement etre supprime sans risque" style="font-size:8.5px;background:rgba(240,136,62,.15);color:var(--orange);border-radius:4px;padding:1px 6px;margin-left:6px;font-weight:700">FABRICANT</span>':'');
    const meta=[a.version?('v'+a.version):'',a.publisher||'',a.installDate||''].filter(Boolean).join(' &middot; ');
    const sizeTxt=a.sizeBytes?fmtBytes(a.sizeBytes):(a.size&&a.size!=='?'?a.size:'—');
    const btns=force
      ? '<button class="btn-su btn-red" style="padding:5px 12px;font-size:11px" onclick="forceApp('+i+')">Supprimer de force</button>'
      : '<button class="btn-su btn-ghost" style="padding:5px 12px;font-size:11px" onclick="uninstallApp('+i+')">Desinstaller</button>'
        +'<button class="btn-su btn-red" style="padding:5px 10px;font-size:11px;margin-left:6px" title="Desinstalle puis supprime tous les residus (dossiers, registre, services)" onclick="forceApp('+i+')">Forcer</button>';
    return '<div class="app-row">'
      +(force?'':'<input type="checkbox" class="app-cb" data-i="'+i+'" onchange="updateSel()" style="accent-color:var(--purple);width:13px;height:13px;cursor:pointer">')
      +'<div class="app-init" style="background:'+col+'22;color:'+col+'">'+(a.name||'?').substring(0,2).toUpperCase()+'</div>'
      +'<div style="flex:1;min-width:0"><div style="font-size:12.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+a.name+badge+'</div>'
      +'<div style="font-size:10px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+meta+'</div></div>'
      +'<div style="flex-shrink:0;width:70px;text-align:right;padding-right:10px;font-size:11px;color:var(--muted)">'+sizeTxt+'</div>'
      +'<div style="flex-shrink:0">'+btns+'</div></div>';
  }).join('');
}

async function loadApps(force){
  const tgt=document.getElementById('apps-list');
  if(tgt&&!_appsData.length)tgt.innerHTML='<div style="color:var(--muted);font-size:12px;padding:14px"><span class="spin" style="width:12px;height:12px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:8px"></span>Lecture de la liste des logiciels installes...</div>';
  try{
    const d=await API.get(force?'/api/apps/refresh':'/api/apps',90000);
    _appsData=d.apps||[];
    renderApps();
    updateSel();
  }catch(e){
    const why=e&&e.name==='AbortError'?'delai depasse':((e&&e.message)||'erreur');
    if(tgt)tgt.innerHTML='<div style="color:var(--red);font-size:12px;padding:14px">Impossible de lire la liste des logiciels ('+why+'). <button class="btn-su btn-ghost" style="font-size:11px;margin-left:8px" onclick="loadApps(1)">Reessayer</button></div>';
  }
}

function filterApps(q){ window._appQ=q||''; renderApps(); }
async function refreshAppsTab(){
  const b=document.getElementById('btn-apps-refresh');
  if(b){b.disabled=true;b.style.opacity='.5';}
  try{
    if(window._appMode==='startup'){ await loadStartup(); }
    else {
      const tgt=document.getElementById(window._appMode==='force'?'force-list':'apps-list');
      if(tgt)tgt.innerHTML='<div style="color:var(--muted);font-size:12px;padding:14px"><span class="spin" style="width:12px;height:12px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:8px"></span>Actualisation de la liste...</div>';
      await loadApps(1);
    }
    toast('Liste actualisée','ok');
  }catch(e){}
  if(b){b.disabled=false;b.style.opacity='1';}
}

function renderForce(){ renderApps(); }

function switchAppTab(name,el){
  ['installed','startup','force'].forEach(n=>{const e=document.getElementById('app-tab-'+n);if(e)e.style.display=(n===name?'block':'none');});
  document.querySelectorAll('.app-tab').forEach(t=>t.classList.remove('active'));
  if(el)el.classList.add('active');
  window._appMode=name;
  if(name==='startup'){loadStartup();return;}
  if(!_appsData.length){loadApps();}else{renderApps();}
}

function updateSel(){
  const s=document.querySelectorAll('.app-cb:checked').length;
  const b=document.getElementById('btn-del-sel');
  if(!b)return;
  b.disabled=(s===0);
  const bytes=_selApps().reduce((t,a)=>t+(a.sizeBytes||0),0);
  b.textContent=s?('Desinstaller ('+s+(bytes?' · '+fmtBytes(bytes):'')+')'):'Supprimer selection';
}

function showLogModal(title,lines,extraHtml){
  const old=document.getElementById('_logmodal');if(old)old.remove();
  const el=document.createElement('div');
  el.id='_logmodal';el.className='modal-overlay';
  el.innerHTML='<div class="modal-box" style="max-width:520px;text-align:left">'
    +'<div class="modal-title" style="text-align:left;margin-bottom:12px">'+title+'</div>'
    +'<div style="background:var(--card2);border:1px solid var(--border);border-radius:8px;padding:10px 12px;max-height:240px;overflow-y:auto;font-size:11.5px;line-height:1.8;color:var(--dim)">'
    +(lines&&lines.length?lines.map(l=>'<div>&bull; '+l+'</div>').join(''):'<div>Aucun detail.</div>')
    +'</div>'+(extraHtml||'')
    +'<div class="modal-btns" style="margin-top:18px"><button class="modal-btn-cancel" onclick="document.getElementById(\'_logmodal\').remove()">Fermer</button></div></div>';
  document.body.appendChild(el);
}

async function uninstallApp(i){
  const a=_appsData[i];if(!a)return;
  showConfirm('Desinstaller '+a.name+' ?','Le programme d installation officiel va etre lance. Certains logiciels affichent leur propre fenetre.',async()=>{
    loading(true,'Desinstallation de '+a.name+'...');
    try{
      const r=await API.post('/api/apps/uninstall2',{app:a,mode:'normal'},300000);
      loading(false);
      const lo=r.leftovers||{};
      let extra='';
      if(lo.count>0){
        extra='<div style="margin-top:14px;padding:11px 13px;background:rgba(240,136,62,.08);border:1px solid rgba(240,136,62,.25);border-radius:8px;font-size:12px;color:var(--orange)">'
          +'<strong>'+lo.count+' residu(s) trouve(s)</strong> ('+(lo.totalSize||'0 B')+') : dossiers et cles de registre laisses sur le PC.'
          +'<button class="btn-su btn-red" style="display:block;margin-top:10px;font-size:11.5px" onclick="cleanLeftovers('+i+')">Supprimer les residus</button></div>';
      }
      showLogModal((r.message||'Desinstallation terminee')+(r.success&&a.sizeBytes?' — '+fmtBytes(a.sizeBytes)+' liberes':''),r.log,extra);
      addLog('Desinstallation : '+a.name+(r.success?'':' (incomplete)'));
      if(r.stillInstalled)toast('Desinstallation incomplete — voir le detail','info');
      loadApps(1);
    }catch(e){loading(false);toast('Erreur : '+e.message,'err');}
  });
}

async function cleanLeftovers(i){
  const a=_appsData[i];if(!a)return;
  const m=document.getElementById('_logmodal');if(m)m.remove();
  loading(true,'Suppression des residus...');
  try{
    const r=await API.post('/api/apps/leftovers/clean',{app:a},300000);
    loading(false);
    showLogModal(r.message||'Residus supprimes',r.log);
    addLog('Residus supprimes : '+a.name);
    loadApps(1);
  }catch(e){loading(false);toast('Erreur : '+e.message,'err');}
}

function showLiveLogModal(title){
  const old=document.getElementById('_livelog');if(old)old.remove();
  const el=document.createElement('div');
  el.id='_livelog';el.className='modal-overlay';
  el.innerHTML='<div class="modal-box" style="max-width:560px;text-align:left">'
    +'<div class="modal-title" style="text-align:left;margin-bottom:12px">'+title+'</div>'
    +'<div id="_livelog-body" style="background:var(--card2);border:1px solid var(--border);border-radius:8px;padding:10px 12px;height:260px;overflow-y:auto;font-size:11.5px;line-height:1.75;color:var(--dim);font-family:monospace"></div>'
    +'<div class="modal-btns" style="margin-top:16px"><button id="_livelog-close" class="modal-btn-cancel" disabled style="opacity:.5">Fermeture a la fin...</button></div></div>';
  document.body.appendChild(el);
  return el;
}
function _esc(x){return String(x).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));}
function _renderLiveLines(lines){
  const body=document.getElementById('_livelog-body');if(!body)return;
  body.innerHTML=(lines||[]).map(raw=>{
    const l=(raw&&typeof raw==='object')?String(raw.value||''):String(raw||'');
    const m=l.match(/^(\d{2}:\d{2}:\d{2})\s+(.*)$/);
    const t=m?m[1]:'',msg=m?m[2]:l;let icon='•',col='var(--dim)';
    if(msg.startsWith('TERMINE')){icon='✅';col='var(--green)';}
    else if(msg.startsWith('ATTENTION')){icon='⚠️';col='var(--orange)';}
    else if(msg.startsWith('Dossier supprime')||msg.startsWith('Cle de registre')||msg.startsWith('Service supprime')||msg.startsWith('Tache')||msg.startsWith('Raccourci')||msg.startsWith('Entree')||msg.startsWith('Paquet Store supprime')){icon='🗑️';col='var(--acc-text)';}
    else if(msg.startsWith('Processus arrete')||msg.startsWith('Process tue')||msg.startsWith('Service arrete')){icon='⛔';col='var(--acc-text)';}
    else if(msg.startsWith('OK -')){icon='✅';col='var(--green)';}
    else if(msg.startsWith('ECHEC')||msg.startsWith('Echec')){icon='❌';col='var(--red)';}
    else if(msg.startsWith('Element bloque')||msg.startsWith('Toujours present')||msg.startsWith('Delai')){icon='🔒';col='var(--orange)';}
    else if(msg.startsWith('Cible')||msg.startsWith('Type')||msg.startsWith('Recherche')||msg.startsWith('Aucun')){icon='🔍';col='#60a5fa';}
    else if(msg.startsWith('Suppression')||msg.startsWith('Prise')||msg.startsWith('Robocopy')||msg.startsWith('Etape')){icon='⚙️';col='var(--dim)';}
    else if(msg.startsWith('Programme')){icon='🕓';col='#facc15';}
    else if(msg.startsWith('Dossier verrouille')||msg.startsWith('Cle de registre non')){icon='🔒';col='var(--orange)';}
    else if(msg.startsWith('Desinstallation en cours')||msg.startsWith('Attente')||msg.startsWith('Desinstalleur interactif')){icon='⏳';col='#facc15';}
    else if(msg.startsWith('Desinstalleur officiel termine')||msg.startsWith('Application Microsoft Store')){icon='✔️';col='var(--green)';}
    else if(msg.startsWith('Desinstalleur introuvable')||msg.startsWith('Desinstalleur indisponible')||msg.startsWith('Desinstalleur interrompu')){icon='❌';col='var(--red)';}
    else if(msg.startsWith('Recherche')||msg.startsWith('Analyse')){icon='🔍';col='#60a5fa';}
    else if(msg.startsWith('Lancement')||msg.startsWith('Suppression du paquet')){icon='⚙️';col='var(--dim)';}
    return '<div style="display:flex;gap:6px;padding:2px 0"><span style="color:var(--muted);flex-shrink:0;min-width:58px">'+t+'</span><span>'+icon+'</span><span style="color:'+col+';word-break:break-all">'+_esc(msg)+'</span></div>';
  }).join('');
  body.scrollTop=body.scrollHeight;
}
async function forceApp(i){
  const a=_appsData[i];if(!a)return;
  showConfirm('Suppression forcee de '+a.name+' ?','Le desinstalleur officiel sera lance, puis OptiPC recherchera et supprimera TOUTES les traces restantes (dossiers, cles de registre, services, taches planifiees, raccourcis), comme un desinstalleur avance. Action irreversible.',async()=>{
    const modal=showLiveLogModal('Suppression forcee de '+a.name);
    _renderLiveLines(['Démarrage de la suppression, veuillez patienter...']);
    let last=0;
    const poll=setInterval(async()=>{
      try{
        const d=await API.get('/api/apps/force-uninstall-log',15000);
        if(d.lines&&d.lines.length!==last){last=d.lines.length;_renderLiveLines(d.lines);}
      }catch(e){}
    },800);
    try{
      const r=await API.post('/api/apps/force-uninstall',{app:a},1200000);
      clearInterval(poll);
      try{const d=await API.get('/api/apps/force-uninstall-log',15000);if(d.lines&&d.lines.length)_renderLiveLines(d.lines);}catch(e){}
      const btn=document.getElementById('_livelog-close');
      if(btn){btn.disabled=false;btn.style.opacity='1';btn.textContent='Fermer';btn.onclick=()=>{document.getElementById('_livelog').remove();loadApps(1);};}
      toast(r.stillInstalled?'Traces supprimees — redemarrage conseille':'Supprime !',r.stillInstalled?'info':'ok');
      addLog('Suppression forcee : '+a.name);
    }catch(e){
      clearInterval(poll);
      const btn=document.getElementById('_livelog-close');
      if(btn){btn.disabled=false;btn.style.opacity='1';btn.textContent='Fermer';btn.onclick=()=>{document.getElementById('_livelog').remove();loadApps(1);};}
      toast('Erreur : '+(e.name==='AbortError'?'delai depasse':e.message),'err');
    }
  });
}

async function deleteSelectedApps(){
  const items=[...document.querySelectorAll('.app-cb:checked')].map(c=>parseInt(c.dataset.i,10));
  if(!items.length)return;
  const selBytes=items.reduce((t,i)=>t+((_appsData[i]&&_appsData[i].sizeBytes)||0),0);
  showConfirm('Desinstaller '+items.length+' logiciel(s) ?','Les desinstallations seront lancees une par une.'+(selBytes?' Espace a liberer : '+fmtBytes(selBytes)+'.':''),async()=>{
    let done=0,n=0,freed=0;const lines=[];
    for(const i of items){
      const a=_appsData[i];if(!a)continue;
      n++;
      loading(true,'Desinstallation '+n+'/'+items.length+' : '+a.name+' — si une fenêtre du logiciel s\'ouvre, validez-la');
      try{
        const r=await API.post('/api/apps/uninstall2',{app:a,mode:'normal'},660000);
        if(r&&r.success){done++;freed+=(a.sizeBytes||0);lines.push('OK : '+a.name+(a.sizeBytes?' ('+fmtBytes(a.sizeBytes)+')':''));}
        else if(r&&r.stillInstalled){lines.push('A verifier : '+a.name+' — la desinstallation n\'a pas ete confirmee (fenetre fermee ou annulee ?). Cliquez sur Actualiser pour verifier.');}
        else{lines.push('Echec : '+a.name+((r&&r.log&&r.log.length)?' — '+r.log[r.log.length-1]:''));}
      }catch(e){lines.push('Echec : '+a.name+' — '+(e.name==='AbortError'?'delai depasse':e.message));}
    }
    loading(false);
    showLogModal(done+'/'+items.length+' logiciel(s) desinstalle(s)'+(freed?' — '+fmtBytes(freed)+' liberes':''),lines);
    addLog(done+' logiciel(s) desinstalle(s)'+(freed?' — '+fmtBytes(freed)+' liberes':''));
    loadApps(1);
  });
}
// ── MON PC ───────────────────────────────────────────────────────────────────
async function loadSysInfo(){loading(true,'Chargement...');
  const _sg=document.getElementById('sysinfo-grid');
  if(_sg&&!_sg.innerHTML.trim())_sg.innerHTML='<div style="grid-column:1/-1;color:var(--muted);font-size:11px"><span class="spin" style="width:11px;height:11px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:7px"></span>Lecture de la configuration...</div>';
  try{const d=await API.get('/api/sysinfo',60000);
    const items=[{l:'Système',v:d.os||'--'},{l:'Version',v:d.build||'--'},{l:'CPU',v:d.cpu||'--'},{l:'Coeurs',v:d.cpuCores||'--'},{l:'GPU',v:d.gpu||'--'},{l:'RAM',v:d.ram||'--'},{l:'Disque',v:d.diskModel||'--'},{l:'Capacité',v:d.diskSize||'--'},{l:'Fabricant',v:d.manufacturer||'--'},{l:'Modèle',v:d.model||'--'},{l:'BIOS',v:d.bios||'--'},{l:'Uptime',v:d.uptime||'--'},{l:'IP',v:d.ip||'--'},{l:'PC',v:d.hostname||'--'},{l:'Utilisateur',v:d.user||'--'}];
    document.getElementById('sysinfo-grid').innerHTML=items.map(i=>`<div class="si-item"><div class="si-lbl">${i.l}</div><div class="si-val">${i.v}</div></div>`).join('');
  }catch(e){
    if(_sg)_sg.innerHTML='<div style="grid-column:1/-1;font-size:11.5px;color:var(--red)">Lecture de la configuration impossible. <button class="btn-su btn-ghost" style="font-size:10px;margin-left:6px" onclick="loadSysInfo()">Réessayer</button></div>';
  }loading(false);}
async function loadDiskInfo(){
  try{const d=await API.get('/api/diskinfo');const el=document.getElementById('disk-info');if(!el)return;
    el.innerHTML=(d.drives||[]).map(dr=>{const p=dr.pct||dr.usedPct||0;return `<div style="flex:1;min-width:160px"><div style="display:flex;justify-content:space-between;margin-bottom:5px"><span style="font-size:12px;font-weight:600">${dr.letter}</span><span style="font-size:11px;color:var(--dim)">${dr.free} libres / ${dr.total}</span></div><div style="height:5px;background:rgba(var(--inv-rgb),.06);border-radius:3px;overflow:hidden"><div style="height:100%;border-radius:3px;background:${p>80?'var(--red)':p>60?'var(--orange)':'var(--purple)'};width:${p}%"></div></div><div style="font-size:10px;color:var(--muted);margin-top:3px">${p}% utilisé — ${dr.used} utilisés</div></div>`;}).join('');
    if(d.drives&&d.drives.length){const c=d.drives.find(dr=>dr.letter==='C:')||d.drives[0];document.getElementById('stat-disk').textContent=c.free||'--';}
  }catch(e){}
}
async function doRegScan(){
  loading(true,'Scan registre...');
  try{
    const d=await API.get('/api/registry/scan');
    _regItems=d.items||[];
    const el=document.getElementById('reg-result');
    const color=d.count>0?'var(--orange)':'var(--green)';
    let html='<div style="font-weight:600;margin-bottom:8px;color:'+color+'">'+d.count+' entrée(s) invalide(s)</div>';
    if(_regItems.length>0){
      html+=_regItems.map(i=>'<div style="display:flex;align-items:center;gap:7px;padding:6px 0;border-bottom:1px solid rgba(var(--inv-rgb),.04)">'+
        '<div style="flex:1;min-width:0"><div style="font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:var(--dim)">'+i.name+'</div>'+
        (i.detail?'<div style="font-size:9.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:var(--muted)" title="'+String(i.detail).replace(/"/g,'&quot;')+'">'+i.detail+'</div>':'')+'</div>'+
        '<span style="flex-shrink:0;white-space:nowrap;font-size:9px;background:rgba(240,136,62,.1);color:var(--orange);border:1px solid rgba(240,136,62,.18);border-radius:4px;padding:1px 6px">'+i.issue+'</span>'+
        '</div>').join('');
    } else {
      html+='<div style="color:var(--green);font-size:11px">Registre propre ✓</div>';
    }
    if(el)el.innerHTML=html;
    const btnClean=document.getElementById('btn-clean-reg');
    if(btnClean)btnClean.disabled=(d.count===0);
    toast(d.count===0?'Registre propre':d.count+' problèmes trouvés','ok');
    addLog('Scan registre: '+d.count+' problème(s)');
  }catch(e){
    toast('Erreur scan registre: '+(e.message||e),'err');
  }
  loading(false);
}
async function doRegClean(){confirm2('Nettoyer le registre','Supprimer '+_regItems.length+' entrée(s) ?',async()=>{loading(true);try{const r=await API.post('/api/registry/clean',{keys:_regItems.map(i=>i.key)});if(r.failed>0){toast(r.cleaned+' nettoyée(s), '+r.failed+' impossible(s)','err');}else{showSuccess(r.cleaned+' entrées nettoyées (sauvegarde créée)','Registre optimisé');}_regItems=[];document.getElementById('btn-clean-reg').disabled=true;doRegScan();}catch(e){toast('Erreur','err');}loading(false);});}

// ── PARAMS ───────────────────────────────────────────────────────────────────
async function loadScheduleStatus(){
  try{
    const d=await API.get('/api/schedule');
    if(d&&d.enabled&&d.frequency&&d.frequency!=='remove'){
      // Activer le bon bouton de frequence
      _schedMode=d.frequency;
      document.querySelectorAll('.sched-btn').forEach(b=>b.classList.remove('active'));
      const ab=document.getElementById('sched-'+d.frequency);
      if(ab)ab.classList.add('active');
      if(d.time){const ti=document.getElementById('sched-time');if(ti)ti.value=d.time;}
      // Afficher l'heure si daily/weekly
      const tr=document.getElementById('sched-time-row');
      if(tr)tr.style.display=(d.frequency==='daily'||d.frequency==='weekly')?'flex':'none';
      updateSchedPreview();
    }
  }catch(e){}
  loadCleanLog();
}
async function loadCleanLog(){
  try{
    const d=await API.get('/api/cleanlog');
    // Détecter nouvelles entrées et les ajouter à l'historique d'activité
    if(d.lines&&d.lines.length>0){
      const lastKnown=localStorage.getItem('optipc_last_cleanlog')||'';
      const newest=d.lines[d.lines.length-1];
      if(newest!==lastKnown){
        localStorage.setItem('optipc_last_cleanlog',newest);
        const knownIdx=d.lines.lastIndexOf(lastKnown);
        const newLines=knownIdx>=0?d.lines.slice(knownIdx+1):d.lines.slice(-1);
        newLines.forEach(l=>{if(l&&l.trim())addLog('🗓️ '+l.trim());});
      }
    }
    const el=document.getElementById('clean-log-list');
    if(!el)return;
    if(!d.lines||d.lines.length===0){
      el.innerHTML='<div style="color:var(--muted);font-size:11px;padding:8px 0">Aucun nettoyage planifié effectué pour l\'instant.</div>';
      return;
    }
    el.innerHTML=d.lines.slice().reverse().map(l=>{
      const mb=l.match(/([\d.,]+\s*(MB|GB|KB|B))\s+liber/i);
      const sizeTag=mb?`<span style="color:var(--green);font-weight:700">${mb[1]}</span>`:'';
      const clean=l.replace(mb?mb[0]:'','').replace('[','').replace(']','');
      return `<div style="display:flex;justify-content:space-between;align-items:center;padding:5px 0;border-bottom:1px solid rgba(var(--inv-rgb),.04);font-size:11px">
        <span style="color:var(--dim)">${clean}</span>${sizeTag}</div>`;
    }).join('');
  }catch(e){}
}

// ── WINDOW CONTROLS ──────────────────────────────────────────────────────────
function wcMin(){fetch('/api/window/min',{method:'POST',headers:{'X-OptiPC-Token':OPTI_TOKEN}}).catch(()=>{});}
function wcMax(){fetch('/api/window/max',{method:'POST',headers:{'X-OptiPC-Token':OPTI_TOKEN}}).catch(()=>{});}
function wcClose(){try{window.close();}catch(e){}}
// Bouton son - injecté dans window.onload

// ── SUPPRESSION FORCÉE ───────────────────────────────────────────────────────
async function browseForDelete(){ browsePick('folder'); }
async function browsePick(kind){
  const btns=document.querySelectorAll('.browse-btn');
  btns.forEach(b=>{b.disabled=true;});
  toast(kind==='file'?'Fenetre de selection de fichier ouverte...':'Fenetre de selection de dossier ouverte...','info');
  try{
    const r=await API.get('/api/browse?type='+kind,190000);
    if(r&&r.success&&r.path&&r.path.length>2){
      document.getElementById('force-del-path').value=r.path;
      toast('Chemin selectionne','ok');
    } else if(r&&r.cancelled){
      toast('Selection annulee','info');
    } else {
      toast('Aucune selection','info');
    }
  }catch(e){ toast('La fenetre de selection ne repond pas','err'); }
  btns.forEach(b=>{b.disabled=false;});
}
function _renderForceLog(lines, log){
  if(!log||!lines||!lines.length)return;
  log.innerHTML=lines.map(raw=>{
    const l=(raw&&typeof raw==='object')?String(raw.value||''):String(raw||'');
    const mm=l.match(/^(\d{2}:\d{2}:\d{2})\s+(.*)$/);
    const t=mm?mm[1]:''; // timestamp HH:mm:ss
    const msg=mm?mm[2]:l; // reste du message
    const isOk=msg.startsWith('OK -');
    const isErr=msg.startsWith('ECHEC');
    const isProc=msg.startsWith('Process tue') || msg.startsWith('Service arrete');
    let icon='📋'; let col='var(--dim)';
    if(isOk){icon='✅';col='var(--green)';}
    else if(isErr){icon='❌';col='var(--red)';}
    else if(msg.startsWith('Arret')){icon='🔴';col='#f97316';}
    else if(msg.startsWith('Prise')){icon='🔐';col='var(--acc-text)';}
    else if(msg.startsWith('Suppression PS')){icon='⚡';col='var(--dim)';}
    else if(msg.startsWith('Suppression CMD')){icon='💻';col='var(--dim)';}
    else if(msg.startsWith('Robocopy')){icon='🔄';col='var(--dim)';}
    else if(msg.startsWith('Suppression fichier')){icon='🗑️';col='var(--dim)';}
    else if(msg.startsWith('Total:')){icon='📊';col='#60a5fa';}
    else if(isProc){icon='⚠️';col='#f97316';}
    return '<div style="display:flex;gap:6px;padding:2px 0;font-size:10.5px;border-bottom:1px solid rgba(var(--inv-rgb),.03)">'+
      '<span style="color:var(--muted);flex-shrink:0">'+t+'</span>'+
      '<span>'+icon+'</span>'+
      '<span style="color:'+col+'">'+msg+'</span></div>';
  }).join('');
  log.scrollTop=log.scrollHeight;
}

async function doForceDelete(){
  const path=document.getElementById('force-del-path').value.trim();
  if(!path){toast('Entrez un chemin','info');return;}
  const st=document.getElementById('force-del-status');
  if(!confirm('⚠️ Supprimer DÉFINITIVEMENT :\n"'+path+'" ?\n\nLes programmes qui l\'utilisent seront arrêtés. Action irréversible.'))return;

  const btn=document.querySelector('[onclick="doForceDelete()"]');
  if(btn){btn.disabled=true;btn.innerHTML='⏳ Suppression...';}
  if(st)st.innerHTML='<span style="color:var(--orange)">⏳ En cours... suivez le détail dans la fenêtre</span>';

  // Même fenêtre de suivi en direct que la suppression forcée des logiciels
  const nm=path.split(/[\\\/]/).filter(Boolean).pop()||path;
  showLiveLogModal('Suppression forcée de '+_esc(nm));
  _renderLiveLines(['Démarrage de la suppression, veuillez patienter...']);
  let last=0;
  const pull=async()=>{
    try{
      const d=await API.get('/api/force-log',10000);
      if(d.lines&&d.lines.length&&d.lines.length!==last){last=d.lines.length;_renderLiveLines(d.lines);}
    }catch(e){}
  };
  const poll=setInterval(pull,700);
  const finish=(ok,msg)=>{
    const body=document.getElementById('_livelog-body');
    if(body){
      body.insertAdjacentHTML('beforeend','<div style="margin-top:6px;padding-top:6px;border-top:1px solid var(--border);font-weight:700;color:'+(ok?'var(--green)':'var(--red)')+'">'+(ok?'✅ ':'❌ ')+_esc(msg)+'</div>');
      body.scrollTop=body.scrollHeight;
    }
    const cb=document.getElementById('_livelog-close');
    if(cb){cb.disabled=false;cb.style.opacity='1';cb.textContent='Fermer';cb.onclick=()=>{const m=document.getElementById('_livelog');if(m)m.remove();};}
    if(st)st.innerHTML='<span style="color:'+(ok?'var(--green)':'var(--red)')+'">'+(ok?'✅ ':'❌ ')+_esc(msg)+'</span>';
  };

  try{
    const r=await API.post('/api/force-delete',{path},600000);
    clearInterval(poll); await pull();
    if(r.success){
      finish(true,r.message);
      document.getElementById('force-del-path').value='';
      toast('Supprimé !','ok');
      addLog('Suppression forcée: '+r.message);
    }else{
      finish(false,r.error||'Échec');
      toast('Échec','err');
      addLog('❌ Suppression forcée: '+(r.error||'échec'));
    }
  }catch(e){
    clearInterval(poll); await pull();
    finish(false,e.name==='AbortError'?'Délai dépassé — redémarrez le PC et réessayez':'Erreur de communication avec OptiPC');
  }
  if(btn){btn.disabled=false;btn.innerHTML='💣 Supprimer de force';}
}

// ── SCHEDULE ─────────────────────────────────────────────────────────────────
let _schedMode='remove';
function setSchedMode(val,btn){
  _schedMode=val;
  document.querySelectorAll('.sched-btn').forEach(b=>b.classList.remove('active'));
  btn.classList.add('active');
  const tr=document.getElementById('sched-time-row');
  if(tr)tr.style.display=(val==='daily'||val==='weekly')?'flex':'none';
  updateSchedPreview();
}
function updateSchedPreview(){
  const el=document.getElementById('sched-preview');if(!el)return;
  const t=document.getElementById('sched-time')?.value||'03:00';
  const[hh,mm]=t.split(':');const hf=hh+'h'+mm;
  const map={remove:'',daily:'→ Tous les jours à '+hf,weekly:'→ Chaque lundi à '+hf,startup:'→ À chaque démarrage du PC'};
  el.textContent=map[_schedMode]||'';
}
async function loadScheduleStatus(){
  try{
    const d=await API.get('/api/schedule');
    if(d&&d.frequency&&d.frequency!=='none'){
      _schedMode=d.frequency;
      const b=document.getElementById('sched-'+d.frequency);
      if(b){document.querySelectorAll('.sched-btn').forEach(x=>x.classList.remove('active'));b.classList.add('active');}
      const tr=document.getElementById('sched-time-row');
      if(tr)tr.style.display=(d.frequency==='daily'||d.frequency==='weekly')?'flex':'none';
      if(d.time){const ti=document.getElementById('sched-time');if(ti)ti.value=d.time;}
      updateSchedPreview();
    }
  }catch(e){}
}
async function applySchedule(){
  loading(true,'Sauvegarde...');
  try{
    const t=document.getElementById('sched-time')?.value||'03:00';
    const r=await API.post('/api/schedule',{frequency:_schedMode,time:t});
    if(r&&r.success){
      toast('✅ Planification enregistrée','ok');
      addLog('Planification: '+_schedMode+' à '+t);
      updateSchedPreview();
    } else {
      toast('❌ '+(r&&r.error?r.error:'Erreur'),'err');
    }
  }catch(e){toast('Erreur réseau','err');}
  loading(false);
}

// ── LICENCE ──────────────────────────────────────────────────────────────────
// ── LICENCE UI helpers ───────────────────────────────────────────────────────
function showLicFree(){
  // Bascule REELLE vers la version gratuite : la cle est retiree du PC.
  if(_isPro){ revokeLicense(); return; }
  document.getElementById('lic-activate-zone').style.display='';
  document.getElementById('lic-pro-zone').style.display='none';
  const k=document.getElementById('lic-key');
  if(k){ k.focus(); }
  toast('Vous êtes déjà en version gratuite','info');
}
function showLicPro(){
  if(_isPro){ toast('La version Premium est déjà active','info'); return; }
  document.getElementById('lic-activate-zone').style.display='';
  document.getElementById('lic-pro-zone').style.display='none';
  const k=document.getElementById('lic-key');
  if(k){ k.focus(); k.scrollIntoView({behavior:'smooth',block:'center'}); }
  showProGate('Entrez votre clé Premium juste en dessous, ou appelez-nous au 05 54 54 23 43 pour en obtenir une.');
}

// 1.0.5 : reprise d'une activation interrompue par un redemarrage du moteur.
setTimeout(()=>{
  let k=null;
  try{ k=sessionStorage.getItem('optipc_pending_key'); sessionStorage.removeItem('optipc_pending_key'); }catch(e){}
  if(k){ const i=document.getElementById('lic-key'); if(i){ i.value=k; activateLicense(); } }
},2500);
async function activateLicense(){
  const key=document.getElementById('lic-key').value.trim().toUpperCase();
  if(!key){toast('Entrez une clé','info');return;}
  loading(true,'Activation en cours...');
  const st=document.getElementById('lic-status');
  try{
    const r=await API.post('/api/license/activate',{key});
    if(r.isPro){
      _isPro=true;
      _setProUI(r);
      toast('✅ Premium activé !','ok');
      addLog('✅ Licence Premium activée');
      if(st)st.innerHTML='';
    } else {
      if(st)st.innerHTML='<span style="color:var(--red)">❌ '+( r.message||'Clé invalide')+'</span>';
      toast(r.message||'Clé invalide','err');
    }
  }catch(e){
    // 1.0.5 : moteur injoignable (Failed to fetch) -> il est en train d'etre
    // relance par le gardien. On garde la cle et on reprendra l'activation
    // automatiquement des que la page se sera rechargee sur le nouveau moteur.
    if(e && e.name==='TypeError'){
      try{ sessionStorage.setItem('optipc_pending_key', key); }catch(_){}
      if(st)st.innerHTML='<span style="color:var(--orange)">⏳ OptiPC redémarre son moteur… L\u2019activation reprendra toute seule dans quelques secondes, ne fermez pas la fenêtre.</span>';
      addLog('⏳ Moteur OptiPC indisponible : redémarrage, activation en attente');
      _optiWatchServer();
      setTimeout(()=>{
        let still=null; try{ still=sessionStorage.getItem('optipc_pending_key'); }catch(_){}
        if(still && st) st.innerHTML='<span style="color:var(--red)">❌ OptiPC ne répond plus. Fermez OptiPC (clic droit sur l\u2019icône près de l\u2019horloge → Quitter), rouvrez-le : la clé sera activée automatiquement. Besoin d\u2019aide : 05 54 54 23 43.</span>';
      },45000);
      loading(false);
      return;
    }
    // Le pont local a renvoye une erreur (ou rien). Il faut IMPERATIVEMENT
    // effacer le message precedent : sans cela l'ancien texte rouge (souvent
    // "Cette cle n'existe pas" d'un essai anterieur) restait affiche sous une
    // nouvelle cle parfaitement valide, et faisait croire a un refus du
    // serveur alors que la licence venait d'etre activee.
    const det=(e&&e.message)?e.message:'erreur locale';
    const msg="L'activation n'a pas pu etre finalisee sur cet ordinateur ("+det+"). "
             +"Si le serveur a accepte votre cle, fermez puis rouvrez OptiPC : la licence sera reprise automatiquement.";
    if(st)st.innerHTML='<span style="color:var(--red)">❌ '+msg+'</span>';
    addLog('❌ Activation interrompue : '+det);
    toast('Activation interrompue','err');
  }
  loading(false);
}

async function _doRevokeLicense(){
  loading(true,'Suppression de la licence...');
  try{
    await API.post('/api/license/revoke',{},20000);
    _isPro=false;
    _setFreeUI();
    const k=document.getElementById('lic-key'); if(k)k.value='';
    const st=document.getElementById('lic-status');
    if(st)st.innerHTML='<span style="color:var(--green)">Version gratuite active. Vous pouvez réactiver votre clé à tout moment.</span>';
    try{ localStorage.removeItem('optipc_pro_reminder'); }catch(e){}
    toast('Version gratuite activée','ok');
    addLog('Retour en version gratuite');
  }catch(e){toast('Erreur lors de la suppression','err');}
  loading(false);
}
async function loadOptiVersion(){
  try{ const v=await API.get('/api/version',8000); if(v&&v.version){ document.querySelectorAll('.opti-ver').forEach(e=>e.textContent='v'+v.version); } }catch(e){}
}
setTimeout(loadOptiVersion,1500);
function revokeLicense(){
  showConfirm('Repasser en version gratuite ?',
    "La clé Premium enregistrée sur cet ordinateur va être supprimée et les fonctions Premium seront de nouveau verrouillées. Vous pourrez réactiver la même clé quand vous le souhaitez.",
    _doRevokeLicense);
}

async function loadProStatus(){
  try{
    const d=await API.get('/api/license/status');
    if(d.trialUsed){_trialUsed=true;}
    if(d.trialEnded){_trialEnded=true;}
    if(d.isPro){_isPro=true;_setProUI(d);_maybeTrialEndingReminder(d);}
    else{_isPro=false;_setFreeUI();}
    _syncTrialButtons();
  }catch(e){}
}

function _setFreeUI(){
  // Bouton sidebar
  const btn=document.getElementById('btn-activate-pro');
  if(btn){
    btn.textContent='Passer en Premium';
    btn.style.background='linear-gradient(135deg,var(--purple),var(--purple2))';
    btn.style.cursor='pointer';
    btn.onclick=()=>{showSec('params',document.querySelector('[data-sec=params]'));const c=document.getElementById('card-compare');if(c)setTimeout(()=>c.scrollIntoView({behavior:'smooth',block:'start'}),120);};
  }
  // Bandeau statut
  const banner=document.getElementById('lic-banner');
  if(banner){
    banner.style.background='rgba(100,116,139,.12)';
    banner.style.border='1px solid rgba(100,116,139,.2)';
  }
  const label=document.getElementById('lic-plan-label');
  if(label){label.textContent='Version Gratuite';label.style.color='var(--text)';}
  const sub=document.getElementById('lic-plan-sub');
  if(sub)sub.textContent='Fonctionnalités limitées';
  // Boutons actif/inactif
  const btnFree=document.getElementById('btn-lic-free');
  const btnPro=document.getElementById('btn-lic-pro');
  if(btnFree){btnFree.style.background='rgba(100,116,139,.4)';btnFree.style.color='#e2e8f0';btnFree.style.borderColor='rgba(100,116,139,.8)';}
  if(btnPro){btnPro.style.background='rgba(var(--acc-rgb),.1)';btnPro.style.color='var(--acc-text)';btnPro.style.borderColor='rgba(var(--acc-rgb),.4)';}
  // Zones
  document.getElementById('lic-activate-zone').style.display='';
  document.getElementById('lic-pro-zone').style.display='none';
  // Re-afficher les cadenas et badges PRO (indispensable apres un retour au gratuit)
  document.querySelectorAll('.badge-pro').forEach(b=>b.style.display='');
  renderPlanCompare();
  if(window._lastScanData)buildRecs(window._lastScanData);
}

function _setProUI(info){
  // Bouton sidebar
  const btn=document.getElementById('btn-activate-pro');
  if(btn){
    btn.textContent='✅ Premium actif';
    btn.style.background='linear-gradient(135deg,#22c55e,#16a34a)';
    btn.style.cursor='default';
    btn.onclick=null;
  }
  // Bandeau statut
  const banner=document.getElementById('lic-banner');
  if(banner){
    banner.style.background='linear-gradient(135deg,rgba(var(--acc-rgb),.15),rgba(var(--acc-rgb),.05))';
    banner.style.border='1px solid rgba(var(--acc-rgb),.35)';
  }
  const label=document.getElementById('lic-plan-label');
  if(label){label.textContent=(info&&info.trial)?'🎁 Essai Premium gratuit':'✅ Version Premium active';label.style.color='var(--acc-text)';}
  // Durée active
  const sub=document.getElementById('lic-plan-sub');
  if(sub && info && info.trial && info.expires_at){
    let fin=info.expires_at;
    try{ fin=new Date(info.expires_at+'T12:00:00').toLocaleDateString('fr-FR',{day:'numeric',month:'long'}); }catch(e){}
    sub.textContent='Se termine le '+fin;
  } else if(sub && info){
    if(info.days_active!=null && info.days_active>=0){
      const d=info.days_active;
      sub.textContent='Actif depuis '+(d===0?"aujourd'hui":d+' jour'+(d>1?'s':''));
    } else {
      sub.textContent='Licence active';
    }
  }
  // Boutons actif/inactif
  const btnFree=document.getElementById('btn-lic-free');
  const btnPro=document.getElementById('btn-lic-pro');
  if(btnFree){btnFree.style.background='rgba(100,116,139,.1)';btnFree.style.color='#475569';btnFree.style.borderColor='rgba(100,116,139,.2)';}
  if(btnPro){btnPro.style.background='rgba(var(--acc-rgb),.35)';btnPro.style.color='#e2d9f3';btnPro.style.borderColor='rgba(var(--acc-rgb),.8)';}
  // Zones
  document.getElementById('lic-activate-zone').style.display='none';
  const proZone=document.getElementById('lic-pro-zone');
  if(proZone){
    proZone.style.display='';
    const det=document.getElementById('lic-pro-details');
    if(det && info){
      let h='';
      if(info.activated_at){
        const d=new Date(info.activated_at);
        h+='<div>📅 Activé le <strong style="color:var(--text)">'+d.toLocaleDateString('fr-FR',{day:'2-digit',month:'long',year:'numeric'})+'</strong></div>';
      }
      if(info.days_active!=null){
        h+='<div>⏱️ Actif depuis : <strong style="color:var(--text)">'+info.days_active+' jour'+(info.days_active>1?'s':'')+'</strong></div>';
      }
      if(info.key_display){
        h+='<div>🔑 Clé : <span style="font-family:monospace;color:var(--purple)">'+info.key_display+'</span></div>';
      }
      det.innerHTML=h;
    }
  }
  // Enlever badges PRO redondants
  document.querySelectorAll('.badge-pro').forEach(b=>b.style.display='none');
  renderPlanCompare();
  if(window._lastScanData)buildRecs(window._lastScanData);
}

function isPro(){return _isPro;}

/* ══════════════════════════════════════════════════════════════════════════
   MISES A JOUR
   Verification au demarrage, au plus une fois tous les 30 jours. Le poste
   n'installe jamais rien sans que l'utilisateur ait vu et accepte, sauf
   correctif de securite marque comme obligatoire.
   ══════════════════════════════════════════════════════════════════════════ */
let _updInfo=null;

function _fmtMo(o){ return o&&o>0 ? ' ('+(o/1048576).toFixed(0)+' Mo)' : ''; }

async function checkUpdate(force){
  try{
    const d=await API.post('/api/update/check',{force:!!force},40000);
    if(!d||!d.update_available){
      // Le serveur confirme qu'il n'y a rien : on retire un bandeau
      // eventuellement affiche. En cas de coupure reseau on ne touche a rien,
      // pour ne pas faire disparaitre une mise a jour deja annoncee.
      if(d && d.checked && !d.offline){
        document.getElementById('upd-bar').classList.remove('show');
        _updInfo=null;
      }
      if(force){
        if(d&&d.offline) toast('Vérification impossible : pas de connexion Internet','info');
        else toast('OptiPC est à jour (version '+((d&&d.current)||'?')+')','ok');
      }
      return null;
    }
    _updInfo=d;
    const bar=document.getElementById('upd-bar');
    document.getElementById('upd-title').textContent =
      d.mandatory ? 'Mise à jour de sécurité importante' : "Une nouvelle version d'OptiPC est disponible";
    document.getElementById('upd-sub').textContent =
      'Version '+d.version+_fmtMo(d.size)+(d.notes?' — '+d.notes:'')+
      (d.mandatory?" — cette mise à jour corrige un problème de sécurité." : '');
    document.getElementById('upd-later').style.display = d.mandatory ? 'none' : '';
    bar.classList.add('show');
    addLog('Mise à jour disponible : version '+d.version);
    return d;
  }catch(e){
    if(force)toast('Vérification impossible','err');
    return null;
  }
}

function dismissUpdate(){
  document.getElementById('upd-bar').classList.remove('show');
  toast('Vous pourrez l\u2019installer plus tard depuis Paramètres','info');
}

async function installUpdate(){
  if(!_updInfo)return;
  const go=document.getElementById('upd-go');
  go.disabled=true; go.textContent='Téléchargement...';
  loading(true,'Téléchargement de la mise à jour...');
  try{
    const r=await API.post('/api/update/install',{url:_updInfo.url,sha256:_updInfo.sha256},900000);
    if(r&&r.success){
      toast('Installation lancée, OptiPC va redémarrer','ok');
      addLog('Mise à jour '+_updInfo.version+' installée');
    } else {
      toast((r&&r.error)||'Installation impossible','err');
      addLog('Échec de la mise à jour : '+((r&&r.error)||'inconnu'));
      go.disabled=false; go.textContent='Réessayer';
    }
  }catch(e){
    toast('Installation impossible','err');
    go.disabled=false; go.textContent='Réessayer';
  }
  loading(false);
}


/* ══════════════════════════════════════════════════════════════════════════
   PREMIER LANCEMENT : CLUF ET POLITIQUE DE CONFIDENTIALITE
   ══════════════════════════════════════════════════════════════════════════ */
function _clufHtml(){
  const A=_edAdresse();
  return ''
  +'<p style="font-size:11px;color:var(--muted);margin-bottom:14px">CONTRAT DE LICENCE UTILISATEUR FINAL &middot; OptiPC &middot; Version '+CONSENT_VERSION+' du '+EDITEUR.dateCG+'</p>'
  +'<p><strong>1. Parties</strong><br>Le present contrat est conclu entre vous, utilisateur du logiciel, et <strong>'+EDITEUR.societe+'</strong>'+_edIdentiteSuite()+'. Le logiciel est diffuse sous la marque '+EDITEUR.marque+'.</p>'
  +'<p><strong>2. Acceptation</strong><br>L\u2019installation et l\u2019utilisation d\u2019OptiPC valent acceptation du present contrat. Si vous refusez ces conditions, n\u2019utilisez pas le logiciel : cliquez sur « Refuser et fermer », puis desinstallez-le.</p>'
  +'<p><strong>3. Objet de la licence</strong><br>'+EDITEUR.societe+' vous concede un droit d\u2019utilisation personnel, non exclusif, non cessible et revocable. Le logiciel n\u2019est pas vendu, il est concede sous licence : le code, les marques, les textes et les elements graphiques demeurent la propriete de l\u2019editeur.</p>'
  +'<p><strong>4. Version gratuite et version Premium</strong><br>La version gratuite est utilisable sans limitation de duree. La version Premium, souscrite par abonnement, debloque des fonctions supplementaires detaillees dans le logiciel et sur '+EDITEUR.site+'. Un abonnement autorise l\u2019usage sur le nombre d\u2019ordinateurs indique lors de la souscription.</p>'
  +'<p><strong>5. Ce que vous vous engagez a ne pas faire</strong><br>Revendre, louer ou preter votre cle ; la diffuser publiquement ; contourner ou tenter de contourner le mecanisme de licence ; decompiler ou modifier le logiciel en dehors des cas autorises par la loi. Le non-respect de ces regles entraine la resiliation immediate de la licence, sans remboursement.</p>'
  +'<p><strong>6. Nature du logiciel</strong><br>OptiPC est un utilitaire de maintenance et d\u2019optimisation. Il detecte les programmes indesirables et les comportements suspects, mais <strong>il ne remplace pas un antivirus resident</strong> et ne garantit ni la suppression de toute menace, ni un gain de performance chiffre.</p>'
  +'<p><strong>7. Operations irreversibles et sauvegarde</strong><br>Le nettoyage, la desinstallation forcee, la suppression forcee de fichiers et la modification du registre sont <strong>definitifs</strong>. Ils ne sont jamais declenches sans votre confirmation explicite. <strong>Sauvegardez vos donnees importantes avant toute operation.</strong></p>'
  +'<p><strong>8. Fausses alertes</strong><br>La detection repose en partie sur des criteres de comportement : un fichier legitime peut etre signale a tort. Preferez toujours la mise en quarantaine, qui est reversible, a la suppression definitive. En cas de doute, appelez le '+EDITEUR.tel+' avant d\u2019agir.</p>'
  +'<p><strong>9. Mises a jour</strong><br>Le logiciel verifie regulierement la disponibilite d\u2019une nouvelle version et vous la propose. Les correctifs de securite peuvent etre installes automatiquement. Aucune mise a jour n\u2019est installee sans que vous en soyez informe.</p>'
  +'<p><strong>10. Garantie et responsabilite</strong><br>Vous beneficiez de la garantie legale de conformite applicable aux contenus numeriques. '+EDITEUR.societe+' ne saurait etre tenue responsable des pertes de donnees resultant d\u2019une operation que vous avez confirmee, d\u2019une configuration particuliere de votre poste ou de l\u2019action d\u2019un autre programme. Sa responsabilite ne peut exceder les sommes effectivement versees au titre de la licence, sans limiter sa responsabilite en cas de faute lourde, de dol ou d\u2019atteinte aux personnes.</p>'
  +'<p><strong>11. Assistance et securite</strong><br>L\u2019assistance repond au '+EDITEUR.tel+' et a '+EDITEUR.mail+'. <strong>Aucun collaborateur ne vous demandera jamais vos mots de passe, vos codes de carte bancaire, ni un paiement par carte cadeau.</strong> Si quelqu\u2019un vous appelle en se reclamant d\u2019OptiPC, raccrochez et rappelez le numero ci-dessus.</p>'
  +'<p><strong>12. Droit applicable</strong><br>Le present contrat est regi par le droit des Emirats arabes unis. Ce choix ne peut priver le consommateur residant dans l\u2019Union europeenne de la protection que lui assurent les dispositions imperatives du droit de son pays de residence habituelle, notamment en matiere de retractation, de garantie legale et de protection des donnees. Les conditions generales de vente completes sont consultables dans Parametres, rubrique A propos.</p>';
}

function _rgpdHtml(){
  const A=_edAdresse();
  return ''
  +'<p style="font-size:11px;color:var(--muted);margin-bottom:14px">POLITIQUE DE CONFIDENTIALITE &middot; Version '+CONSENT_VERSION+' du '+EDITEUR.dateCG+'</p>'
  +'<p style="background:rgba(34,197,94,.1);border:1px solid rgba(34,197,94,.25);border-radius:9px;padding:11px 13px;color:var(--green)"><strong>L\u2019essentiel :</strong> OptiPC analyse votre ordinateur <strong>localement</strong>. La liste de vos fichiers, vos documents et vos photos ne sont jamais envoyes a l\u2019editeur ni a personne d\u2019autre.</p>'
  +'<p><strong>1. Responsable du traitement</strong><br>'+EDITEUR.societe+_edIdentiteSuite()+'. Contact : '+EDITEUR.mail+' &mdash; '+EDITEUR.tel+'.</p>'
  +'<p><strong>1 bis. Representant dans l\u2019Union europeenne</strong><br>L\u2019editeur est etabli hors de l\u2019Union europeenne mais propose OptiPC a des personnes qui y resident : le RGPD s\u2019applique. Conformement a son article 27, un representant dans l\u2019Union est designe pour recevoir vos demandes : '+_edRepUE()+'.</p>'
  +'<p><strong>2. Ce qui reste sur votre ordinateur</strong><br>Les resultats d\u2019analyse, l\u2019historique d\u2019activite, vos reglages et votre cle de licence sont enregistres uniquement sur votre poste, dans votre dossier utilisateur. Vous pouvez les effacer a tout moment depuis Parametres.</p>'
  +'<p><strong>3. Ce qui est transmis a l\u2019editeur</strong><br>Uniquement si vous activez la version Premium : votre cle de licence, un identifiant technique de l\u2019ordinateur (une empreinte chiffree, qui ne permet pas de vous identifier personnellement), le nom de l\u2019ordinateur, la version de Windows et la version d\u2019OptiPC. Ces informations servent exclusivement a verifier que votre abonnement est valide et a limiter l\u2019usage au nombre de postes souscrits.</p>'
  +'<p><strong>4. Achat</strong><br>En cas de souscription, votre nom, votre adresse electronique et vos donnees de facturation sont traites pour executer le contrat et etablir la facture. Le paiement est traite par un prestataire externe : <strong>l\u2019editeur n\u2019a jamais acces au numero complet de votre carte bancaire.</strong></p>'
  +'<p><strong>5. Bases legales</strong><br>Execution du contrat pour la gestion de la licence et de l\u2019abonnement ; obligation legale pour la conservation des documents comptables ; interet legitime pour la securite du service et la lutte contre la fraude.</p>'
  +'<p><strong>6. Duree de conservation</strong><br>Les donnees liees a la licence sont conservees pendant la duree de l\u2019abonnement, puis pendant la duree legale de conservation des pieces comptables. Les donnees locales restent sur votre ordinateur jusqu\u2019a ce que vous les effaciez ou desinstalliez le logiciel.</p>'
  +'<p><strong>7. Destinataires</strong><br>Aucune donnee n\u2019est revendue ni cedee a des fins publicitaires. Seuls interviennent nos prestataires techniques : hebergement du service de licences et prestataire de paiement, tenus par contrat a la confidentialite.</p>'
  +'<p><strong>7 bis. Transferts hors de l\u2019Union europeenne</strong><br>L\u2019editeur etant etabli aux Emirats arabes unis, les donnees liees a votre licence peuvent etre consultees depuis ce pays. Ces transferts sont encadres par les clauses contractuelles types adoptees par la Commission europeenne. Une copie de ces garanties peut etre obtenue en ecrivant a '+EDITEUR.mail+'.</p>'
  +'<p><strong>8. Vos droits</strong><br>Vous disposez d\u2019un droit d\u2019acces, de rectification, d\u2019effacement, de limitation, d\u2019opposition et de portabilite. Ecrivez a '+EDITEUR.mail+', appelez le '+EDITEUR.tel+', ou adressez-vous au representant mentionne a l\u2019article 1 bis. Vous pouvez aussi saisir l\u2019autorite de protection des donnees de votre pays de residence : en France la CNIL, en Belgique l\u2019APD, au Luxembourg la CNPD.</p>'
  +'<p><strong>9. Clients professionnels</strong><br>Si vous utilisez OptiPC dans un cadre professionnel et que l\u2019editeur traite des donnees pour votre compte, un accord de sous-traitance conforme a l\u2019article 28 du RGPD (DPA) est disponible sur simple demande a '+EDITEUR.mail+'.</p>';
}

function showConsentDoc(which){
  document.getElementById('cs-tab-cluf').classList.toggle('active', which==='cluf');
  document.getElementById('cs-tab-rgpd').classList.toggle('active', which==='rgpd');
  const d=document.getElementById('cs-doc');
  d.innerHTML = which==='rgpd' ? _rgpdHtml() : _clufHtml();
  d.scrollTop=0;
}

function showConsentGate(){
  showConsentDoc('cluf');
  document.getElementById('cs-ok').checked=false;
  document.getElementById('cs-accept').disabled=true;
  document.getElementById('consent-ov').classList.add('show');
}

async function acceptConsent(){
  if(!document.getElementById('cs-ok').checked)return;
  try{ await API.post('/api/consent',{version:CONSENT_VERSION},15000); }catch(e){}
  document.getElementById('consent-ov').classList.remove('show');
  addLog('Conditions acceptées (version '+CONSENT_VERSION+')');
  if(!_isPro){ setTimeout(showWelcomeOnce,700); }
}

function refuseConsent(){
  showConfirm('Fermer OptiPC ?',
    "Sans acceptation du contrat de licence, le logiciel ne peut pas être utilisé. OptiPC va se fermer. Vous pourrez le relancer et accepter plus tard.",
    async function(){ try{ await API.post('/api/quit',{},8000); }catch(e){} try{ window.close(); }catch(e){} });
}

/* ── Fermeture de la fenetre de bienvenue ── */
/* Le message d'invitation a passer Pro ne doit apparaitre qu'UNE SEULE fois,
   au lancement. Ce verrou couvre toute la session : rechargement de page,
   rappel horaire, retour depuis un autre ecran. */
let _welcomeAlreadyShown=false;
function showWelcomeOnce(){
  if(_welcomeAlreadyShown)return;
  _welcomeAlreadyShown=true;
  const ov=document.getElementById('welcome-ov');
  if(ov)ov.style.display='flex';
}
function closeWelcome(){
  const ov=document.getElementById('welcome-ov');
  if(ov)ov.style.display='none';
}
document.addEventListener('keydown',function(e){
  if(e.key!=='Escape')return;
  const w=document.getElementById('welcome-ov');
  if(w&&w.style.display==='flex'){ closeWelcome(); return; }
  const c=document.getElementById('_cgu'); if(c){ c.remove(); return; }
  const t=document.getElementById('trial-ov'); if(t&&t.classList.contains('show')){ closeTrial(); return; }
  const g=document.getElementById('pro-gate-ov'); if(g&&g.classList.contains('show')){ closeProGate(); }
});


/* ── COMPARATIF GRATUIT / PRO ────────────────────────────────────────────── */
const PLAN_FREE=[
  {t:'Analyse complète de l\u2019ordinateur',ok:1},
  {t:'Nettoyage des fichiers inutiles et des caches',ok:1},
  {t:'Optimisation mémoire, démarrage et effets visuels',ok:1},
  {t:'Modes d\u2019alimentation (économie, équilibré, performances)',ok:1},
  {t:'Désinstallation des logiciels',ok:1},
  {t:'Détection des virus et logiciels espions',ok:1},
  {t:'Suppression des menaces trouvées',ok:0},
  {t:'Mise en quarantaine réversible',ok:0},
  {t:'Nettoyage avancé et nettoyage du registre',ok:0},
  {t:'Nettoyage automatique planifié',ok:0},
  {t:'Assistance téléphonique prioritaire',ok:0}
];
const PLAN_PRO=[
  {t:'Tout ce que contient la version gratuite',hot:0},
  {t:'Supprime réellement les menaces détectées',hot:1},
  {t:'Quarantaine réversible : zéro risque de fausse alerte',hot:1},
  {t:'Nettoyage avancé + registre : les Go que le gratuit laisse',hot:1},
  {t:'Nettoyage automatique planifié, PC propre sans y penser',hot:1},
  {t:'Assistance téléphonique prioritaire au '+EDITEUR.tel,hot:1},
  {t:'Mises à jour incluses',hot:0},
  {t:EDITEUR.dureePro,hot:0}
];
function renderPlanCompare(){
  const el=document.getElementById('plan-compare');
  if(!el)return;
  const P=_edPrix();
  const freeCur=_isPro?'':'<span class="cmp-badge-cur">Votre version</span>';
  const proCur =_isPro?'<span class="cmp-badge-cur">Votre version</span>':'';
  let h='<div class="cmp-wrap">';

  h+='<div class="cmp-col">'
    +'<div class="cmp-head">Gratuit'+freeCur+'</div>'
    +'<div class="cmp-sub">Pour voir ce qui ne va pas sur votre PC et faire le ménage de base.</div>'
    +'<div class="cmp-price" style="color:var(--dim)">0 €<small>Sans limite de durée, sans publicité</small></div>'
    +'<ul class="cmp-list">'
    + PLAN_FREE.map(function(f){
        return '<li class="cmp-li'+(f.ok?'':' no')+'"><span class="ic">'+(f.ok?'✅':'🔒')+'</span><span>'+f.t+'</span></li>';
      }).join('')
    +'</ul>'
    + (_isPro
        ? '<button class="cmp-cta ghost" onclick="revokeLicense()">Revenir à la version gratuite</button>'
        : '<button class="cmp-cta ghost" style="cursor:default" disabled>Version actuellement utilisée</button>')
    +'</div>';

  h+='<div class="cmp-col pro">'
    +'<div class="cmp-ribbon">Recommandé</div>'
    +'<div class="cmp-head">⭐ Premium'+proCur+'</div>'
    +'<div class="cmp-sub">Pour qu\u2019OptiPC répare vraiment, tout seul, et que quelqu\u2019un décroche quand vous appelez.</div>'
    + (P ? '<div class="cmp-price">'+P+'<small>Paiement unique &middot; '+EDITEUR.dureePro+'</small></div>'
         : '<div class="cmp-price" style="font-size:17px;line-height:1.35">Tarif au '+EDITEUR.tel+'<small>'+EDITEUR.dureePro+'</small></div>')
    +'<ul class="cmp-list">'
    + PLAN_PRO.map(function(f){
        return '<li class="cmp-li'+(f.hot?' hot':'')+'"><span class="ic">'+(f.hot?'⭐':'✅')+'</span><span>'+f.t+'</span></li>';
      }).join('')
    +'</ul>'
    + (_isPro
        ? '<button class="cmp-cta buy" style="cursor:default" disabled>✅ Version Premium active</button>'
        : '<button class="cmp-cta buy" onclick="openBuyPage()">S\u2019abonner à la version Premium</button>'
          +'<button class="cmp-cta ghost" style="margin-top:8px" onclick="goActivate()">J\u2019ai déjà une clé</button>')
    +'<div class="cmp-foot">'+(_isPro?'Merci de votre confiance.':'Une question avant d\u2019acheter ? Appelez le <strong style="color:var(--dim)">'+EDITEUR.tel+'</strong>, un technicien répond en français.')+'</div>'
    +'</div>';

  h+='</div>';
  el.innerHTML=h;

  const ab=document.getElementById('about-editeur');
  if(ab){
    ab.innerHTML='Édité par <strong style="color:var(--dim)">'+EDITEUR.societe+'</strong><br>'
      +(EDITEUR.licence ? ('Licence commerciale n° '+EDITEUR.licence+(EDITEUR.autorite?(' — '+EDITEUR.autorite):'')+'<br>') : '')
      +(_edAdresse() ? (_edAdresse()+'<br>') : '')
      +'© 2026 '+EDITEUR.societe+' — marque '+EDITEUR.marque;
  }
}
function goActivate(){
  showSec('params',document.querySelector('[data-sec=params]'));
  const k=document.getElementById('lic-key');
  if(k){ setTimeout(function(){ k.scrollIntoView({behavior:'smooth',block:'center'}); k.focus(); },120); }
}
function ifPro(fn,msg){if(_isPro)fn();else showProGate(msg);}
function showProGate(msg){document.getElementById('pro-gate-msg').textContent=msg||'Fonction Premium';_syncTrialButtons();document.getElementById('pro-gate-ov').classList.add('show');}

/* ── ESSAI PRO GRATUIT 5 JOURS ─────────────────────────────────────────── */
let _trialUsed=false,_trialEnded=false;
function _trialAvailable(){
  let used=_trialUsed;
  try{ if(localStorage.getItem('optipc_trial_used')==='1')used=true; }catch(e){}
  return !_isPro && !used && !_trialEnded;
}
function _syncTrialButtons(){
  const ok=_trialAvailable();
  ['pro-gate-trial','welcome-trial'].forEach(id=>{const b=document.getElementById(id); if(b)b.style.display=ok?'':'none';});
}
function openTrial(){
  if(!_trialAvailable()){ openBuyPage(); return; }
  document.getElementById('trial-form-zone').style.display='';
  document.getElementById('trial-ok-zone').style.display='none';
  const e=document.getElementById('trial-err'); e.style.display='none';
  document.getElementById('trial-ov').classList.add('show');
  setTimeout(()=>{const p=document.getElementById('tr-prenom'); if(p)p.focus();},80);
}
function closeTrial(){ document.getElementById('trial-ov').classList.remove('show'); }
function _trialErr(m){ const e=document.getElementById('trial-err'); e.textContent=m; e.style.display=''; }
async function startTrial(){
  const prenom=document.getElementById('tr-prenom').value.trim();
  const email=document.getElementById('tr-email').value.trim();
  const telephone=document.getElementById('tr-tel').value.trim();
  const r=document.querySelector('input[name=tr-rappel]:checked');
  if(!prenom){ _trialErr('Indiquez votre prénom.'); return; }
  if(!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(email)){ _trialErr('Indiquez une adresse e-mail valide.'); return; }
  if(telephone.replace(/\D/g,'').length<9){ _trialErr('Indiquez un numéro de téléphone valide.'); return; }
  if(!r){ _trialErr("Choisissez Oui ou Non pour être rappelé(e)."); return; }
  const btn=document.getElementById('trial-go');
  btn.disabled=true; btn.textContent='Activation en cours…';
  try{
    const d=await API.post('/api/license/trial',{prenom,email,telephone,rappel:r.value},90000);
    if(d && d.ok){
      try{ localStorage.setItem('optipc_trial_used','1'); }catch(e){}
      _trialUsed=true; _isPro=true; _setProUI(d);
      let fin='';
      if(d.expires_at){ try{ fin=new Date(d.expires_at+'T12:00:00').toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long'}); }catch(e){} }
      document.getElementById('trial-ok-msg').innerHTML='Toutes les fonctions Premium sont débloquées'+(fin?' jusqu’au <strong style="color:var(--text)">'+fin+'</strong>':' pendant 5 jours')+'.<br>Relancez une analyse : vous pouvez maintenant supprimer les menaces détectées.';
      document.getElementById('trial-form-zone').style.display='none';
      document.getElementById('trial-ok-zone').style.display='';
      addLog('🎁 Essai Premium gratuit activé');
    } else {
      if(d && d.already){ try{ localStorage.setItem('optipc_trial_used','1'); }catch(e){} _trialUsed=true; _syncTrialButtons(); }
      _trialErr((d&&d.message)||"L'essai n'a pas pu démarrer. Appelez le 05 54 54 23 43.");
    }
  }catch(e){
    _trialErr("L'essai n'a pas pu démarrer ("+((e&&e.message)||'erreur locale')+"). Vérifiez votre connexion internet.");
  }
  btn.disabled=false; btn.textContent='Activer mon essai Premium gratuit';
}
function _trialDaysLeft(exp){
  try{ const end=new Date(exp+'T23:59:59'); return Math.ceil((end-new Date())/86400000); }catch(e){ return null; }
}
function _maybeTrialEndingReminder(info){
  if(!info||!info.trial||!info.expires_at)return;
  const left=_trialDaysLeft(info.expires_at);
  if(left==null||left>1)return;
  const _d=new Date(), _k=_d.getFullYear()+'-'+(_d.getMonth()+1)+'-'+_d.getDate();
  try{ if(localStorage.getItem('optipc_trial_ending')===_k)return; localStorage.setItem('optipc_trial_ending',_k); }catch(e){}
  setTimeout(()=>showProGate((left<=0?"Votre essai Premium se termine aujourd'hui.":"Votre essai Premium se termine demain.")+" Gardez la suppression des menaces et le nettoyage automatique : abonnez-vous à OptiPC Premium (offre -50 %)."),2500);
}
function closeProGate(){document.getElementById('pro-gate-ov').classList.remove('show');}

async function doSFC(btn){
  const orig=btn?btn.innerHTML:'';
  if(btn){btn.disabled=true;btn.innerHTML='<div class="spin" style="width:14px;height:14px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:6px"></div>Analyse en cours... (peut prendre plusieurs minutes)';}
  showRepairProgress('Analyse des fichiers système Windows (SFC)...');
  try{
    const r=await API.post('/api/repair',{action:'sfc'});
    toast('✅ '+(r.output||'Réparation SFC terminée'),'ok');
    addLog('SFC: '+( r.output||'terminé'));
  }catch(e){toast('❌ Erreur SFC: '+e.message,'err');}
  hideRepairProgress();
  if(btn){btn.disabled=false;btn.innerHTML=orig;}
}

async function loadVirtMem(){
  try{
    const d=await API.get('/api/virtmem');
    const el=document.getElementById('virt-desc');
    const bar=document.getElementById('virt-bar');
    const detail=document.getElementById('virt-detail');
    if(d&&d.totalMB){
      const pct=Math.round((d.usedMB/d.totalMB)*100);
      if(el)el.textContent='Espace disque utilisé comme RAM d\'appoint';
      if(bar)bar.style.width=pct+'%';
      if(detail)detail.textContent=d.usedMB+'Mo utilisés / '+d.totalMB+'Mo alloués ('+pct+'%)';
    }else{
      if(el)el.textContent='Mémoire virtuelle gérée automatiquement par Windows';
      if(detail)detail.textContent='Taille : automatique';
    }
  }catch(e){
    const el=document.getElementById('virt-desc');
    if(el)el.textContent='Mémoire virtuelle (fichier d\'échange Windows)';
  }
}

async function optimizeVirtMem(btn){
  showConfirm('Optimiser la mémoire virtuelle ?','Windows va reconfigurer le fichier d\'échange pour de meilleures performances. Un redémarrage peut être nécessaire.',async()=>{
    loading(true,'Optimisation de la mémoire virtuelle...');
    try{
      const r=await API.post('/api/repair',{action:'virtmem_optimize'});
      toast('✅ '+(r.output||'Mémoire virtuelle optimisée'),'ok');
    }catch(e){toast('❌ '+e.message,'err');}
    loading(false);
    loadVirtMem();
  });
}

function setVirtMem(sizeMB,btn){
  document.querySelectorAll('.vm-size-btn').forEach(b=>b.classList.remove('vm-active'));
  if(btn)btn.classList.add('vm-active');
  const label=sizeMB===0?'automatique':(sizeMB/1024)+' Go';
  showConfirm('Modifier la mémoire virtuelle ?','Taille : '+label+'. Un redémarrage sera nécessaire pour appliquer.',async()=>{
    loading(true,'Configuration mémoire virtuelle...');
    try{const r=await API.post('/api/repair',{action:'virtmem_set',sizeMB});toast('✅ '+(r.output||'Configuré — redémarrez'),'ok');loadVirtMem();}
    catch(e){toast('❌ '+e.message,'err');}
    loading(false);
  });
}

let _repairAbort=null;
function showRepairProgress(label,onCancel){
  const old=document.getElementById('_repbar');if(old)old.remove();
  const el=document.createElement('div');el.id='_repbar';
  el.style.cssText='position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:var(--card);border:1px solid rgba(var(--acc-rgb),.4);border-radius:12px;padding:14px 22px;min-width:340px;z-index:9998;box-shadow:0 8px 24px rgba(0,0,0,.5);backdrop-filter:blur(8px)';
  el.innerHTML='<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px"><div style="display:flex;align-items:center;gap:8px"><div class="spin" style="width:14px;height:14px;border-width:2px"></div><span style="font-size:12px;font-weight:700;color:var(--text)">'+label+'</span></div><div style="display:flex;align-items:center;gap:10px"><span style="font-size:13px;font-weight:900;color:var(--purple)" id="_rppct">0%</span><button onclick="cancelRepair()" style="border:none;background:rgba(248,81,73,.15);color:var(--red);border-radius:6px;padding:3px 10px;font-size:11px;font-weight:700;cursor:pointer;font-family:inherit">✕ Annuler</button></div></div><div style="height:4px;background:rgba(var(--inv-rgb),.07);border-radius:2px;overflow:hidden"><div id="_rpfill" style="height:100%;width:0%;border-radius:2px;background:linear-gradient(90deg,var(--purple),var(--purple));transition:width .35s"></div></div>';
  document.body.appendChild(el);
  _repairAbort={cancelled:false,_t:0,onCancel,timer:null};
  _repairAbort.timer=setInterval(()=>{
    _repairAbort._t++;
    const pct=Math.min(90,Math.round(90*(1-Math.exp(-_repairAbort._t/25))));
    const f=document.getElementById('_rpfill');if(f)f.style.width=pct+'%';
    const p=document.getElementById('_rppct');if(p)p.textContent=pct+'%';
    if(_repairAbort.cancelled){clearInterval(_repairAbort.timer);hideRepairProgress();}
  },400);
}
function hideRepairProgress(){
  if(_repairAbort&&_repairAbort.timer)clearInterval(_repairAbort.timer);
  const f=document.getElementById('_rpfill');if(f)f.style.width='100%';
  const p=document.getElementById('_rppct');if(p)p.textContent='100%';
  setTimeout(()=>{const b=document.getElementById('_repbar');if(b)b.remove();},700);
}
function cancelRepair(){
  if(_repairAbort){_repairAbort.cancelled=true;if(_repairAbort.onCancel)_repairAbort.onCancel();}
  hideRepairProgress();
  toast('Opération annulée','info');
}

window.onload=async()=>{
  // Injecter bouton son dans topbar
  try{
    const wc=document.querySelector('.wc-btns');
    if(wc){
      const sb=document.createElement('button');
      sb.id='btn-sound';sb.className='wc-btn';
      sb.textContent='🔊';sb.title='Son (cliquer pour couper)';
      sb.style.cssText='font-size:13px;opacity:0.7;margin-right:4px;';
      sb.onclick=toggleSound;
      wc.insertBefore(sb,wc.firstChild);
    }
    const sv=localStorage.getItem('optipc_sound');
    if(sv==='0'){_soundEnabled=false;const b=document.getElementById('btn-sound');if(b)b.textContent='🔇';}
  }catch(e){}
  loadPersistedLogs();
  await loadProStatus();
  // Controle de licence aupres du serveur : applique immediatement une
  // desactivation faite depuis le tableau de bord. Le serveur limite
  // lui-meme la frequence ; hors ligne, rien n'est coupe.
  setTimeout(async()=>{
    try{
      const h=await API.post('/api/license/heartbeat',{force:false},30000);
      if(h&&h.revoked){ _isPro=false; _setFreeUI(); toast(h.message||'Licence desactivee','err'); }
      else if(h&&h.warning){ toast(h.warning,'info'); }
    }catch(e){}
  }, 8000);
  let _consentOk=true;
  try{
    const c=await API.get('/api/consent',15000);
    _consentOk = !!(c && c.accepted && c.version===CONSENT_VERSION);
  }catch(e){ _consentOk=true; }   // en cas de souci, on ne bloque jamais l'acces
  if(!_consentOk){
    setTimeout(showConsentGate,400);
  } else if(!_isPro){
    setTimeout(showWelcomeOnce,1800);
  }
  loadRam();loadDiskInfo();pollPerf();loadScheduleStatus();
  // Mises à jour : au démarrage (le serveur limite lui-même à une fois par
  // mois), puis toutes les 30 jours pour les PC laissés allumés en permanence.
  setTimeout(()=>{checkUpdate(false);}, 25000);
  // ATTENTION : un minuteur JavaScript ne peut pas depasser 2 147 483 647 ms
  // (environ 24,8 jours). Au-dela, la valeur deborde et la fonction est
  // rappelee EN BOUCLE, plusieurs fois par seconde. C'est ce qui saturait
  // le moteur d'OptiPC et empechait l'analyse d'avancer.
  // On repasse donc toutes les 6 heures ; c'est le serveur qui limite
  // reellement la verification a une fois par mois.
  setInterval(()=>{checkUpdate(false);}, 6*3600*1000);
  // Polling clean.log toutes les 30s pour détecter les nettoyages planifiés
  setInterval(()=>{ if(!document.hidden) loadCleanLog(); }, 180000);
};

// ── NETTOYAGE PLANIFIÉ : scan + clean automatique ──────────────────────────
// Fonction appelée par la tâche planifiée Windows (via /api/clean directement)
// ET disponible pour tests manuels
async function autoScanAndClean(){
  try{
    const d=await API.get('/api/analyze');
    const AUTO=['temp_win','thumbnails','d3d','shader_cache','wu_dl','delivery','wer','chrome','edge','brave','firefox','opera'];
    const sel=(d.items||[]).filter(i=>i.size>0&&AUTO.includes(i.id)).map(i=>i.id);
    if(!sel.length){addLog('Nettoyage auto: déjà propre');return {cleaned:'0 B'};}
    const r=await API.post('/api/clean',{selected:sel});
    addLog('Nettoyage auto: '+r.cleaned+' libérés');
    return r;
  }catch(e){addLog('Erreur nettoyage auto');throw e;}
}
// Historique graphiques (30 points = ~1 min)
const _ramHist=[];
const _cpuHist=[];
const _tempHist=[];
let _tempMax=100; // plafond dynamique (°C)

function _drawGraph(canvasId, data, color, bgColor){
  const c=document.getElementById(canvasId);if(!c)return;
  /* Historique vide au lancement : on ne dessine que les vraies mesures,
     calees a droite (avant, 40 zeros donnaient une fausse "montee"). */
  if(!data||!data.length)return;
  if(data.length===1)data=[data[0],data[0]];
  const ctx=c.getContext('2d');
  const W=c.width,H=c.height;
  ctx.clearRect(0,0,W,H);
  // Fond
  ctx.fillStyle='rgba(0,0,0,0.3)';
  ctx.roundRect(0,0,W,H,4);ctx.fill();
  // Grille légère
  ctx.strokeStyle='rgba(var(--inv-rgb),0.04)';ctx.lineWidth=1;
  for(let i=1;i<4;i++){ctx.beginPath();ctx.moveTo(0,H/4*i);ctx.lineTo(W,H/4*i);ctx.stroke();}
  // Dégradé sous la courbe
  const grad=ctx.createLinearGradient(0,0,0,H);
  grad.addColorStop(0,color.replace(')',',0.4)').replace('rgb','rgba'));
  grad.addColorStop(1,color.replace(')',',0)').replace('rgb','rgba'));
  // Courbe
  ctx.beginPath();
  const step=W/39, x0=W-(data.length-1)*step;
  for(let i=0;i<data.length;i++){
    const x=x0+i*step;
    const y=H-(data[i]/100)*H;
    i===0?ctx.moveTo(x,y):ctx.lineTo(x,y);
  }
  // Fermer et remplir le dégradé
  ctx.lineTo(W,H);ctx.lineTo(x0,H);ctx.closePath();
  ctx.fillStyle=grad;ctx.fill();
  // Ligne principale
  ctx.beginPath();
  for(let i=0;i<data.length;i++){
    const x=x0+i*step;const y=H-(data[i]/100)*H;
    i===0?ctx.moveTo(x,y):ctx.lineTo(x,y);
  }
  ctx.strokeStyle=color;ctx.lineWidth=1.5;ctx.stroke();
  // Point actuel
  const lastX=x0+(data.length-1)*step;
  const lastY=H-(data[data.length-1]/100)*H;
  ctx.beginPath();ctx.arc(lastX,lastY,2.5,0,Math.PI*2);
  ctx.fillStyle=color;ctx.fill();
}

async function pollPerf(){
  try{
    const d=await API.get('/api/perf',15000);
    const r=d.ram||{};
    const ram=Math.round(r.pct||0), cpu=Math.round(r.cpuPct||0);
    _ramHist.push(ram);if(_ramHist.length>40)_ramHist.shift();
    _cpuHist.push(cpu);if(_cpuHist.length>40)_cpuHist.shift();
    const sr=document.getElementById('sb-ram-pct');
    if(sr){sr.textContent=ram+'%';sr.style.color=ram>85?'var(--red)':ram>70?'var(--orange)':'var(--green)';}
    const sc=document.getElementById('sb-cpu-pct');
    if(sc){sc.textContent=cpu+'%';sc.style.color=cpu>80?'var(--red)':cpu>60?'var(--orange)':'var(--purple)';}
    const rd=document.getElementById('sb-ram-detail');
    if(rd&&r.used&&r.total)rd.textContent=r.used+' / '+r.total;
    const cd=document.getElementById('sb-cpu-detail');
    if(cd)cd.textContent=cpu<30?'Charge normale':cpu<60?'Charge moderee':'Charge elevee';
    _drawGraph('sb-ram-canvas',_ramHist,'rgb(63,185,80)');
    _drawGraph('sb-cpu-canvas',_cpuHist,'rgb(139,92,246)');

    const t=d.temp||{};
    const tv=document.getElementById('sb-temp-val'), td=document.getElementById('sb-temp-detail');
    if(t.available){
      const c=t.celsius;
      const col=c>=85?'var(--red)':c>=70?'var(--orange)':'#f97316';
      if(tv){tv.textContent=t.label;tv.style.color=col;}
      if(td)td.textContent=c>=85?'Critique':c>=70?'Chaud':'Normal';
      _tempMax=Math.max(_tempMax,c+5);
      _tempHist.push(Math.min(100,Math.round((c/_tempMax)*100)));
      if(_tempHist.length>40)_tempHist.shift();
      _drawGraph('sb-temp-canvas',_tempHist,'rgb(249,115,22)');
    }else{
      if(tv){tv.textContent='N/A';tv.style.color='var(--muted)';}
      if(td)td.textContent='Capteur non disponible';
      _tempHist.push(0);if(_tempHist.length>40)_tempHist.shift();
      _drawGraph('sb-temp-canvas',_tempHist,'rgb(71,85,105)');
    }

    const dr=(d.drives||[]);
    const c1=dr.find(x=>x.letter==='C:')||dr[0];
    const sd=document.getElementById('sb-disk-txt');
    if(sd&&c1)sd.textContent=c1.free||'--';
    const n=document.getElementById('sb-net-txt');
    if(n)n.textContent=d.net||'--';
    const so=document.getElementById('sb-self-txt');
    if(so&&d.self){so.textContent=d.self.cpu+' % · '+d.self.mem;so.style.color=d.self.cpu>=15?'var(--red)':d.self.cpu>=5?'var(--orange)':'var(--green)';}
  }catch(e){}
  _schedPerf();
}
/* Rythme des graphiques : toutes les 5 s pendant les 2 premieres minutes
   d'affichage, puis toutes les 2 min. La phase rapide recommence chaque fois
   que la fenetre est rouverte ou remise au premier plan. */
const PERF_FAST_MS=5000, PERF_SLOW_MS=120000, PERF_FAST_WINDOW_MS=120000;
window._perfFastSince=Date.now();
function _perfDelay(){
  if(document.hidden)return 30000;
  return (Date.now()-window._perfFastSince<PERF_FAST_WINDOW_MS)?PERF_FAST_MS:PERF_SLOW_MS;
}
/* PC modeste (4 coeurs ou moins, ou 4 Go de memoire ou moins) : animations,
   flous et ombres coupes. C'est le navigateur qui dessine l'interface, et ces
   effets tournent en continu sur le processeur quand il n'y a pas de carte
   graphique dediee. */
(function(){
  try{
    const lite=(navigator.hardwareConcurrency||8)<=4||((navigator.deviceMemory||8)<=4);
    const apply=()=>{ if(document.body)document.body.classList.toggle('opti-lite',lite); };
    if(document.body)apply(); else document.addEventListener('DOMContentLoaded',apply);
  }catch(e){}
})();
function _schedPerf(){
  clearTimeout(window._perfT);
  window._perfT=setTimeout(()=>{ if(document.hidden){ _schedPerf(); } else { pollPerf(); } }, _perfDelay());
}
document.addEventListener('visibilitychange',()=>{
  document.body.classList.toggle('opti-idle',document.hidden);
  if(!document.hidden){ window._perfFastSince=Date.now(); clearTimeout(window._perfT); pollPerf(); }
});
/* Fermer la fenetre (croix) ne quitte PLUS OptiPC : il reste actif pres de
   l'horloge. Seul le menu « Quitter OptiPC » de l'icone l'arrete. On previent
   simplement le programme que la fenetre a ete fermee. */


function showConfirm(title, sub, onConfirm){
  const existing=document.getElementById('_modal');if(existing)existing.remove();
  const icon=title.match(/^[\u{1F300}-\u{1FFFF}]|^[😀-🙏]/u)?title.match(/^([\u{1F300}-\u{1FFFF}]|[😀-🙏]+)/u)[0]:'⚠️';
  const titleText=title.replace(/^[\u{1F300}-\u{1FFFF}\s]|^[😀-🙏\s]+/u,'').trim()||title;
  const el=document.createElement('div');
  el.id='_modal';el.className='modal-overlay';
  el.innerHTML='<div class="modal-box"><span class="modal-icon">'+icon+'</span><div class="modal-title">'+titleText+'</div><div class="modal-sub">'+sub+'</div><div class="modal-btns"><button class="modal-btn-cancel" id="_mcancelbtn">Annuler</button><button class="modal-btn-confirm" id="_mokbtn">Confirmer</button></div></div>';
  document.body.appendChild(el);
  document.getElementById('_mcancelbtn').onclick=()=>el.remove();
  document.getElementById('_mokbtn').onclick=()=>{el.remove();onConfirm();};
  el.addEventListener('click',e=>{if(e.target===el)el.remove();});
}

const DISKCAT_COLORS={'Documents':'#E8650C','Videos':'#f97316','Photos':'var(--green)','Music':'#38bdf8','Archives':'#fbbf24','Jeux':'#ef4444','Systeme':'#64748b','Autres':'#94a3b8','Systeme Windows':'#64748b','Programmes':'var(--acc-text)'};
const DISKCAT_LABELS={'Documents':'Documents','Videos':'Vidéos','Photos':'Images','Music':'Musique','Archives':'Archives','Jeux':'Jeux','Systeme':'Fichiers système','Autres':'Autres fichiers','Systeme Windows':'Système Windows','Programmes':'Programmes'};
async function loadDiskCategories(force){
  const el=document.getElementById('diskcat-list');
  if(!el)return;
  el.innerHTML='<div style="color:var(--muted);font-size:11.5px"><span class="spin" style="width:12px;height:12px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:8px"></span>Analyse de vos fichiers en cours...</div>';
  try{
    const d=await API.get('/api/diskcategories',180000);
    const cats=(d.categories||[]).filter(c=>c.size>0).sort((a,b)=>b.size-a.size);
    if(!cats.length){el.innerHTML='<div style="color:var(--muted);font-size:11.5px">Aucun fichier personnel trouvé dans Documents, Images, Vidéos, Musique, Bureau et Téléchargements.</div>';return;}
    const max=cats[0].size;
    el.innerHTML=cats.map(c=>{
      const col=DISKCAT_COLORS[c.name]||'#94a3b8';
      const lbl=DISKCAT_LABELS[c.name]||c.name;
      const pct=Math.max(2,Math.round((c.size/max)*100));
      return '<div style="margin-bottom:9px">'
        +'<div style="display:flex;justify-content:space-between;margin-bottom:4px">'
        +'<span style="font-size:12px;font-weight:600">'+lbl+'</span>'
        +'<span style="font-size:11.5px;color:'+col+';font-weight:700">'+c.sizeStr+'</span></div>'
        +'<div style="height:7px;background:rgba(var(--inv-rgb),.06);border-radius:4px;overflow:hidden">'
        +'<div style="height:100%;width:'+pct+'%;background:'+col+';border-radius:4px"></div></div></div>';
    }).join('')
      +'<div style="font-size:10px;color:var(--muted);margin-top:8px;line-height:1.6">Total analysé : <strong style="color:var(--dim)">'+(d.total||'0 B')+'</strong> &middot; '+(d.scanned||0)+' fichiers dans '+(d.folders||0)+' dossiers personnels'
      +(d.partial?'<br>⏱️ Analyse volontairement limitée à '+(d.elapsed||20)+' s : les dossiers les plus profonds n\u2019ont pas tous été parcourus.':'')
      +'</div>';
  }catch(e){
    el.innerHTML='<div style="font-size:11.5px;color:var(--red);line-height:1.6">Analyse interrompue.'
      +'<div style="color:var(--muted);font-size:10.5px;margin-top:4px">Vos dossiers personnels n\u2019ont pas pu être lus (dossier verrouillé, disque très sollicité ou fichiers OneDrive en ligne).</div>'
      +'<button class="btn-su btn-ghost" style="font-size:10px;margin-top:8px" onclick="loadDiskCategories(1)">Réessayer</button></div>';
  }
}
async function doWinsxsClean(btn){
  showConfirm('Supprimer les anciennes mises à jour ?',"Windows va supprimer définitivement les versions remplacées de ses composants. Cela libère souvent plusieurs centaines de Mo, mais vous ne pourrez plus désinstaller les mises à jour déjà installées. L'opération dure 5 à 20 minutes.",async()=>{
    await doRepair('winsxs_clean',btn);
  });
}
async function stopScan(){
  const c=document.getElementById('btn-scan-cancel');
  if(c)c.disabled=true;
  try{ await API.post('/api/scanner/stop',{},15000); }catch(e){}
}
let _notifPro=true;
let _settings={notifPro:true,notifClean:true,notifScan:true,notifStartup:true,notifThreat:true,sounds:true,openAtStartup:true};
const NOTIF_TOGGLES={notifPro:'tog-notif-pro',notifClean:'tog-notif-clean',notifScan:'tog-notif-scan',notifThreat:'tog-notif-threat',notifStartup:'tog-notif-startup',sounds:'tog-sounds',openAtStartup:'tog-open-startup'};
function notifOn(k){ return _settings[k]!==false; }
async function loadNotifSetting(){
  try{
    const s=await API.get('/api/settings',15000);
    Object.keys(NOTIF_TOGGLES).forEach(k=>{
      if(typeof s[k]!=='undefined')_settings[k]=(s[k]!==false);
      const t=document.getElementById(NOTIF_TOGGLES[k]);
      if(t)t.checked=(_settings[k]!==false);
    });
    _notifPro=notifOn('notifPro');
    _soundEnabled=notifOn('sounds');
  }catch(e){}
}
async function setNotif(key,checked){
  _settings[key]=checked;
  if(key==='notifPro')_notifPro=checked;
  if(key==='sounds')_soundEnabled=checked;
  const body={}; body[key]=checked;
  try{ await API.post('/api/settings',body,15000); }catch(e){}
  if(key==='openAtStartup'){
    toast(checked?'OptiPC s\'ouvrira au démarrage de Windows':'OptiPC démarrera discrètement près de l\'horloge','ok');
  } else if(key==='sounds'){
    toast(checked?'Sons activés':'Sons désactivés','ok');
  } else {
    toast(checked?'Notification activée':'Notification désactivée','ok');
  }
}
async function toggleNotifPro(checked){ return setNotif('notifPro',checked); }
function showCGU(){
  const old=document.getElementById('_cgu');if(old)old.remove();
  const A=_edAdresse();
  const P=_edPrix();
  const el=document.createElement('div');
  el.id='_cgu';el.className='modal-overlay';
  el.innerHTML='<div class="modal-box" style="max-width:660px;text-align:left;max-height:84vh;display:flex;flex-direction:column">'
    +'<div class="modal-title" style="text-align:left;margin-bottom:4px">Conditions générales d\'utilisation et de vente</div>'
    +'<div style="font-size:10.5px;color:var(--muted);margin-bottom:14px">OptiPC — '+EDITEUR.marque+' &middot; Version '+EDITEUR.versionCG+' du '+EDITEUR.dateCG+'</div>'
    +'<div style="overflow-y:auto;font-size:11.5px;line-height:1.75;color:var(--dim);padding-right:8px">'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">1. Identification de l\'éditeur</strong><br>'
    +'Le logiciel OptiPC est édité et commercialisé par <strong style="color:var(--text)">'+EDITEUR.societe+'</strong>, '+EDITEUR.forme+', exploitant la marque commerciale «&nbsp;'+EDITEUR.marque+'&nbsp;».<br>'
    +(EDITEUR.licence ? ('&bull; Licence commerciale : <strong style="color:var(--text)">n° '+EDITEUR.licence+'</strong>'+(EDITEUR.autorite?(', délivrée par la '+EDITEUR.autorite):'')+'<br>') : '')
    +_edLigne('Numéro d\'enregistrement fiscal (TRN)',EDITEUR.trn)
    +_edLigne('Gérant',EDITEUR.gerant)
    +_edLigne('Siège social',A)
    +'&bull; Contact : '+EDITEUR.tel+' — '+EDITEUR.mail+' — '+EDITEUR.site+'</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">2. Objet</strong><br>'
    +'Les présentes conditions régissent l\'utilisation du logiciel OptiPC ainsi que la vente des licences Premium par '+EDITEUR.societe+'. L\'installation ou l\'utilisation d\'OptiPC vaut acceptation pleine et entière des présentes conditions. Elles s\'appliquent aux consommateurs au sens du droit de la consommation.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">3. Description du logiciel</strong><br>'
    +'OptiPC est un utilitaire de maintenance, d\'optimisation et de contrôle de sécurité pour le système d\'exploitation Windows. Il analyse l\'ordinateur, supprime des fichiers devenus inutiles, libère de la mémoire, ajuste des réglages de performance, aide à désinstaller des logiciels et signale les programmes indésirables ou les comportements suspects.<br>'
    +'OptiPC <strong style="color:var(--text)">ne remplace pas un antivirus résident</strong> et ne garantit ni la suppression de toute menace, ni un gain de performance chiffré, ces résultats dépendant de la configuration et de l\'usage de chaque ordinateur.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">4. Configuration requise</strong><br>'
    +'Windows 10 ou Windows 11 (64 bits), un compte disposant des droits administrateur et environ 200 Mo d\'espace disque libre. Certaines fonctions nécessitent une connexion Internet.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">5. Version gratuite et version Premium</strong><br>'
    +'La version gratuite est utilisable sans limitation de durée. Elle donne accès à l\'analyse complète, au nettoyage des fichiers inutiles, à l\'optimisation des performances et du démarrage, à la désinstallation de logiciels et à la détection des menaces.<br>'
    +'La version Premium, obtenue par l\'achat d\'une clé de licence, débloque en outre la suppression et la mise en quarantaine des menaces détectées, le nettoyage avancé, le nettoyage du registre, le nettoyage automatique planifié et l\'assistance téléphonique prioritaire. Le détail des deux versions est présenté dans l\'onglet Paramètres du logiciel.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">6. Licence d\'utilisation</strong><br>'
    +'La licence concédée est personnelle, non exclusive, non cessible et limitée au nombre d\'ordinateurs indiqué lors de l\'achat ('+EDITEUR.dureePro+' sauf mention contraire sur la facture). Elle n\'emporte aucun transfert de propriété intellectuelle : le code, les marques et les éléments graphiques restent la propriété de '+EDITEUR.societe+'.<br>'
    +'Sont interdits la revente, la location, le partage public de la clé, la décompilation hors des cas prévus par la loi et toute tentative de contournement du mécanisme de licence, sous peine de résiliation immédiate et sans remboursement.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">7. Prix, commande et paiement</strong><br>'
    +(P?('Le prix de la licence Premium est de <strong style="color:var(--text)">'+P+'</strong> toutes taxes comprises. '):'Le prix en vigueur de la licence Premium est communiqué avant toute commande, par téléphone au '+EDITEUR.tel+' ou sur '+EDITEUR.site+'. ')
    +'Les prix sont exprimés en euros, toutes taxes comprises. Le paiement s\'effectue en une fois, par un prestataire de paiement sécurisé : '+EDITEUR.societe+' n\'a jamais accès au numéro complet de votre carte bancaire. Une facture est adressée par courrier électronique. La clé de licence est délivrée par courrier électronique dès l\'encaissement, en principe sous 24 heures ouvrées.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">8. Droit de rétractation</strong><br>'
    +'S\'agissant d\'un contrat à distance, le consommateur dispose d\'un délai de quatorze (14) jours calendaires à compter de la conclusion du contrat pour se rétracter, sans avoir à se justifier, en écrivant à '+EDITEUR.mail+' ou en appelant le '+EDITEUR.tel+'.<br>'
    +'Toutefois, la clé de licence constitue un contenu numérique fourni immédiatement : si vous demandez expressément son envoi avant la fin du délai et reconnaissez perdre de ce fait votre droit de rétractation, celui-ci ne peut plus être exercé une fois la clé transmise. À défaut d\'un tel accord exprès, le droit de rétractation reste entier et le remboursement intervient dans les quatorze jours suivant la demande, par le même moyen de paiement.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">9. Garantie légale</strong><br>'
    +'Le consommateur bénéficie de la garantie légale de conformité applicable aux contenus et services numériques. Si OptiPC ne fonctionne pas conformément à la présente description, contactez l\'assistance : la mise en conformité est recherchée en priorité ; à défaut, une réduction de prix ou la résolution du contrat peut être demandée.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">10. Sauvegarde préalable et responsabilité</strong><br>'
    +'Certaines opérations — nettoyage, désinstallation forcée, suppression forcée de fichiers, modification du registre — sont <strong style="color:var(--text)">irréversibles</strong>. Elles ne sont jamais déclenchées sans confirmation explicite de l\'utilisateur. Il appartient à ce dernier de sauvegarder ses données avant toute opération et de vérifier les éléments sélectionnés.<br>'
    +EDITEUR.societe+' ne saurait être tenue responsable des pertes de données ou dysfonctionnements consécutifs à une opération confirmée par l\'utilisateur, à une configuration matérielle ou logicielle particulière, ou à l\'action d\'un autre programme. La responsabilité de l\'éditeur ne peut en tout état de cause excéder le montant effectivement payé pour la licence, sans que cela limite sa responsabilité en cas de faute lourde, de dol ou d\'atteinte aux personnes.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">11. Faux positifs</strong><br>'
    +'La détection repose en partie sur des critères comportementaux : un fichier parfaitement légitime peut être signalé à tort. La mise en quarantaine, réversible, doit toujours être préférée à la suppression définitive. En cas de doute, appelez l\'assistance avant d\'agir.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">12. Données personnelles</strong><br>'
    +'Les analyses sont réalisées <strong style="color:var(--text)">localement</strong> sur votre ordinateur : la liste de vos fichiers n\'est pas transmise à l\'éditeur. Les réglages, l\'historique d\'activité et la clé de licence sont enregistrés sur votre poste.<br>'
    +'Les données collectées à l\'occasion d\'un achat (nom, adresse électronique, données de facturation, clé attribuée) sont traitées par '+EDITEUR.societe+', responsable du traitement, aux fins d\'exécution du contrat, de facturation et d\'assistance. Elles sont conservées pendant la durée de la relation commerciale, puis pendant la durée de conservation légale des documents comptables. Elles ne sont pas revendues.<br>'
    +'L\'éditeur étant établi hors de l\'Union européenne, un représentant au sens de l\'article 27 du RGPD est désigné pour recevoir vos demandes : '+_edRepUE()+'. Les transferts de données vers les Émirats arabes unis sont encadrés par les clauses contractuelles types de la Commission européenne.<br>'
    +'Conformément au RGPD, vous disposez d\'un droit d\'accès, de rectification, d\'effacement, de limitation, d\'opposition et de portabilité, en écrivant à '+EDITEUR.mail+'. Vous pouvez également saisir l\'autorité de protection des données de votre pays de résidence, en France la CNIL.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">13. Assistance</strong><br>'
    +'L\'assistance est joignable au '+EDITEUR.tel+' et à '+EDITEUR.mail+'. <strong style="color:var(--text)">Aucun collaborateur ne vous demandera jamais vos mots de passe, vos codes de carte bancaire ni un paiement par carte cadeau.</strong> En cas d\'appel suspect se réclamant d\'OptiPC ou de '+EDITEUR.marque+', raccrochez et rappelez le numéro ci-dessus.</p>'

    +'<p style="margin-bottom:11px"><strong style="color:var(--text)">14. Modification des conditions</strong><br>'
    +'L\'éditeur peut faire évoluer les présentes conditions, notamment pour tenir compte d\'évolutions légales ou fonctionnelles. La version applicable à une commande est celle en vigueur au jour de celle-ci.</p>'

    +'<p style="margin-bottom:4px"><strong style="color:var(--text)">15. Droit applicable et litiges</strong><br>'
    +'Les présentes conditions sont soumises au droit des Émirats arabes unis. Ce choix ne peut toutefois pas priver le consommateur résidant dans l\'Union européenne de la protection que lui assurent les dispositions impératives du droit de son pays de résidence habituelle : droit de rétractation, garantie légale de conformité et protection des données personnelles restent pleinement applicables.<br>'
    +'En cas de difficulté, contactez d\'abord l\'assistance au '+EDITEUR.tel+' : une solution amiable est recherchée en priorité. À défaut d\'accord, le consommateur conserve la faculté de saisir les juridictions compétentes de son lieu de résidence.</p>'
    +'</div>'
    +'<div class="modal-btns" style="margin-top:16px"><button class="modal-btn-cancel" onclick="document.getElementById(\'_cgu\').remove()">Fermer</button></div></div>';
  document.body.appendChild(el);
  el.addEventListener('click',e=>{if(e.target===el)el.remove();});
}
function _todayKey(){ const d=new Date(); return d.getFullYear()+'-'+(d.getMonth()+1)+'-'+d.getDate(); }
function maybeShowProReminder(){
  // Verrou supplementaire : si l'invitation a deja ete vue dans cette
  // session, on ne la represente jamais.
  if(_welcomeAlreadyShown)return;
  try{
    if(!isPro() && notifOn('notifPro')){
      let last=null;
      try{ last=localStorage.getItem('optipc_pro_reminder'); }catch(e){}
      if(last!==_todayKey()){
        try{ localStorage.setItem('optipc_pro_reminder',_todayKey()); }catch(e){}
        showProGate(_trialEnded
          ? "Votre essai Premium gratuit est terminé : OptiPC est repassé en version gratuite. Abonnez-vous pour continuer à supprimer les menaces et garder le nettoyage automatique (offre -50 %)."
          : "Vous utilisez OptiPC en version gratuite. La version Premium permet de supprimer les menaces détectées, débloque le nettoyage avancé et programme un nettoyage automatique de votre PC.");
      }
    }
  }catch(e){}
  
}
setTimeout(async()=>{ await loadNotifSetting(); },6000);
