/* Fake Win32 only: no sockets, events, sleeps, drivers or real waits. */
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
typedef unsigned long DWORD;
typedef unsigned long long ULONGLONG;
typedef int BOOL;
typedef void *HANDLE;
#define TRUE 1
#define FALSE 0
#define WAIT_OBJECT_0 0
#define WAIT_TIMEOUT 258
#define WAIT_FAILED 0xffffffffUL
#define EVENT_MODIFY_STATE 2
#define SYNCHRONIZE 0x100000
static int running, saved_error, opened, closed, waits, signaled, logs;
static int open_fail, signal_fail, wait_mode, bad_route;
static const char *fixture_token;
static ULONGLONG tick;
static int WSAGetLastError(void) {return saved_error;}
static void WSASetLastError(int x) {saved_error=x;}
static DWORD GetEnvironmentVariableA(const char *name,char *buf,DWORD length) {
    const char *value=!strcmp(name,"PB_TESTLAB_ROUTE_CASE") ? (bad_route ? "bad" : "original") : fixture_token;
    size_t n=strlen(value);
    saved_error=99;
    if (n<length) memcpy(buf,value,n+1);
    return (DWORD)n;
}
static HANDLE OpenEventA(DWORD access,BOOL inherit,const char *name) {
    (void)access;
    if (inherit || !strstr(name,"Local\\PBTarget-")) abort();
    ++opened;
    if (opened==open_fail) return NULL;
    return (HANDLE)(size_t)opened;
}
static BOOL SetEvent(HANDLE handle) {(void)handle;++signaled;return !signal_fail;}
static DWORD WaitForSingleObject(HANDLE handle,DWORD ms) {
    (void)handle;
    if (ms!=50) abort();
    ++waits;
    tick+=50;
    if (wait_mode==1) return WAIT_FAILED;
    if (wait_mode==2) return WAIT_TIMEOUT;
    if (wait_mode==3) {running=FALSE;return WAIT_TIMEOUT;}
    return waits==2 ? WAIT_OBJECT_0 : WAIT_TIMEOUT;
}
static ULONGLONG GetTickCount64(void) {return tick;}
static BOOL CloseHandle(HANDLE handle) {if (!handle) abort();++closed;return TRUE;}
static void log_message(const char *format,...) {(void)format;++logs;saved_error=123;}
#include "../../src/diagnostics/pb_target_accept_gate.h"
static void reset(void) {
    running=TRUE;saved_error=17;opened=closed=waits=signaled=logs=0;
    open_fail=signal_fail=wait_mode=bad_route=0;tick=0;
    fixture_token="0123456789abcdef0123456789abcdef";
}
static void require(int condition,const char *name) {if (!condition) {fprintf(stderr,"FAILED %s\n",name);exit(1);}}
int main(void) {
    reset();require(pbdiag_target_accept_gate() && closed==2 && waits==2 && saved_error==17,"release_and_wsa");
    reset();wait_mode=2;require(!pbdiag_target_accept_gate() && closed==2 && waits==600 && saved_error==17,"bounded_timeout");
    reset();wait_mode=1;require(!pbdiag_target_accept_gate() && closed==2 && waits==1 && saved_error==17,"wait_failure");
    reset();wait_mode=3;require(!pbdiag_target_accept_gate() && closed==2 && waits==1,"cancelled");
    reset();open_fail=1;require(!pbdiag_target_accept_gate() && closed==0 && !waits,"ready_missing");
    reset();open_fail=2;require(!pbdiag_target_accept_gate() && closed==1 && !waits,"release_missing");
    reset();signal_fail=1;require(!pbdiag_target_accept_gate() && closed==2 && !waits,"signal_failure");
    reset();fixture_token="bad";require(!pbdiag_target_accept_gate() && !opened && saved_error==17,"short_token");
    reset();fixture_token="0123456789abcdef0123456789abcdeg";require(!pbdiag_target_accept_gate() && !opened,"invalid_hex");
    reset();bad_route=1;require(!pbdiag_target_accept_gate() && !opened,"wrong_route");
    puts("TARGET_GATE_FAKE_API_10_PASSED");return 0;
}
