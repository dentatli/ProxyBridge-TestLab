"use strict";
var pbc=null;
function initializeScript(){return [new host.apiVersionSupport(1,3),new host.functionAlias(pbcCreate,"pbccreate"),new host.functionAlias(pbcSkip,"pbcskip"),new host.functionAlias(pbcAccept,"pbcaccept"),new host.functionAlias(pbcAbort,"pbcabort")];}
function ai(v){return host.parseInt64(v.toString(16),16);}
function ah(v){return ai(v).toString(16);}
function ae(a,b){return Number(ai(a).compareTo(ai(b)))===0;}
function az(a){return ae(a,0);}
function am(a,n){return host.memory.readMemoryValues(ai(a),1,n,false)[0];}
function aq(a){return ai(am(a,8));}
function an(a,n){return Number(am(a,n));}
function ab(a,n){var r=[];for(var x of host.memory.readMemoryValues(ai(a),n,1,false))r.push(Number(x));return r;}
function need(v,r){if(!v)throw new Error(r);}
function log(s){host.diagnostics.debugLog("PBC "+s+"\n");}
function command(s){for(var l of host.namespace.Debugger.Utility.Control.ExecuteCommand(s))need(!/syntax error|extra character|couldn't resolve|unable to/i.test(l),"DEBUGGER_COMMAND");}
function pin(a,bytes){need(ab(a,bytes.length).every(function(v,i){return v===bytes[i];}),"CODE_PIN");}
function reset(model,create,skip,accept){
    pbc={model:model,create:null,skips:[],accept:null,final:false,error:0};
    for(var n of [0,1,2,10])command("r @$t"+n+" = 0");
    log("CONFIG model="+model+" create="+ah(create)+" skip="+ah(skip)+" accept="+ah(accept)+" create_limit=20 skip_limit=200 accept_limit=200 skip_snapshots=8 version=2");return true;
}
function pbcInitModel(c,s,a){return reset(1,c,s,a);}
function pbcInitKernel(){
    var c=host.getModuleSymbolAddress("tcpip","AlepCreateRedirectRecord").add(0x396),s=host.getModuleSymbolAddress("tcpip","WfpTlShimInspectFastLoopbackSendDatagram"),a=host.getModuleSymbolAddress("tcpip","WfpAleAuthorizeAccept").add(0xcaf);
    pin(c,[0xeb,0x65,0x48,0x8b,0x5d,0x40]);
    pin(s.add(0x2d),[0x8b,0x41,0x30,0x0f,0xba,0xe0,0x15,0x0f,0x82,0x15,1,0,0]);
    pin(s.add(0x14f),[0x4c,0x8d,0x5c,0x24,0x50,0x8b,0xc7,0x49,0x8b,0x5b,0x20,0x49,0x8b,0x6b,0x28]);
    pin(a,[0x85,0xc0,0x75,0x0b,0x48,0x8b,0x45,0xd8]);
    var call=ab(a.subtract(5),5),rel=call[1]|(call[2]<<8)|(call[3]<<16)|(call[4]<<24);
    need(call[0]===0xe8&&ae(a.add(rel),host.getModuleSymbolAddress("fwpkclnt","FwpsNetBufferListRetrieveContext0")),"RETRIEVE_CALL_PIN");
    return reset(0,c,s.add(0x34),a);
}
function pbcStop(){
    for(var id of [2,3,4])command("bd"+id);
    if(pbc&&!pbc.final){pbc.final=true;log("FINAL create="+(pbc.create?1:0)+" skip="+pbc.skips.length.toString(16)+" skip_limit_reached="+(pbc.skips.length>=8?1:0)+" accept="+(pbc.accept?1:0)+" error="+pbc.error);}return true;
}
function pbcAbort(){if(pbc)pbc.error=1;log("INCOMPLETE reason=RAW_LIMIT");pbcStop();}
function fail(e){if(pbc)pbc.error=1;log("INCOMPLETE reason="+(e&&/^[A-Z_]+$/.test(e.message)?e.message:"MEMORY_OR_LAYOUT"));pbcStop();}
function record(r){r=ai(r);need(!az(r),"RECORD_NULL");return {context:aq(r.add(0x1e0)),size:aq(r.add(0x1e8)),refs:an(r.add(0x1f0),4)};}
function state(nbl){
    var raw=aq(ai(nbl).add(0xe0)),info=raw.bitwiseAnd(host.parseInt64("fffffffffffffffc",16)),root=ai(0),node,seen=[],value=ai(0),found=0,nodes=0;
    if(!az(info)){need(an(info,4)===0x6e706657,"WFP_INFO_TAG");root=aq(info.add(0x10));node=root;
        while(!az(node)){need(nodes<8&&seen.indexOf(ah(node))<0,"LIST_BOUND");seen.push(ah(node));nodes++;
            if(ae(aq(node.add(0x10)),5)&&an(node.add(0xb8),1)===0){found=1;value=aq(node.add(8));break;}
            var next=aq(node.add(0x80));if(ae(next,root.add(0x80)))break;need(!az(next),"LIST_LINK");node=next.subtract(0x80);
        }
    }return "info_raw="+ah(raw)+" info="+ah(info)+" root="+ah(root)+" key5="+found+" value="+ah(value)+" nodes="+nodes;
}
function syn(nbl){
    var nb=aq(ai(nbl).add(8)),mdl=aq(nb.add(8)),offset=an(nb.add(0x10),4),length=an(nb.add(0x18),4);
    need(!az(mdl)&&(an(mdl.add(0xa),2)&5)!==0,"SYN_MDL");
    var mapped=aq(mdl.add(0x18)),bytes=an(mdl.add(0x28),4);need(!az(mapped)&&length>=20&&bytes>=offset+20,"SYN_RANGE");
    var h=mapped.add(offset);
    if(!(an(h,2)===0xd9a4&&an(h.add(2),2)===0xda84)){
        var ihl=(an(h,1)&15)*4;
        need((an(h,1)&0xf0)===0x40&&an(h.add(9),1)===6&&ihl>=20&&ihl<=60&&(an(h.add(6),2)&0xff3f)===0&&an(h.add(12),4)===0x100007f&&an(h.add(16),4)===0x100007f&&length>=ihl+20&&bytes>=offset+ihl+20,"SYN_IPV4");h=h.add(ihl);
    }
    var head=(an(h.add(12),1)>>4)*4,flags=an(h.add(13),1);
    need(an(h,2)===0xd9a4&&an(h.add(2),2)===0xda84&&head>=20&&head<=60&&(flags&0x17)===2,"SYN_SELECTOR");
    return {header:h,seq:an(h.add(4),4),flags:flags};
}
function pbcCreate(source,ep,r){try{
    need(pbc&&!pbc.final&&!pbc.create,"CREATE_ORDER");source=ai(source);ep=ai(ep);r=ai(r);
    need(an(source,2)===2&&an(source.add(2),2)===0xd9a4&&!az(ep)&&ae(aq(ep.add(0x1c0)),r),"CREATE_IDENTITY");
    var v=record(r);need(!az(v.context)&&ae(v.size,32),"CREATE_CONTEXT");pbc.create={ep:ep,record:r,context:v.context};
    command("r @$t10 = 0x"+ah(ep));command("bd2");
    log("CREATE ep="+ah(ep)+" record="+ah(r)+" context="+ah(v.context)+" size="+ah(v.size)+" refs="+v.refs.toString(16));
}catch(e){fail(e);}}
function pbcSkip(ep,nbl,family,entryFlags,eflags){try{
    need(pbc&&!pbc.final&&pbc.create&&!pbc.accept,"SKIP_ORDER");if(pbc.skips.length>=8)return;
    var c=pbc.create;ep=ai(ep);nbl=ai(nbl);
    need(ae(ep,c.ep)&&ae(family,2)&&!az(nbl),"SKIP_IDENTITY");
    var flags=Number(ai(entryFlags).bitwiseAnd(0xffffffff));need((flags&0x200000)!==0&&Number(ai(eflags).bitwiseAnd(1))===1,"SKIP_BRANCH_CONDITION");
    need(ae(aq(ep.add(0x1c0)),c.record),"SOURCE_RECORD_CHANGED");var v=record(c.record);need(ae(v.context,c.context)&&ae(v.size,32),"SOURCE_CONTEXT_CHANGED");
    var h=syn(nbl),snapshot=state(nbl);need(!pbc.skips.length||pbc.skips[0].seq===h.seq,"SYN_SEQUENCE_CHANGED");
    pbc.skips.push({nbl:nbl,seq:h.seq});var hit=pbc.skips.length;
    log("SKIP hit="+hit.toString(16)+" ep="+ah(ep)+" record="+ah(c.record)+" context="+ah(v.context)+" size="+ah(v.size)+" flags30="+flags.toString(16)+" nbl="+ah(nbl)+" header="+ah(h.header)+" seq_raw="+h.seq.toString(16)+" tcp_flags="+h.flags.toString(16)+" "+snapshot);
    if(hit>=8)command("bd3");
}catch(e){fail(e);}}
function pbcAccept(nbl,frame,ep,status){try{
    need(pbc&&!pbc.final&&pbc.create&&!pbc.accept,"ACCEPT_ORDER");frame=ai(frame);nbl=ai(nbl);ep=ai(ep);
    need(an(frame.subtract(0x7c),2)===0xda84&&an(frame.subtract(0x7a),2)===0xd9a4&&!az(ep)&&!az(nbl),"ACCEPT_SELECTOR");
    var out=aq(frame.subtract(0x28)),matches=0,last=0;
    for(var i=0;i<pbc.skips.length;i++){if(ae(nbl,pbc.skips[i].nbl)){matches++;last=i+1;}}
    pbc.accept=true;
    log("ACCEPT ep="+ah(ep)+" nbl="+ah(nbl)+" status="+ah(status)+" output_raw="+ah(out)+" skip_count="+pbc.skips.length.toString(16)+" match_hit="+last.toString(16)+" match_count="+matches.toString(16)+" "+state(nbl));pbcStop();
}catch(e){fail(e);}}
var PBC_CREATE_ACTION='r @$t0 = @$t0 + 1; .if (@$t0 >= 0x20) { !pbcabort; } .else { .if ($vvalid(@r14,4) == 1) { .if ((wo(@r14) == 2) and (wo(@r14+2) == 0xd9a4)) { be3; be4; !pbccreate @r14, @rdi, @rax; } } }; gc;';
var PBC_SKIP_ACTION='r @$t1 = @$t1 + 1; .if (@$t1 >= 0x200) { !pbcabort; } .else { .if ((@$t10 != 0) and (@rbx == @$t10) and (@r14w == 2) and ((@eax & 0x200000) != 0) and ((@efl & 1) != 0)) { !pbcskip @rbx, @rbp, @r14w, @eax, @efl; } }; gc;';
var PBC_ACCEPT_ACTION='r @$t2 = @$t2 + 1; .if (@$t2 >= 0x200) { !pbcabort; } .else { .if ($vvalid(@rbp-0x7c,4) == 1) { .if ((wo(@rbp-0x7c) == 0xda84) and (wo(@rbp-0x7a) == 0xd9a4)) { !pbcaccept @rbx, @rbp, @rdi, @eax; } } }; gc;';
function pbcRegister(c,s,a){need(pbc&&!pbc.final,"CONFIG_REQUIRED");
    if(c===undefined){c=host.getModuleSymbolAddress("tcpip","AlepCreateRedirectRecord").add(0x396);s=host.getModuleSymbolAddress("tcpip","WfpTlShimInspectFastLoopbackSendDatagram").add(0x34);a=host.getModuleSymbolAddress("tcpip","WfpAleAuthorizeAccept").add(0xcaf);}
    for(var p of [[2,c,PBC_CREATE_ACTION],[3,s,PBC_SKIP_ACTION],[4,a,PBC_ACCEPT_ACTION]]){command("bp"+p[0]+" 0x"+ah(p[1])+" "+JSON.stringify(p[2]));command("bd"+p[0]);}return true;
}
