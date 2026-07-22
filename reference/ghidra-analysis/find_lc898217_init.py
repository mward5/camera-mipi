import pyghidra
pyghidra.start(install_dir="/home/mward/work/ghidra/ghidra_12.1.2_PUBLIC")
from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor

SYS_PATH = "/home/mward/work/xps-rear-win-20260713/s5k3j1sx04.sys"

with pyghidra.open_program(SYS_PATH, analyze=True) as flat_api:
    program = flat_api.getCurrentProgram()
    monitor = ConsoleTaskMonitor()
    listing = program.getListing()
    ref_mgr = program.getReferenceManager()
    func_mgr = program.getFunctionManager()
    decompiler = DecompInterface()
    decompiler.openProgram(program)

    targets = ["LC898217_Init", "LC898217_ResetPos"]
    seen = set()
    for needle in targets:
        print(f"########## {needle} ##########")
        for data in listing.getDefinedData(True):
            try:
                val = data.getValue()
            except Exception:
                continue
            if val is not None and needle in str(val):
                for ref in ref_mgr.getReferencesTo(data.getAddress()):
                    func = func_mgr.getFunctionContaining(ref.getFromAddress())
                    if func is None or func.getEntryPoint() in seen:
                        continue
                    seen.add(func.getEntryPoint())
                    print(f"-- {func.getName()} @ {func.getEntryPoint()} --")
                    result = decompiler.decompileFunction(func, 60, monitor)
                    if result and result.decompileCompleted():
                        print(result.getDecompiledFunction().getC())
