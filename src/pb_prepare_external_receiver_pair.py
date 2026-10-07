"""Files-only paired receiver candidate; byte-identical observation Core/kernel, no build or installation."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--parent',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--connection-file',type=Path,required=True);ap.add_argument('--verification',type=Path,required=True);args=ap.parse_args()
    root=Path(__file__).resolve().parents[1];parent=args.parent.resolve();new=args.output.resolve()
    if new.parent!=root/'artifacts/diagnostics' or new.exists() or not new.name.startswith('tcp-redirect-context-preparation-'):raise ValueError('EXTERNAL_FRESH_CANDIDATE_REQUIRED')
    build=read(parent/'kit/redirect-context-diagnostic.json');verified=read(args.verification)
    if (build['method']!='redirect-kernel-context-v4' or 'route_matrix_policy' not in build or
        verified['status']!='EXTERNAL_PAIR_STATIC_VERIFICATION_PASSED_RUNTIME_PENDING'):
        raise ValueError('EXTERNAL_PARENT_OR_VERIFICATION_INVALID')
    for name,digest in verified['prepared_source_sha256'].items():
        if sha(root/name)!=digest:raise ValueError('EXTERNAL_VERIFIED_SOURCE_CHANGED: '+name)
    for entry in build['components']:
        if sha(parent/'kit'/entry['name'])!=entry['sha256']:raise ValueError('EXTERNAL_PARENT_BINARY_CHANGED')
    connection=read(args.connection_file)
    policy=dict(method='local-linux-receiver-pair-v1',diagnostic_only=True,performance_comparable=False,cases=['local','linux'],route_case='original',
                host=connection['host'],allowed_source=connection['allowed_source'],port=54122,transfer_bytes=524288,
                receiver_sha256=sha(root/'src/pb_cts_push_receiver.py'),host_key_fingerprint=connection['host_key_fingerprint'],
                connection_file=str(args.connection_file.resolve()),connection_sha256=sha(args.connection_file))
    new.mkdir();(new/'verification').mkdir();shutil.copytree(parent/'source',new/'source');(new/'kit').mkdir()
    for name in ('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys','LICENSE'):
        shutil.copy2(parent/'kit'/name,new/'kit'/name)
    build['external_receiver_policy']=policy;save(new/'kit/redirect-context-diagnostic.json',build)
    env=(parent/'kit/product.env').read_text(encoding='utf-8-sig').replace(str(parent),str(new))
    (new/'kit/product.env').write_text(env,encoding='utf-8-sig')
    # Parent verification stays historical; this candidate is validated against new source checks.
    verified.update(status='PREPARED_STATIC_CHECKS_PASSED_RUNTIME_PENDING',method=policy['method'],
                    kernel_sha256=sha(new/'kit/ProxyBridgeDrv.sys'),core_sha256=sha(new/'kit/ProxyBridgeCore.dll'),
                    parent_directory=str(parent),parent_build_receipt_sha256=sha(parent/'kit/redirect-context-diagnostic.json'),binary_rebuilt=False)
    save(new/'verification/validation.json',verified);save(new/'verification/external-receiver-policy.json',policy)
    shutil.copy2(parent/'verification/route-policy.json',new/'verification/route-policy.json')
    print(json.dumps(dict(status='EXTERNAL_PAIR_FILES_CREATED_PREPARE_REQUIRED',directory=str(new),binary_rebuilt=False)))

if __name__=='__main__':main()
