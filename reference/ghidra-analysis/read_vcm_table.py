#!/usr/bin/env python3
"""Read the raw Vcm[] table entries at index 13 and 19, plus the DW9808 init
register/value table, from s5k3j1sx04.sys."""
import pyghidra

pyghidra.start(install_dir="/home/mward/work/ghidra/ghidra_12.1.2_PUBLIC")

SYS_PATH = "/home/mward/work/xps-rear-win-20260713/s5k3j1sx04.sys"

# Known DW9808_* function entry points, from the prior decompile pass.
KNOWN_FUNCS = {
    0x1400132e0: "DW9808_Init",
    0x140013660: "DW9808_SetPos",
    0x140013140: "DW9808_GetPos",
    0x140013460: "DW9808_ResetPos",
    0x140013550: "DW9808_SetConfig",
    0x1400137b8: "DW9808_WarmStart",
    0x140013384: "DW9808_NRC (or shared prep helper)",
    0x140013210: "DW9808_GetStatus",
    0x1400130a0: "DW9808_GetHPStatus",
}

ORDER_ARRAY_BASE = 0x14002a010   # DAT_14002a010 - order-check array, uint stride 0x50 bytes
TYPE_ARRAY_BASE = 0x14002a020    # DAT_14002a020 - Type field (2 bytes), stride 0x50
FUNCPTR_BASES = [0x14002a038, 0x14002a040, 0x14002a048, 0x14002a050, 0x14002a058]  # 8-byte ptrs, stride 0x50
STRIDE = 0x50

INIT_TABLE_BASE = 0x14002ba58  # DAT_14002ba58 - Init's register/value pair table


def addr(flat_api, program, off):
    return program.getAddressFactory().getDefaultAddressSpace().getAddress(off)


with pyghidra.open_program(SYS_PATH, analyze=True) as flat_api:
    program = flat_api.getCurrentProgram()
    mem = program.getMemory()

    print("=" * 100)
    print("Order-check array (DAT_14002a010), index -> stored value (should be self-index if valid)")
    print("=" * 100)
    for i in range(20):
        a = addr(flat_api, program, ORDER_ARRAY_BASE + i * STRIDE)
        val = mem.getInt(a)
        print(f"  index {i:2d}: order-value = {val}")

    print()
    print("=" * 100)
    print("Type field + function pointers for index 13 (BCD hypothesis) and 19 (raw hex)")
    print("=" * 100)
    for idx in (13, 19):
        type_addr = addr(flat_api, program, TYPE_ARRAY_BASE + idx * STRIDE)
        type_val = mem.getShort(type_addr) & 0xFFFF
        print(f"\n  --- index {idx} ---")
        print(f"  Type field (u16) @ {type_addr}: {type_val} (0x{type_val:x})")
        for fbase in FUNCPTR_BASES:
            faddr = addr(flat_api, program, fbase + idx * STRIDE)
            ptr = mem.getLong(faddr)
            name = KNOWN_FUNCS.get(ptr, "??? unrecognized ???")
            print(f"  funcptr @ {faddr} (table base 0x{fbase:x}): 0x{ptr:x}  -> {name}")

    print()
    print("=" * 100)
    print("Init register/value table (DAT_14002ba58) - first 8 entries, 8 bytes each")
    print("=" * 100)
    for i in range(8):
        a = addr(flat_api, program, INIT_TABLE_BASE + i * 8)
        raw = bytes([mem.getByte(a.add(j)) & 0xFF for j in range(8)])
        print(f"  entry {i}: bytes = {raw.hex(' ')}")

    print("\nDone.")
