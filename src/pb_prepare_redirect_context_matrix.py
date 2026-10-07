"""Create a fresh, byte-identical diagnostic kit; no build, install or runtime queries."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
from pb_tcp_connections_report import read

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def plain(path):
    for item in (path,*path.parents):
        if item.exists() and item.stat().st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:raise ValueError('MATRIX_REPARSE_POINT')

def prepare(root,source,target):
    prefix=root/'artifacts/diagnostics'
    if source.parent!=prefix or target.parent!=prefix:raise ValueError('MATRIX_DIRECTORY_OUTSIDE_DIAGNOSTICS')
    if not all(re.fullmatch(r'tcp-redirect-context-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}',p.name) for p in (source,target)):
        raise ValueError('MATRIX_DIRECTORY_NAME_INVALID')
    if target.exists():raise ValueError('MATRIX_PREPARATION_REQUIRES_FRESH_DIRECTORY')
    plain(source);plain(target)
    kit=source/'kit';receipt=read(kit/'redirect-context-diagnostic.json')
    if receipt['method']!='redirect-context-followup-v2' or receipt['status']!='DIAGNOSTIC_BUILD_PREPARED' or receipt['diagnostic_only'] is not True or receipt['performance_comparable'] is not False:
        raise ValueError('MATRIX_REQUIRES_PREPARED_FOLLOWUP_CORE')
    if {c['name'] for c in receipt['components']}!={'ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys'}:raise ValueError('MATRIX_KIT_COMPONENT_SET_INVALID')
    for component in receipt['components']:
        if sha(kit/component['name'])!=component['sha256']:raise ValueError('MATRIX_SOURCE_KIT_CHANGED')
    for name,value in receipt['base_files_sha256'].items():
        if sha(root/name)!=value:raise ValueError('MATRIX_BASELINE_CHANGED')
    baseline=root/'artifacts/product-builds'/('ProxyBridge-'+receipt['source_commit'])
    for name,value in receipt['original_source_sha256'].items():
        if sha(baseline/name)!=value:raise ValueError('MATRIX_PINNED_SOURCE_CHANGED')
    env=(kit/'product.env').read_text(encoding='utf-8-sig')
    if str(kit/'ProxyBridge_CLI.exe') not in env or str(kit/'ProxyBridgeDrv.sys') not in env:raise ValueError('MATRIX_SOURCE_ENV_BINDING_INVALID')
    target.mkdir();newkit=target/'kit';newkit.mkdir()
    for name in ('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys','redirect-context-diagnostic.json'):
        shutil.copyfile(kit/name,newkit/name)
        assert sha(kit/name)==sha(newkit/name)
    (newkit/'product.env').write_text(env.replace(str(kit),str(newkit)),encoding='utf-8-sig')
    preparation=dict(schema_version=1,method='redirect-context-matrix-v2',fixture_close_guard='pinned-proactor-shutdown-reset-close-v1',source_directory=str(source),
        original_diagnostic_receipt_sha256=sha(kit/'redirect-context-diagnostic.json'),components_byte_identical=True,
        diagnostic_only=True,performance_comparable=False,build_performed=False,product_started=False,traffic_generated=False,driver_state_observed=False,
        cases=['connectex-32','connectex-1','connect-32','connect-1'])
    (target/'matrix-preparation.json').write_text(json.dumps(preparation,ensure_ascii=False,indent=2),encoding='utf-8')
    return preparation

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-directory',type=Path,required=True);parser.add_argument('--output-directory',type=Path,required=True)
    args=parser.parse_args();root=Path(__file__).resolve().parents[1]
    result=prepare(root,args.source_directory.absolute(),args.output_directory.absolute());print(json.dumps(result))

if __name__=='__main__':main()
