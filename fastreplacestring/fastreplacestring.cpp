#include <cstdio>
#include <cstring>
#include <sys/stat.h>
#include <stdlib.h>
#include <vector>
#include <iostream>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

using namespace std;

#define REHASH(a, b, h) ((((h) - (a)*d) << 1) + (b))

// Rabin-Karp search (modified from:
// http://www-igm.univ-mlv.fr/~lecroq/string/node5.html#SECTION0050)
int indexOf(const char *needle, size_t needleLen, const char *haystack,
            size_t haystackLen) {
  if (needleLen == 0) {
    return 0;
  } else if (needleLen > haystackLen) {
    return -1;
  }

  int d, hx, hy, i, j;
  /* Preprocessing */
  /* computes d = 2^(m-1) with
    the left-shift operator */
  for (d = i = 1; i < needleLen; ++i)
    d = (d << 1);

  for (hy = hx = i = 0; i < needleLen; ++i) {
    hx = ((hx << 1) + needle[i]);
    hy = ((hy << 1) + haystack[i]);
  }

  /* Searching */
  j = 0;
  do {
    if (hx == hy && memcmp(needle, haystack + j, needleLen) == 0) {
      return j;
    }
    hy = REHASH(haystack[j], haystack[j + needleLen], hy);
    ++j;
  } while (j < haystackLen - needleLen);

  return -1;
}

int replace(const char *filename, const char *old, const char *newWord) {
  FILE *in = fopen(filename, "rb");

  // Check if file exists and can is read-write
  // This is actually a shortcut because fopen might fail for a number of
  // reasons
  if (in == NULL) {
    fclose(in);
    fprintf(stderr, "error: %s doesn't exist\n", filename);
    return 1;
  }

  char *s = NULL;
  vector<int> indexCache;
  size_t r, newFilelen;

  // read filelen given by fileState
  // alternatively this could be determined with fseek && ftell
  fseek(in, 0, SEEK_END);
  size_t filelen = ftell(in);
  fseek(in, 0, SEEK_SET);

  if ((s = (char *)malloc(filelen)) == NULL) {
    fclose(in);
    fprintf(stderr, "error: malloc s filelen problem \n");
    exit(1);
  }

  // Read in as much of specified file as possible
  // If there isn't anything to read, finish succesfully :)
  if ((r = fread(s, 1, filelen, in)) == 0) {
    free(s);
    fclose(in);
    return 0;
  }

  char *t = NULL;
  char *temp = NULL;

  size_t oldLen = strlen(old);
  size_t newLen = strlen(newWord);

  /* Find all matches and cache their positions. */
  const char *test = NULL;
  test = s;
  int j, start = 0, c = 0;
  int index;

  while ((index = indexOf(old, oldLen, test + start, filelen - start)) != -1) {
    c++;
    j = start;
    j += index;
    indexCache.push_back(j);
    start = j + oldLen;
  }

  if (c == 0) {
    free(s);
    fclose(in);
    return 0;
  } else {
    const char *pstr = s;
    // calculate new file len & allocate memory
    newFilelen = filelen + c * (newLen - oldLen);
    t = (char *)malloc(newFilelen);

    int i = 0;
    j = 0;
    start = 0;
    temp = t;

    if (temp == NULL) {
      free(t);
      free(s);
      fclose(in);
      exit(1);
    }
    // replace the bytes
    for (i = 0; i < c; i++) {
      j = indexCache[i];
      memcpy(temp, pstr, j - start);
      temp += j - start;
      pstr = s + j + oldLen;
      memcpy(temp, newWord, newLen);
      temp += newLen;
      start = j + oldLen;
    }
    memcpy(temp, pstr, filelen - start);

    free(s);

    // stat file so we can restore st_mode
    struct stat st;
    stat(filename, &st);

    // change st_mode so we can open file for writing
    chmod(filename, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);
    in = freopen(filename, "wb", in);
    if (in == NULL) {
      free(t);
      fclose(in);
      fprintf(stderr, "error: %s cannot be written to.\n", filename);
      return 1;
    }

    fwrite(t, 1, newFilelen, in);
    free(t);
    fclose(in);

    // restore st_mode
    chmod(filename, st.st_mode);
  }

  return 0;
}

extern "C" {
  CAMLprim value caml_fastreplacestring(value vPath, value vOldWord, value vNewWord) {
    CAMLparam3(vPath, vOldWord, vNewWord);
    CAMLlocal1(vRet);

    const char *szPath = String_val(vPath);
    const char *szOldWord = String_val(vOldWord);
    const char *szNewWord = String_val(vNewWord);

    int ret = replace(szPath, szOldWord, szNewWord);
    if (ret == 0) {
      /* Ok() */
      vRet = caml_alloc(1, 0);
      Store_field (vRet, 0, Val_unit);
    } else {
      /* Error(..) */
      vRet = caml_alloc(1, 1);
      Store_field (vRet, 0, caml_copy_string("error rewriting file"));
    }
    CAMLreturn(vRet);
  }
}
