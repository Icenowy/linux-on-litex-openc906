#! /usr/bin/python3

from litex.tools.litex_client import RemoteClient
from socketserver import StreamRequestHandler, TCPServer

addr_length = 12
dm_base = 0x9ffff000
bus = None

rvdm = {
    'dmstatus': 0x11,
}

class DR:
    def __init__(self):
        self.dr_length = 1
        self.dr = 0
    def scan(self, rlen, tdi):
        tdi_bits = 0
        bits = 0
        for i in tdi:
            tdi_bits |= (i << bits)
            bits += 8
        in_dr = tdi_bits & ((1 << self.dr_length) - 1)
        out_dr = self.do_scan(in_dr)
        tdo_bits = (tdi_bits << self.dr_length) & ((1 << rlen) - 1)
        tdo_bits |= out_dr
        tdo = bytearray(len(tdi))
        for i in range(0, rlen, 8):
            tdo[i // 8] = tdo_bits & 0xff
            tdo_bits >>= 8
        return tdo
    def do_scan(self, in_dr):
        return self.dr

class BypassDR(DR):
    pass

class IdcodeDR(DR):
    def __init__(self):
        self.dr_length = 32
        self.dr = 0x10000b6f

class DtmcsDR(DR):
    def __init__(self):
        self.dmistat = 0
        dmstatus = bus.read(dm_base + rvdm['dmstatus'] * 4)
        assert dmstatus & 0xf != 0x0
        self.reset_dr = ((dmstatus & 0xf) - 1) | (addr_length << 4)

        self.dr_length = 32
    def do_scan(self, in_dr):
        self.dmistat &= 0x3
        ret = self.reset_dr | (self.dmistat << 10)
        if in_dr & 0x30000: # dmihardreset/dmireset
            self.dmistat = 0

        return ret

class DmiDR(DR):
    def __init__(self, dtmcs):
        self.dr_length = addr_length + 34 # 34 is fixed 32-bit data + 2-bit op
        self.dr = 0
        self.dtmcs = dtmcs
    def do_scan(self, new_dr):
        old_dr = self.dr
        if self.dtmcs.dmistat == 2:
            old_dr &= ~0x3
            old_dr |= 2
            return old_dr

        data = (new_dr >> 2) & 0xffffffff
        addr = (new_dr >> 34)
        assert int(new_dr & 0x3) != 3
        try:
            if int(new_dr & 0x3) == 0: # NOP
                pass
            if int(new_dr & 0x3) == 1: # R
                data = bus.read(dm_base + (addr << 2))
                new_dr &= ~(0xffffffff << 2)
                new_dr |= (data << 2)
            if int(new_dr & 0x3) == 2: # W
                bus.write(dm_base + (addr << 2), data)
            new_dr &= ~0x3
            self.dr = new_dr
        except:
            self.dtmcs.dmistat = 2
        return old_dr

class IR(DR):
    def __init__(self):
        self.dr_length = 5
        self.dr = 0x1
    def do_scan(self, in_dr):
        old_dr = self.dr
        in_dr &= 0x1f
        self.dr = in_dr
        return old_dr

class TAP:
    def __init__(self):
        self.reset()
    def reset(self):
        self.drs = [BypassDR()] * 0x20  # 0x00-0x1f
        self.drs[0x01] = IdcodeDR()
        dtmcs = DtmcsDR()
        self.drs[0x10] = dtmcs
        self.drs[0x11] = DmiDR(dtmcs)
        self.ir = IR()

class DPIHandler(StreamRequestHandler):
    def handle(self):
        cmd = self.rfile.readline()
        while cmd != b'':
            if cmd == b'reset\n':
                tap.reset()
            elif cmd[:2] == b'ib' or cmd[:2] == b'db':
                if cmd[:2] == b'ib':
                    dr = tap.ir
                else:
                    dr = tap.drs[tap.ir.dr]
                rlen = int(cmd[3:].strip())
                dlen = (rlen + 7) // 8
                tdi = self.rfile.read(dlen)
                tdo = dr.scan(rlen, tdi)
                self.wfile.write(tdo)
            else:
                raise ValueError('Invalid request')
            cmd = self.rfile.readline()

bus = RemoteClient()
bus.open()
tap = TAP()
TCPServer.allow_reuse_address = True
serv = TCPServer(('', 5555), DPIHandler)
serv.serve_forever()
