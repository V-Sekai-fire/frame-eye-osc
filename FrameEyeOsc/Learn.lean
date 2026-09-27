-- SPDX-License-Identifier: MIT
import Std.Data.HashMap
import FrameEyeOsc.Osc
/-!
# Learning the avatar's parameters from VRChat's own OSC output

VRChat's OSCQuery HTTP server only listens on the PC's loopback, so the headset cannot
ask it for the avatar's parameter list. VRChat will send its OSC *output* anywhere,
though: launch it with `--osc=9000:<frame-ip>:9001`. On every avatar load it sends
`/avatar/change` and then every parameter with its current value. The value's OSC
type is the parameter's type (`f`, `i`, or `T`/`F` for bools), which is all
`Params.plan` needs.
-/

namespace FrameEyeOsc.Learn

open FrameEyeOsc Osc

structure State where
  avatar : Option String := none
  params : Std.HashMap String String := {}   -- full OSC path ↦ "f" | "i" | "T"
  deriving Inhabited

def typeOf : Arg → Option String
  | .f _ => some "f"
  | .i _ => some "i"
  | .b _ => some "T"
  | .s _ => none

/-- Fold one message in. Returns the new state and whether the parameter set changed. -/
def observe (st : State) (m : Message) : State × Bool :=
  if m.address == "/avatar/change" then
    let id := match m.args with | [.s id] => some id | _ => none
    ({ avatar := id, params := {} }, true)
  else if m.address.startsWith "/avatar/parameters/" then
    match m.args.head?.bind typeOf with
    | some t => if st.params.contains m.address then (st, false)
                else ({ st with params := st.params.insert m.address t }, true)
    | none => (st, false)
  else (st, false)

def State.list (st : State) : List (String × String) := st.params.toList

end FrameEyeOsc.Learn
