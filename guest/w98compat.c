/*
 * Linked into C++ DLLs for Windows 98. MSYS2 builds libstdc++ with stack protection
 * and fortified string functions, and the C library's failure handlers for those call
 * IsProcessorFeaturePresent, which Windows 98's kernel32 lacks: Windows would refuse to
 * load the DLL. Defining the handlers here keeps the library's versions out.
 */
#include <stdlib.h>

void __chk_fail(void)
{
    abort();
}

void __stack_chk_fail(void)
{
    abort();
}

/*
 * Linux cross toolchain (Ubuntu mingw GCC): libgcc's gthr-win32 imports GetThreadId
 * (Windows XP SP1+) and libmingwex imports IsDBCSLeadByteEx. Windows 98's kernel32 lacks
 * them, so the DLL fails to initialise (error 31). Defining the import-table slots here
 * keeps the import-library members, and so the imports, out of the DLL.
 */
#include <windows.h>

static DWORD WINAPI w98_GetThreadId(HANDLE h)
{
    (void)h;
    return GetCurrentThreadId();
}

static BOOL WINAPI w98_IsDBCSLeadByteEx(UINT cp, BYTE c)
{
    (void)cp;
    return IsDBCSLeadByte(c);
}

void *w98_imp_GetThreadId __asm__("__imp__GetThreadId@4") = (void *)w98_GetThreadId;
void *w98_imp_IsDBCSLeadByteEx __asm__("__imp__IsDBCSLeadByteEx@8") = (void *)w98_IsDBCSLeadByteEx;
