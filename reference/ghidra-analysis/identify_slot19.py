#!/usr/bin/env python3
"""Identify the actual chip at Vcm[19] by decompiling its function pointers
and dumping any string references found inside them."""
import pyghidra

pyghidra.start(install_dir="/home/mward/work/ghidra/ghidra_12.1.2_PUBLIC")

from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor

SYS_PATH = "/home/mward/work/xps-rear-win-20260713/s5k3j1sx04.sys"

SLOT19_PTRS = [0x140014c80, 0x140014800, 0x1400148d0, 0x140010900, 0x140014c20]


def strings_referenced_by(program, func):
    """Find any defined string data referenced (directly or one hop via a
    called sub-function) from instructions inside func's body."""
    listing = program.getListing()
    ref_mgr = program.getReferenceManager()
    found = []
    body = func.getBody()
    instr_iter = listing.getInstructions(body, True)
    for instr in instr_iter:
        for ref in instr.getReferencesFrom():
            to_addr = ref.getToAddress()
            data = listing.getDataAt(to_addr)
            if data is not None:
                try:
                    val = data.getValue()
                except Exception:
                    continue
                if val is not None and isinstance(str(val), str) and len(str(val)) >= 3:
                    found.append((str(instr.getAddress()), str(val)))
    return found


with pyghidra.open_program(SYS_PATH, analyze=True) as flat_api:
    program = flat_api.getCurrentProgram()
    monitor = ConsoleTaskMonitor()
    func_mgr = program.getFunctionManager()
    addr_factory = program.getAddressFactory()

    decompiler = DecompInterface()
    decompiler.openProgram(program)

    for ptr in SLOT19_PTRS:
        a = addr_factory.getDefaultAddressSpace().getAddress(ptr)
        func = func_mgr.getFunctionAt(a)
        print("=" * 100)
        if func is None:
            print(f"0x{ptr:x}: no function defined at this address")
            continue
        print(f"0x{ptr:x}: function {func.getName()}")
        strs = strings_referenced_by(program, func)
        if strs:
            print("  Direct string refs inside this function:")
            for iaddr, s in strs:
                print(f"    @ {iaddr}: {s!r}")
        else:
            print("  (no direct string refs found in this function's body)")

        result = decompiler.decompileFunction(func, 60, monitor)
        if result and result.decompileCompleted():
            print("  --- decompiled ---")
            print(result.getDecompiledFunction().getC())
        else:
            print(f"  decompile failed: {result.getErrorMessage() if result else 'no result'}")

    print("\nDone.")
