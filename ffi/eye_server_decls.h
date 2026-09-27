/* The system headers that declare every call in abi/eye_server.sigs.
 *
 * sigs_to_header.py includes this ahead of the prototypes it generates, so each .sigs
 * line is compiled as a redeclaration of glibc's own. Any disagreement is an error. */
#ifndef FRAMEEYEOSC_EYE_SERVER_DECLS_H
#define FRAMEEYEOSC_EYE_SERVER_DECLS_H
#include <fcntl.h>
#include <pthread.h>
#include <stddef.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif
