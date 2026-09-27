-- SPDX-License-Identifier: MIT
/-!
# The C shim

`ffi/shm.c` (the eye-server calls in `abi/eye_server.sigs`) and `ffi/net.c` (UDP and one
HTTP GET). Raw `@[extern]` opaques, in the style of sinew-driver's `Sinew/Udp.lean`.
-/

namespace FrameEyeOsc.Ffi

/-- Map `/dev/shm/eye-server.mmap`, checking size, version 4 and `initialized`. -/
@[extern "fe_shm_open"] opaque shmOpen (path : @& String) : IO Unit
/-- Wait up to `timeoutMs` for the next record. Empty when none arrived. -/
@[extern "fe_shm_next"] opaque shmNext (timeoutMs : UInt32) : IO ByteArray
@[extern "fe_shm_close"] opaque shmClose : IO Unit

/-- Bind a UDP socket on `port` (0 for any), optionally sharing it (mDNS on 5353). -/
@[extern "fe_udp_open"] opaque udpOpen (port : UInt16) (reuse : UInt8) : IO UInt32
@[extern "fe_udp_join"] opaque udpJoin (fd : UInt32) (group : @& String) : IO Unit
@[extern "fe_udp_send"] opaque udpSend (fd : UInt32) (ip : @& String) (port : UInt16) (data : @& ByteArray) : IO Unit
/-- Wait up to `timeoutMs` for a datagram. Empty bytes on timeout. Returns the sender's IP. -/
@[extern "fe_udp_recv"] opaque udpRecv (fd : UInt32) (timeoutMs : UInt32) : IO (ByteArray × String)
@[extern "fe_udp_close"] opaque udpClose (fd : UInt32) : IO Unit

/-- One `GET`, returning the whole HTTP response. -/
@[extern "fe_http_get"] opaque httpGetRaw (ip : @& String) (port : UInt16) (path : @& String) (timeoutMs : UInt32) : IO String

/-- `GET` and return the body of a 200 response. -/
def httpGet (ip : String) (port : UInt16) (path : String) (timeoutMs : UInt32 := 1500) : IO String := do
  let r ← httpGetRaw ip port path timeoutMs
  match r.splitOn "\r\n\r\n" with
  | head :: rest =>
    unless head.startsWith "HTTP/1.1 200" || head.startsWith "HTTP/1.0 200" do
      throw <| IO.userError s!"GET {ip}:{port}{path}: {(head.splitOn "\r\n").headD ""}"
    return "\r\n\r\n".intercalate rest
  | [] => throw <| IO.userError s!"GET {ip}:{port}{path}: empty response"

end FrameEyeOsc.Ffi
