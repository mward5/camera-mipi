#!/usr/bin/env python3
"""Capture line-based V4L2 metadata buffers. THROWAWAY - see WP0 in the plan.

Needed because neither tool on this box can do it: yavta 1.32.0 has no metadata
formats at all, and v4l2-ctl's --set-fmt-meta takes only a fourcc, with no way
to pass the width and height that a line-based metadata format requires.

Plain mmap streaming via ctypes. Standard library only.
"""
import ctypes, ctypes.util, fcntl, mmap, os, struct, sys, argparse

V4L2_BUF_TYPE_META_CAPTURE = 13
V4L2_MEMORY_MMAP = 1
def fourcc(s): return struct.unpack("<I", s.encode())[0]

class Timeval(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]

class Timecode(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("frames", ctypes.c_uint8), ("seconds", ctypes.c_uint8),
                ("minutes", ctypes.c_uint8), ("hours", ctypes.c_uint8),
                ("userbits", ctypes.c_uint8 * 4)]

class MetaFormat(ctypes.Structure):
    _fields_ = [("dataformat", ctypes.c_uint32), ("buffersize", ctypes.c_uint32),
                ("width", ctypes.c_uint32), ("height", ctypes.c_uint32),
                ("bytesperline", ctypes.c_uint32), ("reserved", ctypes.c_uint8 * 8)]

class FormatUnion(ctypes.Union):
    # v4l2_window inside the real union holds userspace pointers, so on 64-bit
    # the union is 8-aligned and struct v4l2_format is 208 bytes, not 204. The
    # alignment member below reproduces that; without it the ioctl number
    # encodes the 32-bit size and every G_FMT/S_FMT returns ENOTTY.
    _fields_ = [("meta", MetaFormat), ("raw_data", ctypes.c_uint8 * 200),
                ("_align", ctypes.c_uint64)]

class Format(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint32), ("fmt", FormatUnion)]

class RequestBuffers(ctypes.Structure):
    _fields_ = [("count", ctypes.c_uint32), ("type", ctypes.c_uint32),
                ("memory", ctypes.c_uint32), ("capabilities", ctypes.c_uint32),
                ("flags", ctypes.c_uint8), ("reserved", ctypes.c_uint8 * 3)]

class BufferUnion(ctypes.Union):
    _fields_ = [("offset", ctypes.c_uint32), ("userptr", ctypes.c_ulong),
                ("planes", ctypes.c_void_p), ("fd", ctypes.c_int32)]

