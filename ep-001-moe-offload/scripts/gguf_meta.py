#!/usr/bin/env python3
"""Print selected GGUF header keys (architecture, layers, experts, quantisation). Usage: gguf_meta.py <file.gguf>"""
import struct, sys
def rd(f, fmt): 
    s=struct.calcsize(fmt); return struct.unpack('<'+fmt, f.read(s))
def rstr(f):
    (n,)=rd(f,'Q'); return f.read(n).decode('utf-8','replace')
T={0:'B',1:'b',2:'H',3:'h',4:'I',5:'i',6:'f',7:'?',10:'Q',11:'q',12:'d'}
def rval(f,t):
    if t==8: return rstr(f)
    if t==9:
        (et,)=rd(f,'I'); (n,)=rd(f,'Q')
        vals=[rval(f,et) for _ in range(n)]
        return f"<array {n}>" if n>8 else vals
    return rd(f,T[t])[0]
with open(sys.argv[1],'rb') as f:
    assert f.read(4)==b'GGUF'; (v,)=rd(f,'I'); (nt,)=rd(f,'Q'); (nkv,)=rd(f,'Q')
    for _ in range(nkv):
        k=rstr(f); (t,)=rd(f,'I'); val=rval(f,t)
        if any(s in k for s in ('block_count','expert','general.name','file_type','context_length','quantize','general.size_label','general.architecture')) and not k.startswith('tokenizer'):
            print(k,'=',val)
