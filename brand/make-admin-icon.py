import math, sys
from PIL import Image, ImageDraw, ImageFont
S=1024*2  # draw at 2x then downsample
bg=(20,10,13,255); red=(230,39,50,255); gold=(255,196,46,255); white=(255,255,255,255)
img=Image.new('RGBA',(S,S),bg)
sym=Image.open(sys.argv[1]).convert('RGBA'); sym=sym.crop(sym.getbbox())
k=0.50*S/max(sym.size); sm=sym.resize((round(sym.width*k),round(sym.height*k)),Image.LANCZOS)
img.alpha_composite(sm,((S-sm.width)//2-int(S*.06), int(S*.12)))
d=ImageDraw.Draw(img)
# shield badge, bottom-right, overlapping the symbol
cx,cy,w=int(S*.70),int(S*.52),int(S*.30)
def shield(cx,cy,w):
    h=w*1.18; t=cy-h/2
    pts=[(cx,t),(cx+w/2,t+h*.14),(cx+w/2,t+h*.50)]
    # curved bottom
    for i in range(1,21):
        a=i/20; pts.append((cx+w/2*(1-a), t+h*.50+h*.50*math.sin(a*math.pi/2)))
    for i in range(1,21):
        a=i/20; pts.append((cx-w/2*a, t+h*.50+h*.50*math.cos(a*math.pi/2)))
    pts+=[(cx-w/2,t+h*.14)]
    return pts
d.polygon(shield(cx,cy,w+int(S*.05)),fill=bg)
d.polygon(shield(cx,cy,w),fill=gold)
# gear on shield
gx,gy=cx,cy+int(w*.02); R=w*.27; r=w*.10
for i in range(8):
    a=i*math.pi/4; tw=w*.075
    pts=[]
    for sx,sy in((-tw,R*.7),(tw,R*.7),(tw,R*1.32),(-tw,R*1.32)):
        pts.append((gx+sx*math.cos(a)-sy*math.sin(a), gy+sx*math.sin(a)+sy*math.cos(a)))
    d.polygon(pts,fill=bg)
d.ellipse([gx-R,gy-R,gx+R,gy+R],fill=bg)
d.ellipse([gx-r,gy-r,gx+r,gy+r],fill=gold)
# ADMIN pill
f=ImageFont.truetype('/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf',int(S*.13))
txt='ADMIN'; tb=d.textbbox((0,0),txt,font=f); tw_,th=tb[2]-tb[0],tb[3]-tb[1]
py=int(S*.85); ph=int(S*.17); pw=tw_+int(S*.12)
d.rounded_rectangle([(S-pw)//2,py-ph//2,(S+pw)//2,py+ph//2],radius=ph//2,fill=red)
d.text(((S-tw_)//2-tb[0],py-th//2-tb[1]),txt,font=f,fill=white)
img.resize((1024,1024),Image.LANCZOS).save(sys.argv[2])
