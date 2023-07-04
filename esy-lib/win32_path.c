#include <stdio.h>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef WIN32
#include <Windows.h>
#include <winbase.h>
#endif

CAMLprim value
esy_win32_check_long_path_regkey(value unit) {
#ifndef WIN32
    return Val_true; 
#else
    HKEY hKey;
    LONG code = RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            L"SYSTEM\\CurrentControlSet\\Control\\FileSystem",
            0,
            KEY_READ|KEY_WOW64_64KEY,
            &hKey);

    if (code != ERROR_SUCCESS)
        return Val_false;

    BYTE *buffer = (BYTE*)LocalAlloc(LPTR, 4);
    DWORD length = {4};
    code = RegQueryValueExW(
            hKey,
            L"LongPathsEnabled",
            0,
            0,
            buffer,
            &length
            );
    DWORD result = *(DWORD*)buffer;

    if (code != ERROR_SUCCESS)
        return Val_false;

    if (result == 1) {
        return Val_true;
    } else {
        return Val_false;
    }
#endif
}

CAMLprim value
esy_move_file(value src, value dst) {
#ifndef WIN32
  rename(String_val(src), String_val(dst));
#else
  MoveFileExA(String_val(src), String_val(dst), MOVEFILE_COPY_ALLOWED | MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
#endif
  return Val_unit;
}  
