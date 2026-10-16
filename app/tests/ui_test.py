"""Test de l'interface OptiPC 2.0 dans Chromium avec un moteur simule.
Capture les erreurs JavaScript et des captures d'ecran de chaque section."""
import json, os, sys, time, random
from pathlib import Path
from playwright.sync_api import sync_playwright

UI = Path(__file__).resolve().parent.parent / 'src' / 'ui'
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/optipc_shots')
OUT.mkdir(parents=True, exist_ok=True)
PRO = os.environ.get('PRO') == '1'

GB = 1024**3; MB = 1024**2
def items():
    L = [('temp_win','Windows','Fichiers temporaires',820*MB,True),('thumbnails','Windows','Cache miniatures',210*MB,True),('recent','Windows','Fichiers recents',3*MB,False),('recycle','Windows','Corbeille',410*MB,True),
         ('chrome','Navigateurs','Cache Chrome',640*MB,True),('edge','Navigateurs','Cache Edge',180*MB,True),('firefox','Navigateurs','Cache Firefox',0,True),
         ('wu_dl','Avance','Mises a jour Windows',1350*MB,True),('prefetch','Avance','Cache Prefetch',95*MB,False),('d3d','Avance','Cache DirectX',120*MB,True),('winold','Avance','Windows.old',18*GB,False),
         ('wer','Windows','Rapports d erreurs Windows',36*MB,True),('upgrade_logs','Windows','Journaux mise a niveau Windows',85*MB,True)]
    return [dict(id=a,cat=b,label=c,size=d,sizeStr='',checked=e,warn='x' if a=='winold' else '') for a,b,c,d,e in L]

def space():
    up = 'C:\\Users\\Marie'
    def it(name, d, size, level, kind, detail='', date='12/03/2023'):
        p = up + '\\' + d + '\\' + name
        return dict(id=p, path=p, name=name, dir=up+'\\'+d, size=size, sizeStr='', date=date, level=level, kind=kind, detail=detail)
    dups = [it('Vacances Agadir 2019 (copie).mp4','Videos\\A trier',3420*MB,'perso','Videos','Copie identique de : C:\\Users\\Marie\\Videos\\Vacances Agadir 2019.mp4'),
            it('Facture_EDF_mars.pdf','Downloads',2*MB,'perso','Documents','Copie identique de : C:\\Users\\Marie\\Documents\\Factures\\Facture_EDF_mars.pdf'),
            it('ChromeSetup.exe','Downloads',90*MB,'safe','Installateurs','Copie identique de : C:\\Users\\Marie\\Desktop\\ChromeSetup.exe')]
    dups += [it('IMG_%04d (1).jpg' % k,'Pictures\\Import',3*MB,'perso','Images','Copie identique de : C:\\Users\\Marie\\Pictures\\IMG_%04d.jpg' % k) for k in range(12)]
    big = [it('Windows10_installation.iso','Downloads',5400*MB,'safe','Archives'), it('Mariage Sophie.mov','Videos',3100*MB,'perso','Videos')]
    dl = [it('Pilote_HP.zip','Downloads',390*MB,'safe','Archives','Telecharge il y a 420 jours'), it('Scan0012.pdf','Downloads',12*MB,'perso','Documents','Telecharge il y a 80 jours')]
    empty = [dict(id=up+'\\Documents\\Nouveau dossier', path=up+'\\Documents\\Nouveau dossier', name='Nouveau dossier', dir=up+'\\Documents', size=0, sizeStr='', date='', level='safe', kind='Dossier', detail='')]
    old = [it('Ancien travail.zip','Documents',680*MB,'check','Archives','Pas modifie depuis 6 ans')]
    s = lambda a: sum(x['size'] for x in a)
    cats = [dict(name=n, size=v*GB, sizeStr='') for n, v in [('Videos',78),('Images',42),('Telechargements',31),('Musique',15),('Documents',10),('Archives',6),('Installateurs',2),('Autres',4)]]
    ef=[dict(id=up+'\\Documents\\note.txt',path=up+'\\Documents\\note.txt',name='note.txt',dir=up+'\\Documents',size=0,sizeStr='0 B',date='01/02/2024',level='safe',kind='Documents',detail='Fichier vide (0 octet)')]
    return dict(scanned=48211, elapsed=22, partial=False, total='188 GB', totalBytes=188*GB, cats=cats,
                groups=dict(dups=dict(items=dups,size=s(dups)), big=dict(items=big,size=s(big)), downloads=dict(items=dl,size=s(dl)), empty=dict(items=empty,size=0), emptyfiles=dict(items=ef,size=0), old=dict(items=old,size=s(old))), date='16/10/2026 15:42')

