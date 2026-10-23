"use strict";
// UI families expand to the existing case IDs; execution and evidence stay per case.
const trafficFamilyDefinitions=[
  {id:"tcp",ru:"TCP",en:"TCP",ids:["three-modes","tcp-rtt","tcp-upload","tcp-download","tcp-duplex","tcp-multistream","loaded-rtt","tcp-connections","flow-rate"],basic:["tcp-rtt","tcp-upload","tcp-download"],standard:["tcp-rtt","tcp-upload","tcp-download","tcp-duplex","tcp-multistream","loaded-rtt"]},
  {id:"udp",ru:"UDP",en:"UDP",ids:["udp-connected","udp-unconnected","udp-sweep","udp-connections"],basic:["udp-connected","udp-unconnected"],standard:["udp-connected","udp-unconnected","udp-sweep"]},
  {id:"web",ru:"HTTP, WebSocket и gRPC",en:"HTTP, WebSocket and gRPC",applications:["http","https","http2","http3","grpc","websocket","websocket-tls"],basic:["app-http","app-https","app-websocket","app-websocket-tls"],standard:["app-http","app-https","app-websocket","app-websocket-tls","app-http2","app-grpc","app-http3"]},
  {id:"security",ru:"TLS и QUIC",en:"TLS and QUIC",applications:["tls","quic"],basic:["app-tls","app-quic"]},
  {id:"dns",ru:"DNS",en:"DNS",families:["dns-classic","dns-encrypted"],basic:["app-dns-tcp","app-dns-udp"]},
  {id:"ssh",ru:"SSH и SFTP",en:"SSH and SFTP",families:["ssh","sftp"],basic:["app-ssh"]},
  {id:"mail",ru:"Почта: SMTP, IMAP и POP3",en:"Mail: SMTP, IMAP and POP3",families:["mail"],basic:["app-smtp","app-imap","app-pop3"]},
  {id:"messaging",ru:"Сообщения: MQTT и AMQP",en:"Messaging: MQTT and AMQP",families:["mqtt","amqp"],basic:["app-mqtt","app-amqp"]},
  {id:"stability",ru:"Стабильность и восстановление",en:"Stability and recovery",ids:["mixed","stability"],basic:["mixed"]},
  {id:"soak",ru:"Длительная стабильность",en:"Endurance",ids:["soak"]}
];
function trafficFamilies(catalog){
  const cases=catalog?.cases||[];
  const families=trafficFamilyDefinitions.map(definition=>{
    const rows=cases.filter(row=>definition.ids?.includes(row.id)||definition.applications?.includes(row.application)||definition.families?.includes(row.family));
    const profiles={};
    for(const [key,ids] of [["BASIC",definition.basic],["STANDARD",definition.standard],["FULL",rows.map(row=>row.id)]]){
      if(ids?.length)profiles[key]=rows.filter(row=>ids.includes(row.id)).map(row=>row.id);
    }
    return {...definition,rows,profiles};
  }).filter(family=>family.rows.length);
  const known=new Set(families.flatMap(family=>family.rows.map(row=>row.id)));
  const unknown=cases.filter(row=>!known.has(row.id));
  if(unknown.length)families.push({id:"other",ru:"Другие проверки",en:"Other checks",rows:unknown,profiles:{FULL:unknown.map(row=>row.id)}});
  return families;
}
function trafficFamilySelection(family,choices,preference={}){
  const selected=family.rows.filter(row=>choices[row.id]?.selected),valid=new Set(family.rows.map(row=>row.id));
  const fallback=family.profiles.STANDARD||family.profiles.FULL;
  const remembered=Array.isArray(preference.ids)?[...new Set(preference.ids.filter(id=>valid.has(id)))]:[];
  const ids=selected.length?selected.map(row=>row.id):remembered.length?remembered:fallback;
  const same=(a,b)=>a.length===b.length&&a.every(id=>b.includes(id));
  const profile=Object.keys(family.profiles).find(key=>same(ids,family.profiles[key]))||"CUSTOM";
  const common=(key,allowed,defaultValue)=>{
    const values=selected.length?selected.map(row=>choices[row.id][key]):[preference[key]||defaultValue];
    return values.every(value=>value===values[0])&&allowed.includes(values[0])?values[0]:"MIXED";
  };
  return {selected:!!selected.length,ids,profile,duration:common("duration",["SHORT","NORMAL","LONG"],"SHORT"),load:common("load",["LOW","HIGH"],"LOW")};
}
function trafficFamilyReportGroups(catalog,requested,results){
  const expected=requested.map(row=>({id:row.id||row.Id,duration:row.duration||row.Duration,load:row.load||row.Load}));
  // Include historic IDs even when they are no longer present in the current catalog.
  const cases=[...(catalog?.cases||[])];
  for(const row of expected)if(!cases.some(item=>item.id===row.id))cases.push({id:row.id});
  return trafficFamilies({cases}).map(family=>{
    const ids=new Set(family.rows.map(row=>row.id)),stages=expected.filter(row=>ids.has(row.id));
    const rows=stages.map(stage=>results.find(row=>row.case_id===stage.id&&row.duration===stage.duration&&row.load===stage.load));
    const passed=rows.filter(row=>row?.complete===true&&row.cleanup_verified===true).length;
    const failed=rows.some(row=>row&&!row.complete&&!row.skipped&&!row.cancelled);
    const status=failed?"FAIL":rows.some(row=>row?.cancelled)?"CANCELLED":passed===stages.length?"PASS":"INCOMPLETE";
    return {family,stages,rows,passed,status};
  }).filter(group=>group.stages.length);
}
