#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <evntrace.h>
#include <evntcons.h>
#include <tdh.h>
#include <cstdio>
#include <string>
#include <vector>
#include <algorithm>

// Saved-file decoder only: never enables a provider or attaches to a process.
static FILE* output;
static unsigned long long records, selected;
static bool boundExceeded;
static const unsigned long long maximumRows = 2000000, maximumBytes = 512ULL*1024*1024;
static std::string guidText(const GUID& g) {
    char s[40]; sprintf_s(s,"%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",g.Data1,g.Data2,g.Data3,g.Data4[0],g.Data4[1],g.Data4[2],g.Data4[3],g.Data4[4],g.Data4[5],g.Data4[6],g.Data4[7]); return s;
}
static void jsonString(const wchar_t* s) {
    fputc('"',output);
    if(s) for(;*s;++s) {
        if(*s=='"'||*s=='\\') {fputc('\\',output); fputc(*s,output);}
        else if(*s>=32&&*s<127) fputc(*s,output);
        else fprintf(output,"\\u%04x",static_cast<unsigned>(*s));
    }
    fputc('"',output);
}
static void hex(const void* p, unsigned n) {
    const unsigned char* b=static_cast<const unsigned char*>(p);
    for(unsigned i=0;i<n;++i) fprintf(output,"%02x",b[i]);
}
static void WINAPI receive(EVENT_RECORD* e) {
    ++records;
    const std::string guid=guidText(e->EventHeader.ProviderId);
    if(guid!="2f07e2ee-15db-40f1-90ef-9d7ba282188a" && guid!="97dcf1eb-61bd-3c9f-e009-df6b3349ea30" && guid!="e53c6823-7bb8-44bb-90dc-3f86090d48a6" && guid!="00e7ee66-5b24-5c41-22cb-af98f63e2f90") return;
    if(boundExceeded || selected>=maximumRows || _ftelli64(output)>=static_cast<__int64>(maximumBytes)) {boundExceeded=true;return;}
    ++selected;
    const EVENT_DESCRIPTOR& d=e->EventHeader.EventDescriptor;
    fprintf(output,"{\"provider\":\"%s\",\"id\":%u,\"version\":%u,\"level\":%u,\"opcode\":%u,\"keyword\":%llu,\"pid\":%lu,\"tid\":%lu,\"qpc\":%lld,\"header_flags\":%u,\"activity_id\":\"%s\",\"payload_length\":%u,\"payload_hex\":\"",guid.c_str(),d.Id,d.Version,d.Level,d.Opcode,d.Keyword,e->EventHeader.ProcessId,e->EventHeader.ThreadId,e->EventHeader.TimeStamp.QuadPart,e->EventHeader.Flags,guidText(e->EventHeader.ActivityId).c_str(),e->UserDataLength);
    hex(e->UserData,e->UserDataLength);fprintf(output,"\"");
    ULONG bytes=0, status=TdhGetEventInformation(e,0,nullptr,nullptr,&bytes);
    if(status==ERROR_INSUFFICIENT_BUFFER && bytes>=sizeof(TRACE_EVENT_INFO) && bytes<=1024*1024) {
        std::vector<unsigned char> storage(bytes);
        TRACE_EVENT_INFO* info=reinterpret_cast<TRACE_EVENT_INFO*>(storage.data());
        status=TdhGetEventInformation(e,0,nullptr,info,&bytes);
        if(status==ERROR_SUCCESS) {
            fprintf(output,",\"decoding_source\":%u,\"event_name\":",static_cast<unsigned>(info->DecodingSource));
            const ULONG nameOffset=(info->DecodingSource==DecodingSourceXMLFile || info->DecodingSource==DecodingSourceTlg)?info->EventNameOffset:0;
            jsonString(nameOffset && nameOffset<bytes?reinterpret_cast<wchar_t*>(storage.data()+nameOffset):L"");
            fprintf(output,",\"properties\":{");
            bool first=true;
            for(ULONG i=0;i<info->TopLevelPropertyCount;++i) {
                const EVENT_PROPERTY_INFO& p=info->EventPropertyInfoArray[i];
                if(!first)fputc(',',output);first=false;
                const wchar_t* name=reinterpret_cast<wchar_t*>(storage.data()+p.NameOffset);
                jsonString(name); fprintf(output,":{");
                ULONG fieldSize=0, code=ERROR_NOT_SUPPORTED;
                if(!(p.Flags&PropertyStruct)) {
                    PROPERTY_DATA_DESCRIPTOR desc{}; desc.PropertyName=reinterpret_cast<ULONGLONG>(name); desc.ArrayIndex=ULONG_MAX;
                    code=TdhGetPropertySize(e,0,nullptr,1,&desc,&fieldSize);
                    fprintf(output,"\"in_type\":%u,\"out_type\":%u,",p.nonStructType.InType,p.nonStructType.OutType);
                    if(code==ERROR_SUCCESS && fieldSize<=65536) {
                        std::vector<unsigned char> field(fieldSize);
                        code=TdhGetProperty(e,0,nullptr,1,&desc,fieldSize,field.data());
                        if(code==ERROR_SUCCESS) {fprintf(output,"\"hex\":\"");hex(field.data(),fieldSize);fprintf(output,"\",");}
                    } else if(code==ERROR_SUCCESS) code=ERROR_MORE_DATA;
                }
                fprintf(output,"\"error\":%lu}",code);
            }
            fprintf(output,"}");
        }
    }
    fprintf(output,",\"decode_error\":%lu}\n",status);
}
int wmain(int argc,wchar_t** argv) {
    if(argc!=3)return 2;
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    if(!GetFileAttributesExW(argv[1],GetFileExInfoStandard,&attributes) || attributes.nFileSizeHigh || attributes.nFileSizeLow>192*1024*1024)return 3;
    if(_wfopen_s(&output,argv[2],L"wb"))return 4;
    EVENT_TRACE_LOGFILEW file{};file.LogFileName=argv[1];file.ProcessTraceMode=PROCESS_TRACE_MODE_EVENT_RECORD|PROCESS_TRACE_MODE_RAW_TIMESTAMP;file.EventRecordCallback=receive;
    TRACEHANDLE handle=OpenTraceW(&file);
    if(handle==INVALID_PROCESSTRACE_HANDLE){fclose(output);return 5;}
    ULONG code=ProcessTrace(&handle,1,nullptr,nullptr), close=CloseTrace(handle);
    int writeError=ferror(output);if(fclose(output))writeError=1;
    printf("{\"method\":\"saved-wfp-afd-etl-v1\",\"records\":%llu,\"selected\":%llu,\"clock_type\":%lu,\"qpc_frequency\":%lld,\"events_lost\":%lu,\"buffers_lost\":%lu,\"bound_exceeded\":%s,\"process_trace_status\":%lu,\"close_trace_status\":%lu,\"write_error\":%d}\n",records,selected,file.LogfileHeader.ReservedFlags,file.LogfileHeader.PerfFreq.QuadPart,file.LogfileHeader.EventsLost,file.LogfileHeader.BuffersLost,boundExceeded?"true":"false",code,close,writeError);
    return code||close||writeError||boundExceeded?6:0;
}
