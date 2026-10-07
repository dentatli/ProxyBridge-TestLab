"""Files-only single original-queue candidate; reuse signed observation binaries."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
POLICY=dict(method='full-wfp-afd-capture-v1',diagnostic_only=True,performance_comparable=False,cases=['original'],baseline_connections=4,
            raw_trace_limit_mib=64,baseline_coverage_before_load=True,recording_gap_declared=True,read_only_wfp_snapshot=True,
            private_record_observed=False,root_cause_proven=False)

def prepare(root,parent,new,verification):
    root=root.resolve();parent=parent.resolve();new=new.resolve()
    if new.parent!=root/'artifacts/diagnostics' or new.exists() or not new.name.startswith('tcp-redirect-context-preparation-'):
        raise ValueError('FULL_METADATA_FRESH_CANDIDATE_REQUIRED')
    build=read(parent/'kit/redirect-context-diagnostic.json');verified=read(verification)
    if (build['method']!='redirect-kernel-context-v4' or 'route_matrix_policy' not in build or 'external_receiver_policy' in build or
        verified['status']!='FULL_METADATA_STATIC_VERIFICATION_PASSED_RUNTIME_PENDING'):
        raise ValueError('FULL_METADATA_PARENT_OR_VERIFICATION_INVALID')
    for name,digest in verified['prepared_source_sha256'].items():
        if sha(root/name)!=digest:raise ValueError('FULL_METADATA_VERIFIED_SOURCE_CHANGED: '+name)
    for component in build['components']:
        if sha(parent/'kit'/component['name'])!=component['sha256']:raise ValueError('FULL_METADATA_PARENT_BINARY_CHANGED')
    if sha(parent/'source'/build['route_matrix_policy']['only_changed_source'])!=build['route_matrix_policy']['source_after_sha256']:
        raise ValueError('FULL_METADATA_PARENT_ROUTE_SOURCE_CHANGED')
    new.mkdir();(new/'verification').mkdir();shutil.copytree(parent/'source',new/'source');(new/'kit').mkdir()
    for name in ('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys','LICENSE'):shutil.copy2(parent/'kit'/name,new/'kit'/name)
    build['full_metadata_policy']=POLICY;save(new/'kit/redirect-context-diagnostic.json',build)
    (new/'kit/product.env').write_text((parent/'kit/product.env').read_text(encoding='utf-8-sig').replace(str(parent),str(new)),encoding='utf-8-sig')
    verified.update(status='PREPARED_STATIC_CHECKS_PASSED_RUNTIME_PENDING',method=POLICY['method'],kernel_sha256=sha(new/'kit/ProxyBridgeDrv.sys'),
                    core_sha256=sha(new/'kit/ProxyBridgeCore.dll'),parent_directory=str(parent),parent_build_receipt_sha256=sha(parent/'kit/redirect-context-diagnostic.json'),
                    binary_rebuilt=False,diagnostic_helper_sha256=sha(root/'bin/pb_read_wfp_etl.exe'))
    save(new/'verification/validation.json',verified);save(new/'verification/full-metadata-policy.json',POLICY)
    shutil.copy2(parent/'verification/route-policy.json',new/'verification/route-policy.json')
    return dict(status='FULL_METADATA_FILES_CREATED_PREPARE_REQUIRED',directory=str(new),product_binaries_rebuilt=False)
def main():
    p=argparse.ArgumentParser();p.add_argument('--parent',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--verification',type=Path,required=True)
    args=p.parse_args();print(json.dumps(prepare(Path(__file__).resolve().parents[1],args.parent,args.output,args.verification)))
if __name__=='__main__':main()