def apps():
    A = []
    for n,p,sz,kind,t in [('McAfee LiveSafe','McAfee, LLC',540,'oem','win32'),('Lenovo Vantage','LENOVO INC.',310,'oem','uwp'),('Google Chrome','Google LLC',420,'','win32'),('VLC media player','VideoLAN',160,'','win32'),('Zoom','Zoom Video Communications',280,'','win32'),
                          ('Microsoft Visual C++ 2015-2022 Redistributable (x64)','Microsoft Corporation',24,'','win32'),('Microsoft Edge WebView2 Runtime','Microsoft Corporation',590,'','win32'),('Calculatrice (Store)','Microsoft Corporation',30,'','uwp'),('Solitaire Collection (Store)','Microsoft Studios',120,'','uwp')]:
        A.append(dict(name=n,publisher=p,sizeBytes=sz*MB,size=f'{sz} MB',version='1.2.3',installDate='12/01/2024',type=t,kind=kind,id=n,removable=True))
    return A

DRIVE = dict(letter='C:', free='64.2 GB', total='476.3 GB', used='412 GB', pct=87, freeBytes=64*GB, totalBytes=476*GB)
def hist():
    import datetime
    today = datetime.date(2026,10,16)
    vals = [62,62,61,63,60,61,62,64,63,62,61,60,59,74,76,75,76,77,75,76,77,78,76,77,78,77,78,77,78,78]
    return [dict(d=(today-datetime.timedelta(days=29-i)).isoformat(), s=v) for i,v in enumerate(vals)]

