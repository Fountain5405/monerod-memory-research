import csv, re, glob, os, sys, statistics as st, datetime as dt, bisect
d=sys.argv[1]; arms=sys.argv[2:4]
pts=[3105425,3105441,3113401,3123400]
def logpts(p):
    out={}
    for l in open(p,errors='replace'):
        m=re.match(r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*Synced (\d+)/',l)
        if not m: continue
        out.setdefault(int(m.group(2)),dt.datetime.strptime(m.group(1),'%Y-%m-%d %H:%M:%S.%f').timestamp())
    return out
def at(v,keys,h):
    i=bisect.bisect_left(keys,h)
    if keys[i]==h or i==0: return v[keys[i]]
    a,b=keys[i-1],keys[i]
    return v[a]+(v[b]-v[a])*(h-a)/(b-a)
res={a:[] for a in arms}
for a in arms:
    for f in sorted(glob.glob(f'{d}/r*_{a}.log')):
        v=logpts(f); k=sorted(v)
        t=[at(v,k,p) for p in pts]
        w=[t[i+1]-t[i] for i in range(3)]+[t[3]-t[0]]
        res[a].append(w); print(os.path.basename(f),[round(x,1) for x in w],'heights',len(k),'first',k[0])
for i,n in enumerate(['heavy 3105425-41','dense to 3113401','tail to 3123400','all from 3105425']):
    A=[x[i] for x in res[arms[0]]];B=[x[i] for x in res[arms[1]]]
    print(n,arms[0],round(st.median(A),1),(round(min(A),1),round(max(A),1)),arms[1],round(st.median(B),1),(round(min(B),1),round(max(B),1)),f'{100*(st.median(B)/st.median(A)-1):+.1f}%','overlap' if max(min(A),min(B))<=min(max(A),max(B)) else 'separate')
edges=[3105401,3105425,3105441,3108000,3110000,3113401,3116000,3118000,3120000,3122000,3123400]
for a in arms:
    print('arm',a)
    for f in sorted(glob.glob(f'{d}/r*_{a}.mem.csv')):
        mx={};pk=0;pkh=None;sw=0
        for r in csv.DictReader(open(f)):
            try: h=int(r['height']); an=int(r['RssAnon_kB'])/1024; sw=max(sw,int(r['VmSwap_kB']))
            except (ValueError,TypeError,KeyError): continue
            if h>3123400: continue
            if an>pk: pk,pkh=an,h
            for i in range(len(edges)-1):
                if edges[i]<=h<edges[i+1]: mx[i]=max(mx.get(i,0),an)
        print(os.path.basename(f)[:9],'peak',round(pk),'at',pkh,'swap',sw,[round(mx.get(i,0)) for i in range(len(edges)-1)])
print('edges',edges)
