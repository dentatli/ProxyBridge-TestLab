"use strict";
// Read-only target memory. Debugger commands only replace owned watchpoint 3.
var pbNblConfig = null;
var pbNblState = null;
function initializeScript() { return [new host.apiVersionSupport(1, 3)]; }
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
function pbLog(s) { host.diagnostics.debugLog("PBN " + s + "\n"); }
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
    return true;
}
// Explicit isolated CDB fixture entry. Runtime evidence must have CONFIG model=0.
function pbNblInitModel(get, retrieveReturn, acceptReturn, bad) {
    pbNeed(pbNblState === null || !pbNblState.armed, "WATCH_STILL_ARMED");
    pbNblIntegerChecks();
    pbNblConfig = {get:pbI(get), retrieveReturn:pbI(retrieveReturn), acceptReturn:pbI(acceptReturn), bad:pbI(bad), model:true};
    pbNblState = null;
    pbLog("CONFIG model=1 get=" + pbH(get) + " retrieve_return=" + pbH(retrieveReturn) + " accept_return=" + pbH(acceptReturn));
    return true;
}
function pbNblClear() {
    if (pbNblState && pbNblState.armed) {
        pbCommand("bc3",true);
        pbCommand("r @$t8 = 0");
        pbNblState.armed = false;
    }
}
function pbNblStop() { pbNblClear(); return true; }
function pbNblFail(stage, error) {
    try { pbNblClear(); } catch (_) { pbLog("INCOMPLETE stage=cleanup reason=DEBUGGER_COMMAND"); }
    var reason = error && /^[A-Z_]+$/.test(error.message) ? error.message : "MEMORY_OR_LAYOUT";
    pbLog("INCOMPLETE stage=" + stage + " reason=" + reason);
    return false;
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
    pbNeed(bytes[0]===0xa4 && bytes[1]===0xd9 && bytes[2]===0x84 && bytes[3]===0xda &&
        (bytes[12]>>4)>=5 && (bytes[13]&0x17)===2, "PACKET_TUPLE");
    return {nb:nb,mdl:mdl,header:header,sequence:bytes.slice(4,8).join(":"),flags:bytes[13]};
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
    pbLog("STATE stage="+stage+" nbl="+pbH(s.nbl)+" info_raw="+pbH(raw)+" info="+pbH(info)+" root="+pbH(root)+
        " key5="+(found?"present":"absent")+" value="+pbH(value)+" record_match="+(found&&pbEq(value,s.record)?1:0)+" nodes="+nodes);
}
function pbNblArm(nbl, record, source) {
    try {
        pbNeed(pbNblState===null, "ARM_REPEATED");
        pbNblState={nbl:pbI(nbl),record:pbI(record),source:pbI(source),armed:true,reads:0,packet:null};
        // Slot3 is the selected-source watch installed by the reviewed CREATE handler.
        pbNblClear();
        pbNeed(pbNblConfig!==null, "CONFIG_REQUIRED");
        pbNeed(!pbZero(nbl) && pbZero(pbI(nbl).bitwiseAnd(7)) && !pbZero(record), "ARM_IDENTITY");
        pbNeed(pbEq(pbQ(pbI(source).add(0x1c0)),record), "SOURCE_RECORD_CHANGED");
        pbNblState.packet=pbNblPacket(pbI(nbl));
        pbNblSnapshot("send");
        pbCommand("ba3 r8 0x"+pbH(pbI(nbl).add(0xe0))+" \"dx @$scriptContents.pbNblRead(@rcx,@rbx,@rip,@rsp,@rsi,@rbp); gc;\"");
        pbNblState.armed=true;pbCommand("r @$t8 = 1");
        pbLog("ARMED nbl="+pbH(nbl)+" address="+pbH(pbI(nbl).add(0xe0))+" limit=10");
        return true;
    } catch(e) {return pbNblFail("send",e);}
}
function pbNblRead(nbl, raw, ip, sp, key, consume) {
    try {
        var s=pbNblState;
        if (!s || !s.armed) return false;
        s.reads++;
        if (pbEq(ip,pbNblConfig.get) && pbEq(nbl,s.nbl) && pbEq(key,5) && pbEq(consume,1) &&
            pbEq(pbQ(pbI(sp).add(0x38)),pbNblConfig.retrieveReturn) &&
            pbEq(pbQ(pbI(sp).add(0xa8)),pbNblConfig.acceptReturn)) {
            pbNblCheckIdentity();
            pbNeed(pbEq(pbQ(s.nbl.add(0xe0)),raw), "WFP_INFO_CHANGED_DURING_READ");
            var frame=pbQ(pbI(sp).add(0x98)), ep=pbQ(pbI(sp).add(0xb8));
            pbNeed(pbSmall(frame.subtract(0x7c),2)===0xda84 && pbSmall(frame.subtract(0x7a),2)===0xd9a4 && !pbZero(ep), "ACCEPT_TUPLE");
            pbLog("RECEIVE nbl="+pbH(nbl)+" ep="+pbH(ep)+" raw="+s.reads.toString(16)+" key=5 consume=1");
            pbNblSnapshot("receive");pbNblClear();pbLog("DONE nbl="+pbH(nbl));return true;
        }
        if (s.reads>=16) throw new Error("READ_LIMIT");
        return false;
    } catch(e) {return pbNblFail("receive",e);}
}
