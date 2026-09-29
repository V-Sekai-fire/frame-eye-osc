-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: MIT
import Lake
open Lake DSL System

package FrameEyeOscTests where
  leanOptions := #[⟨`autoImplicit, false⟩]

require «plausible-witness-dag» from git
  "https://github.com/fire/plausible-witness-dag" @ "160b94c9c6eed3bb9ebffce919fc6f989dcafba8"

-- ../src/core.slang as C++: every function the tests call, with C names.
target core.cpp pkg : FilePath := do
  let src := pkg.dir / ".." / "src"
  let out := pkg.buildDir / "gen" / "core.cpp"
  let entries ← src.readDir
  let slang := entries.filter (·.path.extension == some "slang")
  let inputs ← slang.mapM (inputTextFile ·.path)
  (Job.collectArray inputs).mapM fun _ => do
    buildFileUnlessUpToDate' out do
      createParentDirs out
      proc { cmd := "slangc", args := #[(src / "core.slang").toString, "-I", src.toString, "-target", "cpp",
                                         "-warnings-disable", "41017", "-o", out.toString] }
    return out

def cppObj (pkg : Package) (name : String) (src : Job FilePath) : FetchM (Job FilePath) := do
  let includes := #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.dir / "ffi").toString]
  buildO (pkg.buildDir / "ffi" / s!"{name}.o") src includes #["-std=c++17", "-O2", "-fPIC", "-Wno-main"] "c++"

extern_lib frameeyeosc_ffi pkg := do
  let core ← cppObj pkg "core" (← core.cpp.fetch)
  let shim ← cppObj pkg "shim" (← inputTextFile (pkg.dir / "ffi" / "shim.cpp"))
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "frameeyeosc_ffi") #[core, shim]

lean_lib FrameEyeOscTests

@[default_target]
lean_exe tests where
  root := `Main
  moreLinkArgs := #["-lpthread", "-lm"]
