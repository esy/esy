#include <caml/mlvalues.h>
#include <sys/types.h>
#include <sys/stat.h>

#if __APPLE__ || __linux__
// Reference: https://man7.org/linux/man-pages/man3/getumask.3.html
mode_t getumask(void) {
    mode_t mask = umask( 0 );
    umask(mask);
    return mask;
}
#else 
#include <io.h>
// Reference: https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/umask-s?view=msvc-160#example
int windows_getumask() {
    int oldmask, err, dontcare;

    err = _umask_s( _S_IWRITE, &oldmask );
    if (err)
    {
        printf("Error setting the umask.\n");
        exit(1);
    }
    err = _umask_s( oldmask, &dontcare );
    if (err)
    {
        printf("Error setting the umask.\n");
        exit(1);
    }
    return oldmask;
}
#endif


CAMLprim value
esy_getumask(value unit) {
#if __APPLE__ || __linux__
    mode_t umask = getumask();
    return Val_int((int) umask);
#else
    int umask = windows_getumask();
    return Val_int(umask);
#endif
}
