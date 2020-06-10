#include <stdio.h>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef WIN32
#include <Windows.h>
#define limit 32767
void directory_get_entries_recursively(const char* path) {

  DWORD attrs = GetFileAttributesA(path);
  if (attrs == INVALID_FILE_ATTRIBUTES) {  
    printf("GetFileAttributesA(%s) (in main) failed\n", path); 
    return;
  }

  if (! (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    if (attrs & FILE_ATTRIBUTE_READONLY) {
      /* printf("Readonly %s\n", path); */
      /* printf("Attrs: %x \nRemoving readonly attribute\n", attrs); */
      SetFileAttributesA(path, attrs & (~FILE_ATTRIBUTE_READONLY));
    } else {
      /* printf("RW %s\n", path); */
    }
    /* DeleteFileA(path); */
    return;
  }
  
  WIN32_FIND_DATA ffd;
  char search_path[limit];
  strcpy(search_path, path);
  strcat(search_path, "\\*");
  HANDLE hFind = FindFirstFile(search_path, &ffd);
  if (INVALID_HANDLE_VALUE == hFind) {
    /* printf("FindFirstFile failed for %s\n", path); */
    return;
  }
  do {
    if (strcmp(ffd.cFileName, ".") != 0 && strcmp(ffd.cFileName, "..") != 0) { 
      char child_path[limit];
      strcpy(child_path, path);
      strcat(child_path, "\\");
      strcat(child_path, ffd.cFileName);
      DWORD child_attrs = GetFileAttributesA(child_path);
      if (child_attrs == INVALID_FILE_ATTRIBUTES) {  
	/* printf("GetFileAttributesA(%s) (while iterating) failed\n", child_path);  */
	return;
      }
      if (child_attrs & FILE_ATTRIBUTE_READONLY) {
	/* printf("Readonly %s\n", child_path); */
	/* printf("Attrs: %x \nRemoving readonly attribute\n", child_attrs); */
	DWORD newAttrs = child_attrs & (~FILE_ATTRIBUTE_READONLY);
	if(SetFileAttributesA(child_path, newAttrs)) {
	  /* DeleteFileA(child_path); */
	  /* printf("Updated file attributes to %x\n", newAttrs); */
	} else {
	  /* printf("Failed to set attrs to %x \n", newAttrs); */
	}
      } else {
	/* printf("RW %s\n", child_path); */
      }
      if (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
	/* printf("Directory: %s\n", child_path); */
        directory_get_entries_recursively(child_path);
	/* RemoveDirectoryA(child_path); */
      }
    }
  } while (FindNextFile(hFind, &ffd) != 0);
  /* RemoveDirectoryA(path); */
}

#endif

CAMLprim value
esy_win32_remove_readonly_attribute(value path_mlstr) {
#ifndef WIN32
    return Val_unit; 
#else
    const char* path = String_val(path_mlstr); 
    directory_get_entries_recursively(path);
    return Val_unit; 
#endif
}