API = {
 '/api/version': {'version':'2.0.0'},
 '/api/license/status': ({'isPro':True,'plan':'PRO','trial':False,'activated_at':'2026-10-01T10:00:00','days_active':15,'key_display':'ST-AB12-****-****'} if PRO else {'isPro':False,'plan':'FREE'}),
 '/api/license/heartbeat': {},
 '/api/consent': {'accepted':True,'version':'1.0'},
 '/api/perf': {'ram':{'pct':61,'cpuPct':18,'used':'9.8 GB','total':'16 GB'},'temp':{'available':True,'celsius':52,'label':'52°C'},'drives':[DRIVE],'net':'Connecte','self':{'cpu':1,'mem':'85 MB'}},
 '/api/perf2': {'disk':7,'gpu':{'present':True,'name':'NVIDIA GeForce RTX 3060','pct':34,'temp':61},'procs':142},
 '/api/analyze': {'total':'3.4 GB','totalBytes':int(3.4*GB),'score':78,'items':items(),'ramPct':61,'winoldSize':'18 GB'},
 '/api/security/status': {'defEnabled':True,'defSigAge':5,'fwOk':True,'uacOk':True,'ssOk':False,'otherAV':False,'otherAVName':''},
 '/api/health': {'disks':{'worst':'ok','available':True,'disks':[{'name':'Samsung SSD 980 500GB','number':'0','type':'SSD NVMe','size':'465.8 GB','letters':['C:'],'level':'ok','label':'Bonne','pct':96,'temp':38,'hours':6120,'wear':4,'reasons':[],'rows':[{'k':'Type','v':'SSD NVMe'},{'k':'Interface','v':'NVMe'},{'k':'Capacite','v':'465.8 GB'},{'k':'Temperature','v':'38 °C'},{'k':"Heures d'utilisation",'v':'6 120 h (0,7 ans)'},{'k':'Usure (SSD)','v':'4 %'},{'k':'Erreurs de lecture','v':'0'},{'k':'Etat Windows','v':'Healthy'}]},{'name':'WDC WD10EZEX 1TB','number':'1','type':'Disque dur','size':'931.5 GB','letters':['D:'],'level':'warn','label':'Attention','pct':60,'temp':61,'hours':31200,'wear':None,'reasons':['Temperature elevee (61 °C)'],'rows':[{'k':'Type','v':'Disque dur'},{'k':'Temperature','v':'61 °C'}]}]},
              'battery':{'present':True,'health':86,'level':'ok','charge':74,'plugged':True,'design':'52 000 mWh','full':'44 720 mWh','cycles':312},
              'boot':{'available':True,'lastSec':38,'firstSec':72,'lastBoot':'16/10/2026 08:12','history':[]}},
 '/api/diskinfo': {'drives':[DRIVE, dict(letter='D:', free='420 GB', total='931 GB', used='511 GB', pct=55, freeBytes=420*GB, totalBytes=931*GB)]},
 '/api/score/history': {'items':hist()},
 '/api/softupdates': {'available':True,'count':3,'items':[{'name':'Google Chrome','id':'Google.Chrome','current':'129.0.6668.90','available':'130.0.6723.59'},{'name':'VLC media player','id':'VideoLAN.VLC','current':'3.0.18','available':'3.0.21'},{'name':'Adobe Acrobat Reader','id':'Adobe.Acrobat.Reader.64-bit','current':'24.002','available':'24.003'}]},
 '/api/schedule': {'enabled':False,'frequency':'remove'},
 '/api/settings': {'notifPro':True,'notifClean':True,'notifScan':True,'notifStartup':True,'notifThreat':True,'sounds':False,'openAtStartup':True},
 '/api/cleanlog': {'lines':[]},
 '/api/apps': {'apps':apps()}, '/api/apps/refresh': {'apps':apps()},
 '/api/startup': {'items':[{'name':'Spotify','regPath':'HKCU','enabled':True,'command':'spotify.exe'},{'name':'OneDrive','regPath':'HKCU','enabled':True},{'name':'Opera GX Stable','regPath':'HKCU','enabled':True},{'name':'MicrosoftEdgeAutoLaunch_E61075848EC473','regPath':'HKCU','enabled':True},{'name':'SecurityHealth','regPath':'HKLM','enabled':True},{'name':'NordVPN','regPath':'HKLM','enabled':True},{'name':'Teams','regPath':'HKCU','enabled':False}]},
 '/api/startup/toggle': {'ok':True},
 '/api/browsers/hijack': {'count':2,'items':[{'browser':'Google Chrome','kind':'policy','level':'crit','title':'Réglage imposé : DefaultSearchProviderSearchURL','detail':'search.yoursearch.xyz'},{'browser':'Google Chrome','kind':'prefs','level':'crit','title':'Page de démarrage détournée (Default)','detail':'start.hijack.top'}]},
 '/api/browsers/repair': {'ok':True,'msg':'2 problème(s) corrigé(s)'},
 '/api/ram/optimize': {'ok':True},
 '/api/space/remove': {'ok':True,'done':5,'freed':1600*MB,'freedStr':'1.6 GB','limited':2,'msg':'ok'},
 '/api/services': {'services':[{'name':'DiagTrack','state':'Running'},{'name':'Fax','state':'Stopped'}]},
 '/api/powerplan': {'plans':[{'guid':'a','name':'Equilibre','icon':'balance','desc':'Bon compromis','active':True},{'guid':'b','name':'Performances','icon':'rocket','desc':'Maximum de puissance','active':False},{'guid':'c','name':'Economie','icon':'battery','desc':'Autonomie','active':False}]},
 '/api/virtmem': {'totalMB':4096,'usedMB':820},
 '/api/ram': {'pct':81,'totalMB':16384,'freeMB':2937},
 '/api/access/status': {'cam':True,'mic':True,'tel':True},
 '/api/space/scan': space(),
 '/api/network': {'ok':True,'myIp':'192.168.1.24','gateway':'192.168.1.1','adapter':'Wi-Fi','count':6,'newCount':1,'dns':['192.168.1.1'],'dnsLevel':'ok','date':'16/10/2026 15:50',
                  'wifi':{'connected':True,'ssid':'Livebox-4A2C','auth':'WPA2-Personnel','cipher':'CCMP','signal':82,'level':'ok','verdict':'Bonne protection (WPA2)'},
                  'devices':[{'ip':'192.168.1.1','mac':'3C-81-D8-11-22-33','name':'livebox.home','vendor':'Sagemcom (Livebox / box)','type':'box','label':'Box internet','isNew':False,'isGateway':True,'isSelf':False},
                             {'ip':'192.168.1.24','mac':'A4-C3-F0-00-11-22','name':'PC-MARIE','vendor':'Intel','type':'pc','label':'Ce PC','isNew':False,'isGateway':False,'isSelf':True},
                             {'ip':'192.168.1.31','mac':'7A-11-22-33-44-55','name':'','display':'iPhone de Karim','model':'iPhone','vendor':'Apple','type':'phone','label':'iPhone','isNew':True,'isGateway':False,'isSelf':False},
                             {'ip':'192.168.1.40','mac':'64-EB-8C-00-00-01','name':'EPSON3A1B2C','vendor':'Epson','type':'printer','label':'Imprimante ou appareil HP/Canon/Epson','isNew':False,'isGateway':False,'isSelf':False},
                             {'ip':'192.168.1.52','mac':'A8-5E-45-00-00-02','name':'','vendor':'LG','type':'tv','label':'TV, enceinte ou boitier multimedia','isNew':False,'isGateway':False,'isSelf':False},
                             {'ip':'192.168.1.60','mac':'00-11-22-33-44-55','name':'','vendor':'','type':'unknown','label':'Appareil inconnu','isNew':False,'isGateway':False,'isSelf':False}]},
 '/api/network/speed': {'ok':True,'mbps':87.4,'level':'ok','text':'Rapide : films et visio sans souci'},
 '/api/quarantine': {'items':[]},
 '/api/restorepoints': {'items':[{'id':12,'desc':'OptiPC - avant Tout reparer','date':'16/10/2026 15:10'},{'id':11,'desc':'Windows Update','date':'12/10/2026 03:02'}],'count':2,'enabled':True},
 '/api/sysinfo': {'os':'Microsoft Windows 11 Famille','build':'26100','cpu':'Intel(R) Core(TM) i5-12450H','cpuCores':8,'gpu':'NVIDIA GeForce RTX 3060','ram':'16 GB','diskModel':'Samsung SSD 980','diskSize':'465.8 GB','manufacturer':'LENOVO','model':'IdeaPad Gaming 3','bios':'J5CN45WW','uptime':'6h 12m','ip':'192.168.1.24','hostname':'PC-MARIE','user':'Marie'},
 '/api/boot': {'available':True,'lastSec':38,'firstSec':72,'lastBoot':'16/10/2026 08:12'},
 '/api/clean': {'cleaned':'2.4 GB','cleanedBytes':int(2.4*GB),'success':True},
 '/api/restorepoint': {'ok':True,'created':True,'msg':'Point de restauration cree'},
 '/api/security/fix': {'ok':True,'msg':'ok'},
 '/api/update/check': {'checked':True,'update_available':False,'current':'2.0.0'},
}