class Buffer(ctypes.Structure):
    _fields_ = [("index", ctypes.c_uint32), ("type", ctypes.c_uint32),
                ("bytesused", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("field", ctypes.c_uint32), ("timestamp", Timeval),
                ("timecode", Timecode), ("sequence", ctypes.c_uint32),
                ("memory", ctypes.c_uint32), ("m", BufferUnion),
                ("length", ctypes.c_uint32), ("reserved2", ctypes.c_uint32),
                ("request_fd", ctypes.c_int32)]

def _ioc(d, t, nr, size): return (d << 30) | (size << 16) | (ord(t) << 8) | nr
IOC_READ, IOC_WRITE = 2, 1
VIDIOC_S_FMT     = _ioc(IOC_READ | IOC_WRITE, 'V', 5,  ctypes.sizeof(Format))
VIDIOC_G_FMT     = _ioc(IOC_READ | IOC_WRITE, 'V', 4,  ctypes.sizeof(Format))
VIDIOC_REQBUFS   = _ioc(IOC_READ | IOC_WRITE, 'V', 8,  ctypes.sizeof(RequestBuffers))
VIDIOC_QUERYBUF  = _ioc(IOC_READ | IOC_WRITE, 'V', 9,  ctypes.sizeof(Buffer))
VIDIOC_QBUF      = _ioc(IOC_READ | IOC_WRITE, 'V', 15, ctypes.sizeof(Buffer))
VIDIOC_DQBUF     = _ioc(IOC_READ | IOC_WRITE, 'V', 17, ctypes.sizeof(Buffer))
VIDIOC_STREAMON  = _ioc(IOC_WRITE, 'V', 18, 4)
VIDIOC_STREAMOFF = _ioc(IOC_WRITE, 'V', 19, 4)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("device")
    ap.add_argument("--width", type=int, default=3968)
    ap.add_argument("--height", type=int, default=684)
    ap.add_argument("--format", default="MET8")
    ap.add_argument("--count", type=int, default=20)
    ap.add_argument("--nbufs", type=int, default=4)
    ap.add_argument("--outdir")
    ap.add_argument("--set-format-only", action="store_true",
                    help="set the format and exit; the image node's pipeline start "
                         "validates this node's link too, so its format must already "
                         "be right or that start fails with EPIPE")
    a = ap.parse_args()
    if not a.set_format_only and not a.outdir:
        ap.error("--outdir is required unless --set-format-only")
    if a.outdir:
        os.makedirs(a.outdir, exist_ok=True)

    fd = os.open(a.device, os.O_RDWR)
    try:
        f = Format(); f.type = V4L2_BUF_TYPE_META_CAPTURE
        f.fmt.meta.dataformat = fourcc(a.format)
        f.fmt.meta.width = a.width
        f.fmt.meta.height = a.height
        f.fmt.meta.bytesperline = a.width
        f.fmt.meta.buffersize = a.width * a.height
        fcntl.ioctl(fd, VIDIOC_S_FMT, f)
        print(f"format set: {a.format} {f.fmt.meta.width}x{f.fmt.meta.height} "
              f"bpl={f.fmt.meta.bytesperline} buffersize={f.fmt.meta.buffersize}")
        if f.fmt.meta.buffersize < a.width * a.height:
            print(f"WARNING: driver shrank the buffer to {f.fmt.meta.buffersize}; "
                  f"expected at least {a.width * a.height}")
        if a.set_format_only:
            # Flipping the format is not enough. This driver keeps its vb2
            # queue as VIDEO_CAPTURE until REQBUFS arrives with a metadata
            # type (ipu6_isys_vidioc_reqbufs -> vb2_queue_change_type), and
            # link validation reads the format matching the *queue* type. So
            # without this the image node validates our link against a video
            # format and fails with EPIPE. A zero count is enough to switch it.
            req0 = RequestBuffers(count=0, type=V4L2_BUF_TYPE_META_CAPTURE,
                                  memory=V4L2_MEMORY_MMAP)
            fcntl.ioctl(fd, VIDIOC_REQBUFS, req0)
            print("queue type switched to META_CAPTURE")
            return

        req = RequestBuffers(count=a.nbufs, type=V4L2_BUF_TYPE_META_CAPTURE,
                             memory=V4L2_MEMORY_MMAP)
        fcntl.ioctl(fd, VIDIOC_REQBUFS, req)
        print(f"buffers allocated: {req.count}")

        maps = []
        for i in range(req.count):
            b = Buffer(index=i, type=V4L2_BUF_TYPE_META_CAPTURE, memory=V4L2_MEMORY_MMAP)
            fcntl.ioctl(fd, VIDIOC_QUERYBUF, b)
            maps.append(mmap.mmap(fd, b.length, mmap.MAP_SHARED,
                                  mmap.PROT_READ, offset=b.m.offset))
            fcntl.ioctl(fd, VIDIOC_QBUF, b)

        fcntl.ioctl(fd, VIDIOC_STREAMON, struct.pack("i", V4L2_BUF_TYPE_META_CAPTURE))
        print("streaming...")
        got = 0
        try:
            while got < a.count:
                b = Buffer(type=V4L2_BUF_TYPE_META_CAPTURE, memory=V4L2_MEMORY_MMAP)
                fcntl.ioctl(fd, VIDIOC_DQBUF, b)
                data = maps[b.index][:b.bytesused or b.length]
                path = os.path.join(a.outdir, f"paf-{b.sequence:04d}.bin")
                open(path, "wb").write(data)
                nz = len(set(data[:65536]))
                print(f"  seq={b.sequence:5d} bytesused={b.bytesused:9d} "
                      f"distinct_bytes_in_first_64k={nz}")
                fcntl.ioctl(fd, VIDIOC_QBUF, b)
                got += 1
        finally:
            fcntl.ioctl(fd, VIDIOC_STREAMOFF, struct.pack("i", V4L2_BUF_TYPE_META_CAPTURE))
        print(f"captured {got} buffers into {a.outdir}")
    finally:
        os.close(fd)

if __name__ == "__main__":
    main()
