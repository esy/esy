#include <caml/mlvalues.h>

#if __APPLE__ || __linux__
#include <sys/resource.h>
#endif

#define MIN_NOFILE 4096

CAMLprim value
esy_ensure_minimum_file_descriptors(value unit) {
#if __APPLE__ || __linux__
    struct rlimit limits;
    getrlimit(RLIMIT_NOFILE, &limits);
    if (limits.rlim_cur < MIN_NOFILE) {
        limits.rlim_cur = MIN_NOFILE;
        setrlimit(RLIMIT_NOFILE, &limits);
    }
#endif
    return Val_unit; 
}