errors = []
def handle(route):
    url = route.request.url
    path = url.split('optipc.local',1)[1].split('?')[0]
    if path.startswith('/api/'):
        time.sleep(0.02)
        body = API.get(path, {})
        route.fulfill(status=200, content_type='application/json', body=json.dumps(body))
        return
    f = UI / (path.lstrip('/') or 'index.html')
    if not f.exists():
        route.fulfill(status=404, body='')
        return
    ct = {'.html':'text/html','.css':'text/css','.js':'application/javascript','.png':'image/png'}.get(f.suffix,'application/octet-stream')
    route.fulfill(status=200, content_type=ct, body=f.read_bytes())

with sync_playwright() as p:
    b = p.chromium.launch()
    for theme in ['light','dark']:
        pg = b.new_page(viewport={'width':1440,'height':900})
        pg.on('pageerror', lambda e: errors.append('PAGEERROR '+str(e)))
        pg.on('console', lambda m: errors.append('CONSOLE '+m.type+': '+m.text) if m.type in ('error',) else None)
        pg.route('https://optipc.local/**', handle)
        pg.add_init_script("window.chrome={webview:{postMessage:function(m){window.__msgs=(window.__msgs||[]);window.__msgs.push(m);}}};try{localStorage.setItem('optipc_theme','%s')}catch(e){}" % theme)
        pg.goto('https://optipc.local/index.html')
        pg.wait_for_timeout(2500)
        pg.evaluate("closeWelcome()")
        pg.screenshot(path=str(OUT/f'{theme}_01_home.png'))
        pg.evaluate("startHomeScan()"); pg.wait_for_timeout(700)
        pg.screenshot(path=str(OUT/f'{theme}_02_scan.png'))
        pg.wait_for_timeout(2500)
        pg.screenshot(path=str(OUT/f'{theme}_03_done.png'))
        pg.evaluate("document.getElementById('home-results').scrollIntoView()"); pg.wait_for_timeout(600)
        pg.screenshot(path=str(OUT/f'{theme}_04_results.png'))
        pg.evaluate("document.querySelector('#sec-home').scrollTop=0;startOptimize()"); pg.wait_for_timeout(500)
        pg.screenshot(path=str(OUT/f'{theme}_05_opt.png'))
        pg.wait_for_timeout(2500)
        pg.screenshot(path=str(OUT/f'{theme}_06_fixed.png'))
        for i,(sec,extra) in enumerate([('clean',None),('space','go'),('protect',None),('apps',None),('apps','start'),('health',None),('network',None),('tools','adv'),('params',None)]):
            pg.evaluate("closeWelcome()"); pg.evaluate(f"goSec('{sec}')")
            pg.wait_for_timeout(700)
            if extra=='go': pg.evaluate("renderSpace()"); pg.wait_for_timeout(500)
            if extra=='prot': pg.evaluate("switchPTab('prot')"); pg.wait_for_timeout(400)
            if extra=='start': pg.evaluate("appFilter('start')"); pg.wait_for_timeout(500)
            if extra=='adv': pg.evaluate("document.getElementById('adv-card').open=true"); pg.wait_for_timeout(600)
            if sec=='network': pg.evaluate("loadNetwork(true)"); pg.wait_for_timeout(900)
            pg.screenshot(path=str(OUT/f'{theme}_{i+10:02d}_{sec}{"_"+extra if extra else ""}.png'))
        pg.evaluate("showProGate('Test du message Premium')"); pg.wait_for_timeout(300)
        pg.screenshot(path=str(OUT/f'{theme}_21_progate.png'))
        msgs = pg.evaluate("window.__msgs||[]")
        print(theme, 'host messages:', msgs[:4])
        pg.close()
    b.close()

print('ERRORS:', len(errors))
for e in errors[:40]: print(e)
