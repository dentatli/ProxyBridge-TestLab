"use strict";
// Read-only target memory. Debugger commands manage owned watchpoints 2/3/4.
var pbNblConfig = null;
var pbNblState = null;
var pbRetry = null;
function initializeScript() { return [new host.apiVersionSupport(1, 3),
    new host.functionAlias(pbRetryCreateQuiet,"pbrcreate")]; }
function pbI(v) { return host.parseInt64(v.toString(16), 16); }
function pbH(v) { return pbI(v).toString(16); }
function pbEq(a, b) { return Number(pbI(a).compareTo(pbI(b))) === 0; }
function pbZero(a) { return pbEq(a, 0); }
function pbMem(a, size) { return host.memory.readMemoryValues(pbI(a), 1, size, false)[0]; }
function pbQ(a) { return pbI(pbMem(a, 8)); }
function pbSmall(a, size) { return Number(pbMem(a, size)); }
function pbBytes(a, count) {
    var result = [];
    for (var value of host.memory.readMemoryValues(pbI(a), count, 1, false)) result.push(Number(value));
    return result;
}
function pbNeed(ok, reason) { if (!ok) throw new Error(reason); }
function pbLog(s) { host.diagnostics.debugLog("PBR " + s + "\n"); }
function pbCommand(s, missingAllowed) {
    for (var line of host.namespace.Debugger.Utility.Control.ExecuteCommand(s)) {
        if (missingAllowed && /no breakpoint/i.test(line)) continue;
        if (/syntax error|extra character|no breakpoint|couldn't resolve|unable to/i.test(line)) throw new Error("DEBUGGER_COMMAND");
    }
}
function pbPin(address, expected) {
    var actual = pbBytes(address, expected.length);
    pbNeed(actual.every(function(v, i) { return v === expected[i]; }), "CODE_PIN");
}
function pbNblIntegerChecks() {
    var p=host.parseInt64("ffffb888c55e8b30",16);
    pbNeed(pbEq(0,0) && !pbEq(p,p.add(1)) && pbEq(p.add(0xe0).subtract(0xe0),p) &&
        pbEq(p.add(3).bitwiseAnd(host.parseInt64("fffffffffffffffc",16)),p), "INTEGER_CHECK");
}
function pbNblInitKernel() {
    pbNeed(pbNblState === null || !pbNblState.armed, "WATCH_STILL_ARMED");
    pbNblConfig=null;
    pbNblIntegerChecks();
    var get = host.getModuleSymbolAddress("NETIO", "WfpNblInfoGet");
    var retrieve = host.getModuleSymbolAddress("fwpkclnt", "FwpsNetBufferListRetrieveContext0");
    var accept = host.getModuleSymbolAddress("tcpip", "WfpAleAuthorizeAccept");
    pbPin(get, [0x40,0x53,0x48,0x83,0xec,0x30,0x48,0x8b,0x99,0xe0,0,0,0,0x48,0x83,0xe3,0xfc]);
    pbPin(retrieve, [0x40,0x53,0x55,0x56,0x48,0x83,0xec,0x50,0x41,0x0f,0xb6,0xe8,0x48,0x8b,0xf2,0x48,0x8b,0xd9]);
    pbPin(retrieve.add(0x27), [0x48,0x89,0x7c,0x24,0x78]);
    pbPin(retrieve.add(0x248), [0x48,0x8d,0x88,0x80,0,0,0]);
    pbPin(retrieve.add(0x25c), [0x44,0x38,0xb7,0xb8,0,0,0]);
    pbPin(retrieve.add(0x265), [0x48,0x39,0x77,0x10]);
    pbPin(retrieve.add(0x29e), [0x48,0x8b,0x47,0x08]);
    pbPin(retrieve.add(0x2dd), [0x48,0x8b,0x01]);
    pbPin(retrieve.add(0x2e8), [0x48,0x8d,0x78,0x80]);
    pbPin(retrieve.add(0x4f), [0x48,0x8b,0xf8]);
    pbPin(retrieve.add(0x651), [0x48,0x8b,0x40,0x10]);
    pbPin(accept.add(0xcaf), [0x85,0xc0,0x75,0x0b,0x48,0x8b,0x45,0xd8,0x48,0x89,0x87,0xc0,0x01,0,0]);
    var bad = pbQ(host.getModuleSymbolAddress("nt", "MmBadPointer"));
    pbNblConfig = {get: get.add(0xd), retrieveReturn: retrieve.add(0x4f), acceptReturn: accept.add(0xcaf), bad: bad, model: false};
    pbNblState = null;
    pbLog("CONFIG model=0 get=" + pbH(pbNblConfig.get) + " retrieve_return=" + pbH(pbNblConfig.retrieveReturn) + " accept_return=" + pbH(pbNblConfig.acceptReturn));
    pbLog("POLICY source_limit=80 packet_limit=40 total_limit=200 send_limit=8 version=6");
    return true;
}
// Explicit isolated CDB fixture entry. Runtime evidence must have CONFIG model=0.
function pbNblInitModel(get, retrieveReturn, acceptReturn, bad) {
    pbNeed(pbNblState === null || !pbNblState.armed, "WATCH_STILL_ARMED");
    pbNblIntegerChecks();
    pbNblConfig = {get:pbI(get), retrieveReturn:pbI(retrieveReturn), acceptReturn:pbI(acceptReturn), bad:pbI(bad), model:true};
    pbNblState = null;
    pbLog("CONFIG model=1 get=" + pbH(get) + " retrieve_return=" + pbH(retrieveReturn) + " accept_return=" + pbH(acceptReturn));
    pbLog("POLICY source_limit=80 packet_limit=40 total_limit=200 send_limit=8 version=6");
    return true;
}
function pbNblPacket(nbl) {
    var nb = pbQ(nbl.add(8)), mdl = pbQ(nb.add(8));
    var offset = pbSmall(nb.add(0x10),4), length = pbSmall(nb.add(0x18),4);
    var count = pbSmall(mdl.add(0x28),4), mapped = pbQ(mdl.add(0x18));
    pbNeed((pbSmall(mdl.add(0xa),2) & 5) !== 0 && !pbZero(mapped) && length >= 20 && count >= offset+20, "PACKET_MAPPING");
    var header = mapped.add(offset), first = pbBytes(header,20), ihl = (first[0]&15)*4;
    if (!(first[0]===0xa4 && first[1]===0xd9 && first[2]===0x84 && first[3]===0xda)) {
        pbNeed((first[0]&0xf0)===0x40 && first[9]===6 && ihl>=20 && ihl<=60 &&
            (first[6]&0x3f)===0 && first[7]===0 && length>=ihl+20 && count>=offset+ihl+20 &&
            first.slice(12,20).join(",")==="127,0,0,1,127,0,0,1", "PACKET_IPV4");
        header=header.add(ihl);
    }
    var bytes=pbBytes(header,20);
    pbNeed(bytes[0]===0xa4 && bytes[1]===0xd9 && bytes[2]===0x84 && bytes[3]===0xda, "PACKET_PORTS");
    pbNeed((bytes[12]>>4)>=5, "TCP_HEADER_LENGTH");
    return {nb:nb,mdl:mdl,header:header,sequence:bytes.slice(4,8).join(":"),flags:bytes[13],syn:(bytes[13]&0x17)===2};
}
function pbNblCheckIdentity() {
    var s=pbNblState, p=s.packet;
    pbNeed(pbEq(pbQ(s.nbl.add(8)),p.nb) && pbEq(pbQ(p.nb.add(8)),p.mdl), "PACKET_STORAGE_CHANGED");
    var b=pbBytes(p.header,20);
    pbNeed(b[0]===0xa4 && b[1]===0xd9 && b[2]===0x84 && b[3]===0xda &&
        (b[12]>>4)>=5 && b[13]===p.flags && b.slice(4,8).join(":")===p.sequence, "PACKET_IDENTITY_CHANGED");
}
function pbNblSnapshot(stage) {
    var s=pbNblState, raw=pbQ(s.nbl.add(0xe0));
    var info=raw.bitwiseAnd(host.parseInt64("fffffffffffffffc",16));
    var root=pbI(0), node, visited=[], value=pbI(0), found=false, nodes=0;
    if (!pbZero(info) && !pbEq(info,pbNblConfig.bad)) {
        pbNeed(pbSmall(info,4)===0x6e706657, "WFP_INFO_TAG");
        root=pbQ(info.add(0x10));node=root;
        if (!pbZero(root)) {
            while (true) {
                pbNeed(nodes<8, "LIST_LIMIT");
                pbNeed(visited.indexOf(pbH(node))<0, "LIST_CYCLE");visited.push(pbH(node));nodes++;
                var key=pbQ(node.add(0x10)), inactive=pbSmall(node.add(0xb8),1);
                if (pbEq(key,5) && inactive===0) {value=pbQ(node.add(8));found=true;break;}
                var next=pbQ(node.add(0x80));
                if (pbEq(next,root.add(0x80))) break;
                pbNeed(!pbZero(next), "LIST_LINK");node=next.subtract(0x80);
            }
        }
    }
    pbLog("STATE stage="+stage+" epoch="+pbRetry.sends.toString(16)+" nbl="+pbH(s.nbl)+" info_raw="+pbH(raw)+" info="+pbH(info)+" root="+pbH(root)+
        " key5="+(found?"present":"absent")+" value="+pbH(value)+" record_match="+(found&&pbEq(value,s.record)?1:0)+" nodes="+nodes);
}
// Raw NB+20/+28 fields are logged separately from physical packet identity.
function pbRetryBuffer(stage) {
    var s=pbNblState,p=s.packet,nb=pbQ(s.nbl.add(8));
    var current=pbQ(nb.add(8)),offset=pbSmall(nb.add(0x10),4),length=pbSmall(nb.add(0x18),4);
    var chain=pbQ(nb.add(0x20)),dataOffset=pbSmall(nb.add(0x28),4),readable=0,match=0;
    try {
        var b=pbBytes(p.header,20);readable=1;
        match=b[0]===0xa4 && b[1]===0xd9 && b[2]===0x84 && b[3]===0xda &&
            (b[12]>>4)>=5 && b[13]===p.flags && b.slice(4,8).join(":")===p.sequence?1:0;
    } catch (_) {}
    pbLog("BUFFER stage="+stage+" epoch="+s.epoch.toString(16)+" nb="+pbH(nb)+
        " current_mdl="+pbH(current)+" current_offset="+offset.toString(16)+" length="+length.toString(16)+
        " nb20_raw="+pbH(chain)+" nb28_raw="+dataOffset.toString(16)+" saved_header="+pbH(p.header)+
        " header_readable="+readable+" header_match="+match);
}
// Epoch is one SEND observation, not an asserted network retransmission number.
function pbRetryInit() {
    pbRetry={creates:0,sourceReads:0,sends:0,reads:0,pairs:0,samples:0,nonSynSamples:0,sourceArmed:false,error:0,final:false,sequence:null};
}
function pbRetryInitKernel() {
    pbNeed(!pbRetry || !pbRetry.sourceArmed,"WATCH_STILL_ARMED");
    pbNblInitKernel();
    var send=host.getModuleSymbolAddress("tcpip","WfpTlShimInspectFastLoopbackSendDatagram");
    pbPin(send.add(0x2d),[0x8b,0x41,0x30,0x0f,0xba,0xe0,0x15]);
    pbNblConfig.send=send.add(0x30);pbRetryInit();return true;
}
function pbRetryInitModel(get,ret,accept,bad,send) {
    pbNblInitModel(get,ret,accept,bad);pbNblConfig.send=pbI(send);pbRetryInit();return true;
}
function pbRetryEnd(reason) {
    var s=pbNblState;
    if (!s || s.ended) return;
    if (s.armed) {pbCommand("bc4",true);pbCommand("r @$t9 = 0");s.armed=false;}
    s.ended=true;
    pbLog("END epoch="+s.epoch.toString(16)+" reason="+reason+" reads="+s.reads.toString(16));
}
function pbRetryStop() {
    pbCommand("bd2",true);pbRetryEnd("STOPPED");
    if (pbRetry && pbRetry.sourceArmed) {
        pbCommand("bc3",true);pbCommand("r @$t8 = 0");pbRetry.sourceArmed=false;
    }
    if (pbRetry && !pbRetry.final) {
        pbRetry.final=true;
        pbLog("FINAL creates="+pbRetry.creates.toString(16)+" source_reads="+pbRetry.sourceReads.toString(16)+
            " sends="+pbRetry.sends.toString(16)+" reads="+pbRetry.reads.toString(16)+" pairs="+pbRetry.pairs.toString(16)+" error="+pbRetry.error);
    }
    return true;
}
function pbRetryFail(error) {
    var reason=error && /^[A-Z_]+$/.test(error.message)?error.message:"MEMORY_OR_LAYOUT";
    if (pbRetry) pbRetry.error=1;
    try {pbRetryStop();} catch (_) {pbLog("INCOMPLETE reason=CLEANUP");}
    pbLog("INCOMPLETE reason="+reason);return false;
}
function pbRetryCreate(selector,source,record) {
    try {
        pbNeed(pbRetry!==null && pbNblConfig!==null,"CONFIG_REQUIRED");
        pbRetry.creates++;
        pbNeed(pbRetry.creates<16,"CREATE_LIMIT");
        if (pbSmall(pbI(selector),2)!==2 || pbSmall(pbI(selector).add(2),2)!==0xd9a4) return false;
        pbNeed(!pbRetry.sourceArmed && !pbZero(source) && !pbZero(record),"CREATE_IDENTITY");
        pbNeed(pbEq(pbQ(pbI(source).add(0x1c0)),record),"SOURCE_RECORD_CHANGED");
        var context=pbQ(pbI(record).add(0x1e0)),size=pbQ(pbI(record).add(0x1e8));
        pbNeed(!pbZero(context) && pbEq(size,32),"CREATE_RECORD");
        pbRetry.source=pbI(source);pbRetry.record=pbI(record);
        pbCommand("bd2");
        pbLog("TRACK ep="+pbH(source)+" record="+pbH(record)+" context="+pbH(context)+" size="+pbH(size));
        pbRetry.sourceArmed=true;
        pbCommand("ba3 r4 /w \"@$scriptContents.pbRetrySourceQuiet(@rip,@rcx,@rbx,@rbp,@eax,@r14w)\" 0x"+pbH(pbI(source).add(0x30)));
        pbCommand("r @$t8 = 1");return true;
    } catch(e) {return pbRetryFail(e);}
}
function pbRetrySource(ip,rcx,rbx,nbl,flags,family) {
    try {
        var r=pbRetry;
        if (!r || !r.sourceArmed) return false;
        r.sourceReads++;
        pbNeed(r.sourceReads<128,"SOURCE_LIMIT");
        if (!pbEq(ip,pbNblConfig.send) || !pbEq(rcx,r.source) || !pbEq(rbx,r.source)) return false;
        pbNeed(pbEq(family,2) && pbEq(pbQ(r.source.add(0x1c0)),r.record),"SOURCE_RECORD_CHANGED");
        var packet=pbNblPacket(pbI(nbl));
        if (!packet.syn) {
            if (r.nonSynSamples<4) {r.nonSynSamples++;pbLog("SKIP reason=NON_SYN nbl="+pbH(nbl)+" flags="+pbH(packet.flags));}
            return false;
        }
        if (r.sequence===null) r.sequence=packet.sequence;
        pbNeed(r.sequence===packet.sequence,"SYN_SEQUENCE_CHANGED");
        pbNeed(r.sends<8 && r.reads<512,"TOTAL_LIMIT");
        pbRetryEnd("REPLACED");r.sends++;
        pbNblState={nbl:pbI(nbl),record:r.record,source:r.source,packet:packet,reads:0,epoch:r.sends,armed:false,ended:false};
        pbLog("SEND epoch="+r.sends.toString(16)+" nbl="+pbH(nbl)+" flags="+pbH(flags)+
            " nb="+pbH(packet.nb)+" mdl="+pbH(packet.mdl)+" header="+pbH(packet.header)+" seq_raw="+pbH(pbSmall(packet.header.add(4),4)));
        pbNblSnapshot("send");pbRetryBuffer("send");
        pbNblState.armed=true;
        pbCommand("ba4 r8 /w \"@$scriptContents.pbRetryReadQuiet(@rcx,@rbx,@rip,@rsp,@rsi,@rbp)\" 0x"+pbH(pbI(nbl).add(0xe0)));
        pbCommand("r @$t9 = 1");return true;
    } catch(e) {return pbRetryFail(e);}
}
function pbRetryRead(nbl,raw,ip,sp,key,consume) {
    try {
        var r=pbRetry,s=pbNblState;
        if (!r || !s || !s.armed) return false;
        r.reads++;s.reads++;
        var reason=null;
        if (!pbEq(ip,pbNblConfig.get)) reason="IP";
        else if (!pbEq(nbl,s.nbl)) reason="OBJECT";
        else if (!pbEq(pbQ(pbI(sp).add(0x38)),pbNblConfig.retrieveReturn)) reason="RETRIEVE_CALLER";
        else if (!pbEq(pbQ(pbI(sp).add(0xa8)),pbNblConfig.acceptReturn)) reason="ACCEPT_CALLER";
        else if (!pbEq(key,5)) reason="KEY";
        else if (!pbEq(consume,1)) reason="CONSUME";
        if (reason===null) {
            var frame=pbQ(pbI(sp).add(0x98)),ep=pbQ(pbI(sp).add(0xb8));
            var local=pbSmall(frame.subtract(0x7c),2),peer=pbSmall(frame.subtract(0x7a),2);
            pbLog("SELECTOR epoch="+s.epoch.toString(16)+" frame="+pbH(frame)+" ep="+pbH(ep)+" local_raw="+pbH(local)+" peer_raw="+pbH(peer));
            if (local!==0xda84 || peer!==0xd9a4 || pbZero(ep)) {pbRetryEnd("OTHER_TUPLE");return false;}
            pbNeed(pbEq(pbQ(s.nbl.add(0xe0)),raw),"WFP_INFO_CHANGED_DURING_READ");
            pbLog("SELECTED epoch="+s.epoch.toString(16)+" ep="+pbH(ep)+" nbl="+pbH(nbl)+" raw="+s.reads.toString(16));
            pbNblSnapshot("selected");pbRetryBuffer("selected");
            var nb=pbQ(s.nbl.add(8)),mdl=pbQ(nb.add(8));
            if (!pbEq(nb,s.packet.nb) || !pbEq(mdl,s.packet.mdl)) {
                pbLog("STORAGE epoch="+s.epoch.toString(16)+" old_nb="+pbH(s.packet.nb)+" nb="+pbH(nb)+" old_mdl="+pbH(s.packet.mdl)+" mdl="+pbH(mdl));
                pbRetryEnd("PACKET_STORAGE_CHANGED");return false;
            }
            pbNblCheckIdentity();
            pbNeed(pbEq(pbQ(s.nbl.add(0xe0)),raw),"WFP_INFO_CHANGED_DURING_READ");
            pbLog("RECEIVE epoch="+s.epoch.toString(16)+" ep="+pbH(ep)+" nbl="+pbH(nbl)+" raw="+s.reads.toString(16));
            pbNblSnapshot("receive");r.pairs++;pbRetryEnd("MATCH");return true;
        }
        if (r.samples<4) {r.samples++;pbLog("REJECT epoch="+s.epoch.toString(16)+" reason="+reason+" ip="+pbH(ip));}
        if (r.reads>=512) {pbRetryEnd("TOTAL_LIMIT");return pbRetryFail(new Error("TOTAL_LIMIT"));}
        if (s.reads>=64) pbRetryEnd("READ_LIMIT");
        return false;
    } catch(e) {
        var reason=e && /^[A-Z_]+$/.test(e.message)?e.message:"MEMORY_OR_LAYOUT";
        try {pbRetryEnd(reason);} catch (_) {return pbRetryFail(e);}
        return false;
    }
}

// Conditions always continue; diagnostic logging and owned-watch cleanup stay bounded.
function pbRetryCreateQuiet(a,b,c) { pbRetryCreate(a,b,c); }
function pbRetrySourceQuiet(a,b,c,d,e,f) { pbRetrySource(a,b,c,d,e,f); return false; }
function pbRetryReadQuiet(a,b,c,d,e,f) { pbRetryRead(a,b,c,d,e,f); return false; }
