// SPDX-License-Identifier: MIT
// UDP for OSC and mDNS, and one blocking HTTP GET for OSCQuery. IPv4 only, which is
// what VRChat's OSC and OSCQuery listen on.
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <lean/lean.h>

static lean_obj_res net_err(const char *what, int e) {
  char buf[256];
  snprintf(buf, sizeof buf, "%s: %s", what, strerror(e));
  return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(buf)));
}

static int parse_ip(const char *s, struct in_addr *out) { return inet_pton(AF_INET, s, out) == 1; }

// udpOpen : (port : UInt16) → (reuse : UInt8) → IO UInt32
LEAN_EXPORT lean_obj_res fe_udp_open(uint16_t port, uint8_t reuse, lean_obj_arg w) {
  (void)w;
  int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    return net_err("socket", errno);
  }
  if (reuse) {
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one);
  }
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_ANY)};
  if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0) {
    int e = errno;
    close(fd);
    return net_err("bind", e);
  }
  return lean_io_result_mk_ok(lean_box_uint32((uint32_t)fd));
}

// udpJoin : UInt32 → (group : String) → IO Unit
LEAN_EXPORT lean_obj_res fe_udp_join(uint32_t fd, b_lean_obj_arg group, lean_obj_arg w) {
  (void)w;
  struct ip_mreq m = {.imr_interface.s_addr = htonl(INADDR_ANY)};
  if (!parse_ip(lean_string_cstr(group), &m.imr_multiaddr)) {
    return net_err("multicast group", EINVAL);
  }
  if (setsockopt((int)fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &m, sizeof m) != 0) {
    return net_err("IP_ADD_MEMBERSHIP", errno);
  }
  return lean_io_result_mk_ok(lean_box(0));
}

// udpSend : UInt32 → (ip : String) → (port : UInt16) → ByteArray → IO Unit
LEAN_EXPORT lean_obj_res fe_udp_send(uint32_t fd, b_lean_obj_arg ip, uint16_t port, b_lean_obj_arg data, lean_obj_arg w) {
  (void)w;
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port)};
  if (!parse_ip(lean_string_cstr(ip), &a.sin_addr)) {
    return net_err(lean_string_cstr(ip), EINVAL);
  }
  ssize_t n = sendto((int)fd, lean_sarray_cptr(data), lean_sarray_size(data), 0, (struct sockaddr *)&a, sizeof a);
  if (n < 0) {
    return net_err("sendto", errno);
  }
  return lean_io_result_mk_ok(lean_box(0));
}

// udpRecv : UInt32 → (timeoutMs : UInt32) → IO (ByteArray × String). Empty on timeout.
LEAN_EXPORT lean_obj_res fe_udp_recv(uint32_t fd, uint32_t timeout_ms, lean_obj_arg w) {
  (void)w;
  struct pollfd p = {.fd = (int)fd, .events = POLLIN};
  int r = poll(&p, 1, (int)timeout_ms);
  if (r < 0 && errno != EINTR) {
    return net_err("poll", errno);
  }
  uint8_t buf[9216];
  ssize_t n = 0;
  char from[INET_ADDRSTRLEN] = "";
  if (r > 0) {
    struct sockaddr_in a;
    socklen_t al = sizeof a;
    n = recvfrom((int)fd, buf, sizeof buf, 0, (struct sockaddr *)&a, &al);
    if (n < 0) {
      return net_err("recvfrom", errno);
    }
    inet_ntop(AF_INET, &a.sin_addr, from, sizeof from);
  }
  lean_object *bytes = lean_alloc_sarray(1, (size_t)n, (size_t)n);
  memcpy(lean_sarray_cptr(bytes), buf, (size_t)n);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, bytes);
  lean_ctor_set(pair, 1, lean_mk_string(from));
  return lean_io_result_mk_ok(pair);
}

LEAN_EXPORT lean_obj_res fe_udp_close(uint32_t fd, lean_obj_arg w) {
  (void)w;
  close((int)fd);
  return lean_io_result_mk_ok(lean_box(0));
}

// httpGet : (ip : String) → (port : UInt16) → (path : String) → (timeoutMs : UInt32) → IO String
// Returns the whole response, headers included; Lean splits it.
LEAN_EXPORT lean_obj_res fe_http_get(b_lean_obj_arg ip, uint16_t port, b_lean_obj_arg path, uint32_t timeout_ms,
                                     lean_obj_arg w) {
  (void)w;
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port)};
  if (!parse_ip(lean_string_cstr(ip), &a.sin_addr)) {
    return net_err(lean_string_cstr(ip), EINVAL);
  }
  int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    return net_err("socket", errno);
  }
  struct timeval tv = {.tv_sec = timeout_ms / 1000, .tv_usec = (timeout_ms % 1000) * 1000};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
  if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) {
    int e = errno;
    close(fd);
    return net_err("connect", e);
  }
  char req[1024];
  int len = snprintf(req, sizeof req, "GET %s HTTP/1.1\r\nHost: %s:%u\r\nConnection: close\r\n\r\n",
                     lean_string_cstr(path), lean_string_cstr(ip), (unsigned)port);
  if (len < 0 || (size_t)len >= sizeof req || send(fd, req, (size_t)len, MSG_NOSIGNAL) != len) {
    int e = errno;
    close(fd);
    return net_err("send", e ? e : EMSGSIZE);
  }
  size_t cap = 65536, size = 0;
  char *out = malloc(cap + 1);
  for (;;) {
    if (size == cap) {
      cap *= 2;
      if (cap > (16u << 20)) {
        break;
      }
      out = realloc(out, cap + 1);
    }
    ssize_t n = recv(fd, out + size, cap - size, 0);
    if (n <= 0) {
      break;
    }
    size += (size_t)n;
  }
  close(fd);
  out[size] = 0;
  lean_object *s = lean_mk_string_from_bytes(out, size);
  free(out);
  return lean_io_result_mk_ok(s);
}
