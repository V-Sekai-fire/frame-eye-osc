import Lake
open Lake DSL System

package FrameEyeOsc where
  version := v!"0.2.0"
  leanOptions := #[⟨`autoImplicit, false⟩]

-- Property testing, pinned to the toolchain like the rest of the workspace.
require plausible from git
  "https://github.com/leanprover-community/plausible" @ "v4.30.0"

-- The iterative-deepening counter-example search that `lake exe falsify` drives.
require «plausible-witness-dag» from git
  "https://github.com/V-Sekai-fire/plausible-witness-dag" @ "23ca437da267"

@[default_target]
lean_lib FrameEyeOsc

-- ── The C shim ────────────────────────────────────────────────────────────────
-- abi/eye_server.sigs becomes a header of prototypes compiled next to glibc's own, so
-- a signature in the .sigs file that disagrees with libc fails the build.
target eye_server_api.h pkg : FilePath := do
  let sigs := pkg.dir / "abi" / "eye_server.sigs"
  let gen  := pkg.dir / "abi" / "sigs_to_header.py"
  let out  := pkg.buildDir / "gen" / "eye_server_api.h"
  let sigsJob ← inputTextFile sigs
  sigsJob.mapM fun _ => do
    buildFileUnlessUpToDate' out do
      createParentDirs out
      proc { cmd := "python3", args := #[gen.toString, sigs.toString, out.toString,
                                           "FRAMEEYEOSC_EYE_SERVER_API_H", "eye_server_decls.h"] }
    return out

def ffiObj (pkg : Package) (stem : String) (apiH : Job FilePath) : FetchM (Job FilePath) := do
  let src ← inputTextFile (pkg.dir / "ffi" / s!"{stem}.c")
  let src := src.zipWith (fun s _ => s) apiH
  let weak := #["-I", (← getLeanIncludeDir).toString,
                "-I", (pkg.buildDir / "gen").toString,
                "-I", (pkg.dir / "abi").toString, "-I", (pkg.dir / "ffi").toString]
  buildO (pkg.buildDir / "ffi" / s!"{stem}.o") src weak
    #["-std=c11", "-O2", "-fPIC", "-Wall", "-Werror", "-D_GNU_SOURCE"] "cc"

extern_lib feffi pkg := do
  let apiH ← eye_server_api.h.fetch
  let objs ← #["shm", "net"].mapM (ffiObj pkg · apiH)
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "feffi") objs

-- ── Executables ───────────────────────────────────────────────────────────────
lean_exe frameeyeosc where
  root := `Main

-- Plausible properties over the Float code paths that the theorems cannot reach.
lean_exe proptest where
  root := `Proptest

-- plausible-witness-dag counter-example search, each query paired with a broken control.
lean_exe falsify where
  root := `Falsify

-- Regenerates abi/eye_server_layout.h from FrameEyeOsc.Layout (`--check` fails if stale).
lean_exe layout_header where
  root := `LayoutHeader
