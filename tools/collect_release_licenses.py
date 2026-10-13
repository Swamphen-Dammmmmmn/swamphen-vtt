"""Copy copyright and license material into a built portable launcher directory."""
from pathlib import Path
import argparse
import shutil
import sys

ROOT=Path(__file__).resolve().parent.parent

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--boot",type=Path,required=True)
    args=parser.parse_args()
    destination=args.boot.resolve()
    if not destination.is_relative_to((ROOT/"build").resolve()):raise SystemExit("License output must be inside project build directory")
    for name in ("LICENSE","THIRD_PARTY_NOTICES"):shutil.copy2(ROOT/name,destination/name)
    target=destination/"licenses"
    target.mkdir(exist_ok=True)
    count=0
    for source_root in (ROOT/"addons",ROOT/"assets"/"environment",ROOT/"dev"/"vendor"):
        for source in source_root.rglob("*"):
            if source.is_file() and (source.name.upper().startswith(("LICENSE","COPYING","NOTICE","THIRD_PARTY_NOTICES")) or source.name=="OFL.txt"):
                output=target/"third-party"/source.relative_to(ROOT)
                output.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(source,output)
                count+=1
    for source in (ROOT/"artifacts"/"godot-licenses").glob("*.txt"):
        output=target/"godot"/source.name
        output.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,output)
    runtime=Path(sys.base_prefix)/"LICENSE.txt"
    if not runtime.exists():runtime=Path(sys.base_prefix)/"LICENSE"
    if not runtime.exists():raise SystemExit("Python runtime license missing")
    shutil.copy2(runtime,target/"Python-LICENSE.txt")
    for info in (Path(sys.prefix)/"Lib"/"site-packages").glob("*.dist-info"):
        if not info.name.lower().startswith(("cryptography-","cffi-","pycparser-","pyinstaller-","altgraph-")):continue
        for source in info.rglob("*"):
            if source.is_file() and ("licenses" in source.parts or source.name.upper().startswith(("LICENSE","COPYING","NOTICE"))):
                output=target/"runtime"/info.name/source.relative_to(info)
                output.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(source,output)
    print(f"Collected {count} third-party license files and runtime licenses.")

if __name__=="__main__":main()
