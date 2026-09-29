// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// The libc calls the daemon makes, declared with __extern_cpp so the emitted C++ calls them
// by their own names. None of these is declared by the Slang C++ prelude's headers, so each
// declaration here is the only one. Constants are the Linux values, shared by x86_64 and aarch64.
module libc;

public static const int O_RDONLY = 0;
public static const int O_WRONLY = 1;
public static const int O_RDWR = 2;
public static const int O_CREAT = 0x40;
public static const int O_TRUNC = 0x200;
public static const int O_CLOEXEC = 0x80000;
public static const int SEEK_END = 2;
public static const int PROT_READ = 1;
public static const int PROT_WRITE = 2;
public static const int MAP_SHARED = 1;
public static const int AF_INET = 2;
public static const int SOCK_DGRAM = 2;
public static const int SOL_SOCKET = 1;
public static const int SO_REUSEADDR = 2;
public static const int MSG_DONTWAIT = 0x40;
public static const int CLOCK_MONOTONIC = 1;
public static const int EOWNERDEAD = 130;

public struct IoVec
{
    public uint8_t* base;
    public uint64_t size;
};

public struct TimeSpec
{
    public int64_t seconds;
    public int64_t nanoseconds;
};

// struct sockaddr_in: family, port and address in network byte order, then padding.
public struct SockAddrIn
{
    public uint16_t family;
    public uint16_t port;
    public uint32_t address;
    public uint32_t zero0;
    public uint32_t zero1;
};

public __extern_cpp int open(uint8_t* p_path, int p_flags, int p_mode);
public __extern_cpp int close(int p_fd);
public __extern_cpp int64_t read(int p_fd, uint8_t* p_bytes, uint64_t p_size);
public __extern_cpp int64_t writev(int p_fd, IoVec* p_vectors, int p_count);
public __extern_cpp int64_t lseek(int p_fd, int64_t p_offset, int p_whence);
public __extern_cpp int mkdir(uint8_t* p_path, uint32_t p_mode);
public __extern_cpp int unlink(uint8_t* p_path);
public __extern_cpp uint8_t* mmap(uint8_t* p_address, uint64_t p_length, int p_prot, int p_flags, int p_fd,
                                  int64_t p_offset);
public __extern_cpp int munmap(uint8_t* p_address, uint64_t p_length);
public __extern_cpp int pthread_mutex_lock(uint8_t* p_mutex);
public __extern_cpp int pthread_mutex_unlock(uint8_t* p_mutex);
public __extern_cpp int pthread_mutex_consistent(uint8_t* p_mutex);
public __extern_cpp int usleep(uint32_t p_microseconds);
public __extern_cpp int clock_gettime(int p_clock, TimeSpec* p_time);
public __extern_cpp int socket(int p_domain, int p_type, int p_protocol);
public __extern_cpp int connect(int p_fd, SockAddrIn* p_address, uint32_t p_size);
public __extern_cpp int bind(int p_fd, SockAddrIn* p_address, uint32_t p_size);
public __extern_cpp int setsockopt(int p_fd, int p_level, int p_name, int* p_value, uint32_t p_size);
public __extern_cpp int64_t send(int p_fd, uint8_t* p_bytes, uint64_t p_size, int p_flags);
public __extern_cpp int64_t recv(int p_fd, uint8_t* p_bytes, uint64_t p_size, int p_flags);
public __extern_cpp int* __errno_location();

public int errno_value()
{
    return *__errno_location();
}
