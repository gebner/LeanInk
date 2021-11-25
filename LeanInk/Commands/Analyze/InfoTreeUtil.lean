import Lean.Elab.Command

import Lean.Data.Lsp

namespace LeanInk.Commands.Analyze

open Lean
open Lean.Elab

/-
  TacticFragment
-/
structure TacticFragment where
  info: TacticInfo
  ctx: ContextInfo
  deriving Inhabited

namespace TacticFragment
  def headPos (f: TacticFragment) : String.Pos := 
    (f.info.toElabInfo.stx.getPos? false).getD 0

  def tailPos (f: TacticFragment) : String.Pos := 
    (f.info.toElabInfo.stx.getTailPos? false).getD 0

  def length (f: TacticFragment) : Nat := 
    tailPos f - headPos f

  def toFormat (f: TacticFragment) : IO Format := 
    TacticInfo.format f.ctx f.info

  def isExpanded (f: TacticFragment) : Bool :=
    match f.info.toElabInfo.stx.getHeadInfo, f.info.toElabInfo.stx.getTailInfo with
    | SourceInfo.original .., SourceInfo.original .. => false
    | _, _ => true
end TacticFragment

/-
  MessageFragment
-/
structure MessageFragment where
  headPos: String.Pos
  tailPos: String.Pos
  msg: Message

def Position.toStringPos (fileMap: FileMap) (pos: Position) : String.Pos :=
    return FileMap.lspPosToUtf8Pos fileMap (fileMap.leanPosToLspPos pos)

namespace MessageFragment
  def mkFragment (fileMap: FileMap) (msg: Message) : MessageFragment := do
    let headPos := Position.toStringPos fileMap msg.pos
    let tailPos := Position.toStringPos fileMap (msg.endPos.getD msg.pos)
    return { headPos := headPos, tailPos := tailPos, msg := msg }

  def length (f: MessageFragment) : Nat := f.tailPos - f.headPos
end MessageFragment

def mergeSort [Inhabited α] (f: α -> α -> Bool) : List α -> List α -> List α
  | [], x => (x.toArray.qsort f).toList
  | x, [] => (x.toArray.qsort f).toList
  | x::xs, y::ys => 
    if f x y then
      return x::y::mergeSort f xs ys
    else
      return y::x::mergeSort f xs ys

def mergeSortFragments : List TacticFragment -> List TacticFragment -> List TacticFragment := 
  mergeSort (λ x y => x.headPos < y.headPos)

def Info.toFragment (info : Info) (ctx : ContextInfo) : Option TacticFragment := do
  match info with
  | Info.ofTacticInfo i => 
    let fragment : TacticFragment := { info :=  i, ctx := ctx }
    if fragment.isExpanded then
      return none
    else
      return fragment
  | _ => none

partial def _resolveTacticList (ctx?: Option ContextInfo := none) : InfoTree -> List TacticFragment
  | InfoTree.context ctx tree => _resolveTacticList ctx tree
  | InfoTree.node info children =>
    match ctx? with
    | none => return []
    | some ctx =>
      let ctx? := info.updateContext? ctx
      let resolvedChildrenLeafs := children.toList.map (_resolveTacticList ctx?)
      let sortedChildrenLeafs := resolvedChildrenLeafs.foldl mergeSortFragments []
      if sortedChildrenLeafs.isEmpty then
        match Info.toFragment info ctx with
        | some f => [f]
        | none => []
      else
        return sortedChildrenLeafs    
  | _ => []

def resolveTacticList (trees: List InfoTree) : List TacticFragment :=
  return (trees.map _resolveTacticList).foldl mergeSortFragments []