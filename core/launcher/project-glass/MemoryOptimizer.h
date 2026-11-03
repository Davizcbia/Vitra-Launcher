// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QtGlobal>
#ifdef Q_OS_WIN
#include <QCoreApplication>
#include <QDir>
#include <string>
#include <qt_windows.h>
#include <psapi.h>
#include <shellapi.h>
#endif

// Settings › Memory: frees physical memory before the game starts, with
// documented Windows calls only.
//  - trimUserProcesses(): empties the working sets of the processes this user
//    may adjust (no elevation); their idle pages move to the page file.
//  - purgeSystemLists(): also writes out modified pages and drops the standby
//    list (the file cache). Needs administrator rights, so an unelevated
//    launcher runs it in an elevated copy of itself (--pg-optimize-memory,
//    handled at the top of main()).
namespace MemoryOptimizer {
#ifdef Q_OS_WIN
inline constexpr bool supported(){return true;}
inline quint64 availableBytes(){MEMORYSTATUSEX status{};status.dwLength=sizeof(status);return GlobalMemoryStatusEx(&status)?status.ullAvailPhys:0;}
inline void trimUserProcesses(){
    DWORD ids[4096];DWORD bytes=0;
    if(!EnumProcesses(ids,sizeof(ids),&bytes))return;
    const DWORD self=GetCurrentProcessId();
    for(DWORD i=0;i<bytes/sizeof(DWORD);++i) {
        if(ids[i]==0 || ids[i]==self)continue;
        // Fails for other users' and elevated processes: they are skipped.
        if(HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|PROCESS_SET_QUOTA,FALSE,ids[i])) {EmptyWorkingSet(process);CloseHandle(process);}
    }
}
inline bool elevated(){
    HANDLE token=nullptr;TOKEN_ELEVATION elevation{};DWORD size=0;bool result=false;
    if(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)){result=GetTokenInformation(token,TokenElevation,&elevation,sizeof(elevation),&size) && elevation.TokenIsElevated;CloseHandle(token);}
    return result;
}
inline bool enablePrivilege(const wchar_t *name){
    HANDLE token=nullptr;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,&token))return false;
    TOKEN_PRIVILEGES privileges{};privileges.PrivilegeCount=1;privileges.Privileges[0].Attributes=SE_PRIVILEGE_ENABLED;
    const bool ok=LookupPrivilegeValueW(nullptr,name,&privileges.Privileges[0].Luid) &&
                  AdjustTokenPrivileges(token,FALSE,&privileges,0,nullptr,nullptr) && GetLastError()==ERROR_SUCCESS;
    CloseHandle(token);return ok;
}
inline bool purgeSystemLists(){
    // NtSetSystemInformation(SystemMemoryListInformation = 80) commands:
    // 2 empty all working sets, 3 flush the modified list, 4 purge the standby list.
    using SetInformation=LONG(NTAPI *)(INT,PVOID,ULONG);
    const auto set=reinterpret_cast<SetInformation>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtSetSystemInformation"));
    if(!set || !enablePrivilege(L"SeProfileSingleProcessPrivilege"))return false;
    if(enablePrivilege(L"SeIncreaseQuotaPrivilege"))SetSystemFileCacheSize(static_cast<SIZE_T>(-1),static_cast<SIZE_T>(-1),0);
    bool ok=true;
    for(int command:{2,3,4})ok=set(80,&command,sizeof(command))>=0 && ok;
    return ok;
}
// Starts the elevated copy (UAC prompt, from the UI thread); null if declined.
inline HANDLE startElevatedPurge(){
    const std::wstring exe=QDir::toNativeSeparators(QCoreApplication::applicationFilePath()).toStdWString();
    SHELLEXECUTEINFOW info{};info.cbSize=sizeof(info);info.fMask=SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb=L"runas";info.lpFile=exe.c_str();info.lpParameters=L"--pg-optimize-memory";info.nShow=SW_HIDE;
    return ShellExecuteExW(&info) ? info.hProcess : nullptr;
}
inline bool waitForPurge(HANDLE process){
    WaitForSingleObject(process,60000);DWORD code=1;GetExitCodeProcess(process,&code);CloseHandle(process);return code==0;
}
#else
inline constexpr bool supported(){return false;}
#endif
}
