#!/usr/bin/env python3
"""Decompile the DW9808_* VCM functions and locate the Vcm[] table in s5k3j1sx04.sys."""
import pyghidra

pyghidra.start(install_dir="/home/mward/work/ghidra/ghidra_12.1.2_PUBLIC")

from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor

SYS_PATH = "/home/mward/work/xps-rear-win-20260713/s5k3j1sx04.sys"

TARGET_STRINGS = [
    "CheckVcmTable Order Error",
    "DW9808_Init",
    "DW9808_SetPos",
    "DW9808_GetPos",
    "DW9808_ResetPos",
    "DW9808_SetConfig",
    "DW9808_WarmStart",
    "DW9808_NRC",
    "DW9808_GetStatus",
    "DW9808_GetHPStatus",
]


def find_string_addresses(program, needle):
    monitor = ConsoleTaskMonitor()
    listing = program.getListing()
    hits = []
    data_iter = listing.getDefinedData(True)
    for data in data_iter:
        try:
            val = data.getValue()
        except Exception:
            continue
        if val is not None and needle in str(val):
            hits.append(data.getAddress())
    return hits


def decompile_function(decompiler, func, monitor, timeout=60):
    result = decompiler.decompileFunction(func, timeout, monitor)
    if result and result.decompileCompleted():
        return result.getDecompiledFunction().getC()
    return f"<<decompile failed: {result.getErrorMessage() if result else 'no result'}>>"


with pyghidra.open_program(SYS_PATH, analyze=True) as flat_api:
    program = flat_api.getCurrentProgram()
    monitor = ConsoleTaskMonitor()
    ref_mgr = program.getReferenceManager()
    func_mgr = program.getFunctionManager()

    decompiler = DecompInterface()
    decompiler.openProgram(program)

    print("=" * 100)
    print(f"Program: {program.getName()}  base: {program.getImageBase()}")
    print("=" * 100)

    seen_funcs = set()

    for needle in TARGET_STRINGS:
        print(f"\n########## STRING: {needle!r} ##########")
        addrs = find_string_addresses(program, needle)
        if not addrs:
            print("  (no matching string data found)")
            continue
        for saddr in addrs:
            print(f"  string at {saddr}")
            refs = ref_mgr.getReferencesTo(saddr)
            for ref in refs:
                from_addr = ref.getFromAddress()
                func = func_mgr.getFunctionContaining(from_addr)
                if func is None:
                    print(f"    ref from {from_addr} -- not inside a defined function")
                    continue
                key = func.getEntryPoint()
                print(f"    ref from {from_addr} -- inside function {func.getName()} @ {key}")
                if key in seen_funcs:
                    continue
                seen_funcs.add(key)
                print(f"    --- decompiling {func.getName()} @ {key} ---")
                c_code = decompile_function(decompiler, func, monitor)
                print(c_code)
                print(f"    --- end {func.getName()} ---\n")

    print("\n\nDone.")
