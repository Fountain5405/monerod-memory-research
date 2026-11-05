# Bytes of a file resident in the page cache, by mincore. Used by min_mem.sh with COLD=1 (E034); fincore is not installed.
import mmap,os,sys,ctypes
f=os.open(sys.argv[1],os.O_RDONLY); n=os.fstat(f).st_size; pg=mmap.PAGESIZE
libc=ctypes.CDLL("libc.so.6",use_errno=True); libc.mmap.restype=ctypes.c_void_p
libc.mmap.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_long]
a=libc.mmap(None,n,1,1,f,0); v=(ctypes.c_ubyte*((n+pg-1)//pg))()
libc.mincore.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p]
assert libc.mincore(a,n,v)==0
print(sum(x&1 for x in v)*pg)
