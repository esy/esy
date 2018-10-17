#include <cstdio>
#include <iostream>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>
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
  while (j <= haystackLen - needleLen) {
    if (hx == hy && memcmp(needle, haystack + j, needleLen) == 0) {
      return j;
    }
    hy = REHASH(haystack[j], haystack[j + needleLen], hy);
    ++j;
  }

  return -1;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    cout << "usage: fastreplacestring <filename> <term> <replacement>\n";
    return 1;
  }

  string filename = argv[argc - 3];
  const char *old = argv[argc - 2];
  const char *newWord = argv[argc - 1];
  FILE *in = fopen(filename.c_str(), "rb");

  // Check if file exists and can is read-write
  // This is actually a shortcut because fopen might fail for a number of
  // reasons
  if (in == NULL) {
    cout << "error: " + filename + " doesn't exist\n";
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
    printf("malloc s filelen problem \n");
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
      free(s);
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
    stat(filename.c_str(), &st);

    // change st_mode so we can open file for writing
    chmod(filename.c_str(), S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);
    in = freopen(filename.c_str(), "wb", in);
    if (in == NULL) {
      cout << "error: " + filename + " cannot be written to.\n";
      return 1;
    }

    fwrite(t, 1, newFilelen, in);
    fclose(in);

    // restore st_mode
    chmod(filename.c_str(), st.st_mode);
  }

  return 0;
}
