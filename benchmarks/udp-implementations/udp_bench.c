// Isolated user-mode benchmark. Public test key, not production credentials.
#define WIN32_LEAN_AND_MEAN
#define FD_SETSIZE 1024
#include <winsock2.h>
#include <windows.h>
#include <bcrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#pragma comment(lib,"ws2_32.lib")
#pragma comment(lib,"bcrypt.lib")
#define BODY 512
#define SIGNED_BYTES (32+BODY)
#define PACKET (SIGNED_BYTES+32)
#define MAGIC 0x31424c50u
typedef struct { BCRYPT_ALG_HANDLE alg; BCRYPT_HASH_HANDLE hash; PUCHAR object; } MAC;
static SOCKET server_socket;
static volatile LONG stopped;
static volatile LONG64 nonce=1, accepted, invalid, send_errors;
static uint32_t u32(const unsigned char *p) { uint32_t v; memcpy(&v,p,4); return v; }
static uint64_t u64(const unsigned char *p) { uint64_t v; memcpy(&v,p,8); return v; }
static void p32(unsigned char *p,uint32_t v) { memcpy(p,&v,4); }
static void p64(unsigned char *p,uint64_t v) { memcpy(p,&v,8); }
static LONGLONG tick(void) { LARGE_INTEGER v; QueryPerformanceCounter(&v); return v.QuadPart; }
static MAC open_mac(void) {
    MAC m={0}; DWORD size=0,n=0; unsigned char key[32];
    for(unsigned i=0;i<32;i++) key[i]=(unsigned char)i;
    if(BCryptOpenAlgorithmProvider(&m.alg,BCRYPT_SHA256_ALGORITHM,NULL,BCRYPT_ALG_HANDLE_HMAC_FLAG)<0 ||
       BCryptGetProperty(m.alg,BCRYPT_OBJECT_LENGTH,(PUCHAR)&size,sizeof(size),&n,0)<0) exit(3);
    m.object=(PUCHAR)malloc(size); if(!m.object)exit(3);
    if(BCryptCreateHash(m.alg,&m.hash,m.object,size,key,32,BCRYPT_HASH_REUSABLE_FLAG)<0)exit(3);
    return m;
}
static void close_mac(MAC *m) { BCryptDestroyHash(m->hash); BCryptCloseAlgorithmProvider(m->alg,0); free(m->object); }
static void sign(MAC *m,const unsigned char *p,unsigned char *tag) {
    if(BCryptHashData(m->hash,(PUCHAR)p,SIGNED_BYTES,0)<0 || BCryptFinishHash(m->hash,tag,32,0)<0)exit(3);
}
static int valid(MAC *m,const unsigned char *p,int n,unsigned kind,uint64_t run) {
    unsigned diff=0; unsigned char expected[32]; uint32_t flow,seq;
    if(n!=PACKET || u32(p)!=MAGIC || p[4]!=1 || p[5] || p[6]!=kind || p[7] || u64(p+24)!=run)return 0;
    flow=u32(p+8);seq=u32(p+12);if(flow>=1024)return 0;
    sign(m,p,expected);
    for(unsigned i=0;i<32;i++)diff|=(unsigned)(expected[i]^p[SIGNED_BYTES+i]);
    for(unsigned i=0;i<BODY;i++)diff|=(unsigned)(p[32+i]^(unsigned char)(flow+seq+i));
    return diff==0;
}
static DWORD WINAPI serve_packets(LPVOID unused) {
    unsigned char packet[65536]; MAC mac=open_mac(); (void)unused;
    while(!InterlockedCompareExchange(&stopped,0,0)) {
        struct sockaddr_in peer;int size=sizeof(peer);
        int n=recvfrom(server_socket,(char*)packet,sizeof(packet),0,(struct sockaddr*)&peer,&size);
        if(n==SOCKET_ERROR) { int e=WSAGetLastError();if(e==WSAETIMEDOUT)continue; if(stopped)break; InterlockedIncrement64(&send_errors);continue; }
        if(!valid(&mac,packet,n,1,(uint64_t)InterlockedCompareExchange64(&nonce,0,0))) { InterlockedIncrement64(&invalid);continue; }
        packet[6]=2;sign(&mac,packet,packet+SIGNED_BYTES);
        if(sendto(server_socket,(char*)packet,PACKET,0,(struct sockaddr*)&peer,size)!=PACKET)InterlockedIncrement64(&send_errors);
        else InterlockedIncrement64(&accepted);
    }
    close_mac(&mac);return 0;
}
static int server(void) {
    struct sockaddr_in address={0};int size=sizeof(address),buffer=4*1024*1024;DWORD timeout=200;
    char line[128];HANDLE thread;
    server_socket=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);if(server_socket==INVALID_SOCKET)return 4;
    if(setsockopt(server_socket,SOL_SOCKET,SO_RCVBUF,(char*)&buffer,sizeof(buffer)) ||
       setsockopt(server_socket,SOL_SOCKET,SO_SNDBUF,(char*)&buffer,sizeof(buffer)) ||
       setsockopt(server_socket,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout)))return 4;
    address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(server_socket,(struct sockaddr*)&address,sizeof(address)))return 4;
    if(getsockname(server_socket,(struct sockaddr*)&address,&size))return 4;
    size=sizeof(buffer);
    if(getsockopt(server_socket,SOL_SOCKET,SO_RCVBUF,(char*)&buffer,&size))return 4;
    thread=CreateThread(NULL,0,serve_packets,NULL,0,NULL);if(!thread)return 4;
    printf("{\"ready\":true,\"port\":%u,\"receive_buffer\":%d}\n",ntohs(address.sin_port),buffer);fflush(stdout);
    while(fgets(line,sizeof(line),stdin)) {
        if(!strncmp(line,"RESET ",6)) {
            InterlockedExchange64(&nonce,(LONG64)_strtoui64(line+6,NULL,16));
            InterlockedExchange64(&accepted,0);InterlockedExchange64(&invalid,0);InterlockedExchange64(&send_errors,0);
            puts("{\"reset\":true}");
        } else if(!strncmp(line,"STATS",5)) {
            printf("{\"accepted\":%llu,\"invalid\":%llu,\"send_errors\":%llu}\n",
                (unsigned long long)InterlockedCompareExchange64(&accepted,0,0),
                (unsigned long long)InterlockedCompareExchange64(&invalid,0,0),
                (unsigned long long)InterlockedCompareExchange64(&send_errors,0,0));
        } else if(!strncmp(line,"STOP",4))break;
        fflush(stdout);
    }
    InterlockedExchange(&stopped,1);closesocket(server_socket);
    if(WaitForSingleObject(thread,3000)!=WAIT_OBJECT_0)return 5;
    CloseHandle(thread);return 0;
}
static const char *option(int argc,char **argv,const char *key,const char *fallback) {
    for(int i=2;i+1<argc;i++)if(!strcmp(argv[i],key))return argv[i+1];return fallback;
}
static int compare_double(const void *a,const void *b) { double x=*(const double*)a,y=*(const double*)b;return(x>y)-(x<y); }
static int load(int argc,char **argv) {
    unsigned flows=(unsigned)atoi(option(argc,argv,"--flows","128"));
    double seconds=atof(option(argc,argv,"--seconds","4")),pps=atof(option(argc,argv,"--pps","100"));
    uint64_t run=_strtoui64(option(argc,argv,"--nonce","1"),NULL,16);
    struct sockaddr_in target={0};SOCKET sockets[1024]; LARGE_INTEGER frequency;
    uint32_t sent=0,received=0,invalid_count=0,duplicates=0,errors=0,planned;
    LONGLONG started,now,deadline;MAC mac=open_mac();unsigned char packet[65536];
    LONGLONG *timestamps;unsigned char *seen;double *latency;
    if(!flows || flows>512 || seconds<.1 || seconds>10 || pps<1 || pps>10000)return 2;
    planned=(uint32_t)(flows*pps*seconds);if(planned>5000000)return 2;
    timestamps=(LONGLONG*)calloc(planned+1,sizeof(*timestamps));seen=(unsigned char*)calloc(planned+1,1);latency=(double*)malloc((planned+1)*sizeof(double));
    if(!timestamps || !seen || !latency)return 3;
    target.sin_family=AF_INET;target.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    target.sin_port=htons((u_short)atoi(option(argc,argv,"--port","0")));
    for(unsigned i=0;i<flows;i++) {
        struct sockaddr_in local={0};int buffer=256*1024;u_long nonblocking=1;
        sockets[i]=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);if(sockets[i]==INVALID_SOCKET)return 4;
        setsockopt(sockets[i],SOL_SOCKET,SO_RCVBUF,(char*)&buffer,sizeof(buffer));
        local.sin_family=AF_INET;local.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        if(bind(sockets[i],(struct sockaddr*)&local,sizeof(local)))return 4;
        ioctlsocket(sockets[i],FIONBIO,&nonblocking);
    }
    QueryPerformanceFrequency(&frequency);started=tick();deadline=started+(LONGLONG)(seconds*(double)frequency.QuadPart);
    for(;;) {
        fd_set ready;struct timeval timeout={0,0};now=tick();
        for(unsigned batch=0;batch<32 && sent<planned && now<deadline;batch++) {
            unsigned flow;LONGLONG due=started+(LONGLONG)((double)sent/(flows*pps)*(double)frequency.QuadPart);
            if(now<due)break;
            flow=sent%flows;memset(packet,0,32);p32(packet,MAGIC);packet[4]=1;packet[6]=1;
            p32(packet+8,flow);p32(packet+12,sent);p64(packet+16,(uint64_t)now);p64(packet+24,run);
            for(unsigned j=0;j<BODY;j++)packet[32+j]=(unsigned char)(flow+sent+j);
            sign(&mac,packet,packet+SIGNED_BYTES);timestamps[sent]=now;
            if(sendto(sockets[flow],(char*)packet,PACKET,0,(struct sockaddr*)&target,sizeof(target))!=PACKET)errors++;
            sent++;now=tick();
        }
        FD_ZERO(&ready);for(unsigned i=0;i<flows;i++)FD_SET(sockets[i],&ready);
        if(select(0,&ready,NULL,NULL,&timeout)==SOCKET_ERROR)return 6;
        for(unsigned i=0;i<flows;i++)if(FD_ISSET(sockets[i],&ready)) {
            for(unsigned batch=0;batch<8;batch++) {
                struct sockaddr_in peer;int size=sizeof(peer),n=recvfrom(sockets[i],(char*)packet,sizeof(packet),0,(struct sockaddr*)&peer,&size);
                uint32_t sequence;
                if(n==SOCKET_ERROR) {if(WSAGetLastError()!=WSAEWOULDBLOCK)errors++;break;}
                if(peer.sin_addr.s_addr!=target.sin_addr.s_addr || peer.sin_port!=target.sin_port || !valid(&mac,packet,n,2,run)) {invalid_count++;continue;}
                sequence=u32(packet+12);
                if(sequence>=sent || u32(packet+8)!=i || sequence%flows!=i || u64(packet+16)!=(uint64_t)timestamps[sequence]) {invalid_count++;continue;}
                if(seen[sequence]) {duplicates++;continue;}seen[sequence]=1;
                latency[received++]=(double)(tick()-timestamps[sequence])*1000.0/(double)frequency.QuadPart;
            }
        }
        now=tick();if(now>=deadline && (received==sent || now-deadline>frequency.QuadPart/2))break;
    }
    qsort(latency,received,sizeof(double),compare_double);
    printf("{\"planned\":%u,\"sent\":%u,\"received\":%u,\"invalid\":%u,\"duplicates\":%u,\"errors\":%u,\"elapsed\":%.6f,\"offered_pps\":%.2f,\"p50_ms\":%.6f,\"p99_ms\":%.6f,\"max_ms\":%.6f}\n",
        planned,sent,received,invalid_count,duplicates,errors,(double)(now-started)/(double)frequency.QuadPart,sent/seconds,
        received?latency[received/2]:0,received?latency[(uint64_t)(received-1)*99/100]:0,received?latency[received-1]:0);
    for(unsigned i=0;i<flows;i++)closesocket(sockets[i]);
    close_mac(&mac);free(timestamps);free(seen);free(latency);return 0;
}
int main(int argc,char **argv) {
    WSADATA data;int result;if(argc<2 || WSAStartup(MAKEWORD(2,2),&data))return 2;
    result=!strcmp(argv[1],"server")?server():!strcmp(argv[1],"load")?load(argc,argv):2;
    WSACleanup();return result;
}
