"use strict";
var pba=null;
function initializeScript() {return [new host.apiVersionSupport(1,3),new host.functionAlias(pbaPre,"pbapre"),new host.functionAlias(pbaPost,"pbapost")];}
function ai(v) {return host.parseInt64(v.toString(16),16);}
function ah(v) {return ai(v).toString(16);}
function ae(a,b) {return Number(ai(a).compareTo(ai(b)))===0;}
function az(a) {return ae(a,0);}
function am(a,n) {return host.memory.readMemoryValues(ai(a),1,n,false)[0];}
function aq(a) {return ai(am(a,8));}
function an(a,n) {return Number(am(a,n));}
function ab(a,n) {var r=[];for(var x of host.memory.readMemoryValues(ai(a),n,1,false))r.push(Number(x));return r;}
function need(v,r) {if(!v)throw new Error(r);}
function log(v) {host.diagnostics.debugLog("PBA "+v+"\n");}
function command(s) {for(var l of host.namespace.Debugger.Utility.Control.ExecuteCommand(s))need(!/syntax error|extra character|couldn't resolve|unable to/i.test(l),"DEBUGGER_COMMAND");}
function pbaInitModel(pre,post) {pba={model:1,pre:null,post:null,final:false,error:0};command("r @$t0 = 0");command("r @$t1 = 0");log("CONFIG model=1 pre="+ah(pre)+" post="+ah(post)+" limit=100 version=1");return true;}
function pbaInitKernel() {
    var accept=host.getModuleSymbolAddress("tcpip","WfpAleAuthorizeAccept"),pre=accept.add(0xcaa),post=accept.add(0xcaf);
    var b=ab(pre,5),expected=[0x85,0xc0,0x75,0x0b,0x48,0x8b,0x45,0xd8],after=ab(post,8);
    need(b[0]===0xe8 && after.every(function(v,i){return v===expected[i];}),"ACCEPT_CODE_PIN");
    var rel=b[1]|(b[2]<<8)|(b[3]<<16)|(b[4]<<24);
    need(ae(pre.add(5).add(rel),host.getModuleSymbolAddress("fwpkclnt","FwpsNetBufferListRetrieveContext0")),"RETRIEVE_CALL_PIN");
    pba={model:0,pre:null,post:null,final:false,error:0};command("r @$t0 = 0");command("r @$t1 = 0");
    log("CONFIG model=0 pre="+ah(pre)+" post="+ah(post)+" limit=100 version=1");return true;
}
function state(nbl) {
    var raw=aq(ai(nbl).add(0xe0)),info=raw.bitwiseAnd(host.parseInt64("fffffffffffffffc",16)),root=ai(0),node,seen=[],value=ai(0),found=0,nodes=0;
    if(!az(info)) {
        need(an(info,4)===0x6e706657,"WFP_INFO_TAG");root=aq(info.add(0x10));node=root;
        while(!az(node)) {
            need(nodes<8 && seen.indexOf(ah(node))<0,"LIST_BOUND");seen.push(ah(node));nodes++;
            if(ae(aq(node.add(0x10)),5) && an(node.add(0xb8),1)===0) {found=1;value=aq(node.add(8));break;}
            var next=aq(node.add(0x80));if(ae(next,root.add(0x80)))break;
            need(!az(next),"LIST_LINK");node=next.subtract(0x80);
        }
    }
    return "info_raw="+ah(raw)+" info="+ah(info)+" root="+ah(root)+" key5="+found+" value="+ah(value)+" nodes="+nodes;
}
function pbaStop() {
    command("bd2");command("bd3");
    if(pba && !pba.final) {pba.final=true;log("FINAL pre="+(pba.pre?1:0)+" post="+(pba.post?1:0)+" error="+pba.error);}
    return true;
}
function fail(e) {if(pba)pba.error=1;log("INCOMPLETE reason="+(e && /^[A-Z_]+$/.test(e.message)?e.message:"MEMORY_OR_LAYOUT"));pbaStop();}
function pbaPre(nbl,frame,ep,sp) {
    try {
        need(pba && !pba.final && !pba.pre,"PRE_ORDER");
        need(an(ai(frame).subtract(0x7c),2)===0xda84 && an(ai(frame).subtract(0x7a),2)===0xd9a4 && !az(ep) && !az(nbl),"SELECTOR");
        var tid=ai(host.currentThread.Id);pba.pre={nbl:ai(nbl),frame:ai(frame),ep:ai(ep),sp:ai(sp),tid:tid};
        log("PRE tid="+ah(tid)+" scope="+ah(sp)+" frame="+ah(frame)+" ep="+ah(ep)+" nbl="+ah(nbl)+" "+state(nbl));
    } catch(e) {fail(e);}
}
function pbaPost(nbl,frame,ep,sp,status) {
    try {
        need(pba && !pba.final && pba.pre && !pba.post,"POST_ORDER");
        var p=pba.pre,tid=ai(host.currentThread.Id);
        need(ae(tid,p.tid)&&ae(nbl,p.nbl)&&ae(frame,p.frame)&&ae(ep,p.ep)&&ae(sp,p.sp),"PAIR_IDENTITY");
        var record=aq(ai(frame).subtract(0x28)),ctx=ai(0),size=ai(0);
        if(ae(status,0)&&!az(record)){ctx=aq(record.add(0x1e0));size=aq(record.add(0x1e8));}
        log("POST tid="+ah(tid)+" scope="+ah(sp)+" frame="+ah(frame)+" ep="+ah(ep)+" nbl="+ah(nbl)+" status="+ah(status)+" record="+ah(record)+" context="+ah(ctx)+" size="+ah(size));
        pba.post=true;pbaStop();
    } catch(e) {fail(e);}
}

var PBA_PRE_ACTION="r @$t0 = @$t0 + 1; .if (@$t0 >= 0x100) { bd2; bd3; .printf \"PBA INCOMPLETE reason=RAW_LIMIT\\n\"; } .else { .if ($vvalid(@rbp-0x7c,4) == 1) { .if ((wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)) { !pbapre @rcx, @rbp, @rdi, @rsp; } } .else { bd2; bd3; .printf \"PBA INCOMPLETE reason=SELECTOR_UNREADABLE\\n\"; } }; gc;";
var PBA_POST_ACTION="r @$t1 = @$t1 + 1; .if (@$t1 >= 0x100) { bd2; bd3; .printf \"PBA INCOMPLETE reason=RAW_LIMIT\\n\"; } .else { .if ($vvalid(@rbp-0x7c,4) == 1) { .if ((wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)) { !pbapost @rbx, @rbp, @rdi, @rsp, @eax; } } .else { bd2; bd3; .printf \"PBA INCOMPLETE reason=SELECTOR_UNREADABLE\\n\"; } }; gc;";
function pbaRegister(pre,post) {
    need(pba && !pba.final,"CONFIG_REQUIRED");
    if(pre===undefined){var a=host.getModuleSymbolAddress("tcpip","WfpAleAuthorizeAccept");pre=a.add(0xcaa);post=a.add(0xcaf);}
    command("bp2 0x"+ah(pre)+" "+JSON.stringify(PBA_PRE_ACTION));command("bd2");
    command("bp3 0x"+ah(post)+" "+JSON.stringify(PBA_POST_ACTION));command("bd3");return true;
}
