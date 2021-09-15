#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <sys/types.h>
#include <sys/stat.h>

#if WIN32
#include <io.h>
#include <string.h>
#endif


CAMLprim value
esy_getumask() {
    CAMLparam0();
    CAMLlocal1( result );
#if WIN32
    // Reference: https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/umask-s?view=msvc-160#example
    int oldmask, err, dontcare;

    err = _umask_s( _S_IWRITE, &oldmask );
    if (err) {
        result = caml_alloc( 1, 1 );
        char *msg = strerror(err);
        Store_field( result, 0, caml_copy_string(msg) ); // Error(msg)
    } else {
        err = _umask_s( oldmask, &dontcare );
        if (err) {
            result = caml_alloc( 1, 1 );
            char *msg = strerror(err);
            Store_field( result, 0, caml_copy_string(msg) ); // Error(msg)
        } else {
            result = caml_alloc( 1, 0 );
            Store_field( result, 0, Val_int(oldmask) ); // Ok(oldmask)
        }
    }
#else
    // Reference: https://man7.org/linux/man-pages/man3/getumask.3.html
    mode_t mask = umask( 0 );
    umask( mask );
    result = caml_alloc( 1, 0 );
    Store_field( result, 0, Val_int((int) mask) ); // Ok(mask)   
#endif
    CAMLreturn( result );
}
