import macros
from compiler/idents import IdentCache
from compiler/vmdef import registerCallback, VmArgs, PCtx
from compiler/modulegraphs import ModuleGraph

from compiler/vm import
    # Getting values from VmArgs
    getInt, getFloat, getString, getBool, getNode, getVarNode,
    # Setting result (return value)
    setResult

from compiler/ast import
    # Types
    PSym, PNode, TNodeKind,
    # Getting values from PNodes
    getInt, getFloat,
    # Creating new PNodes
    newNode, newFloatNode, addSon, newTree

from os import splitFile
from threadpool import FlowVar

import compiler/renderer

# Assume location of shared state type in ../state
import ../state
include ../scripts/types


type
    Script* = ref object
        filename*: string
        moduleName*: string
        mainModule*: PSym
        graph*: ModuleGraph
        context*: PCtx
        watcher*: FlowVar[int]

#proc getNode*(a: VmArgs; i: Natural): PNode =
#  doAssert i < a.rc-1
#  let s = cast[seq[TFullReg]](a.slots)
#  doAssert s[i+a.rb+1].kind == rkNode
#  result = s[i+a.rb+1].node

#type
#  SomeObj = object
#    name: string
#    val: float

#proc fill[T](x: var SomeObj, field: string, val: T) =



#[ Structure of AST for objects:
- Node:
  - nkEmpty ??
  - nkExprColonExpr:
    - nkSym: Field1
    - nkStr / Int / Float (basic type node): Value1
  - nkExprColonExpr:
    - nkSym: Field2
    - nkStr / Int / Float (basic type node): Value2
  - ...

Thus, macro takes `SomeObj` and hardcodes a:
doAssert x[0].kind == nkEmpty
doAssert x[1].kind == nkExprColonExpr
doAssert x[1][0].kind == nkSym
doAssert x[1][0].sym.name.s == "name"
doAssert x[1][1].kind == nkStrLit
result.name = x[1][1].strVal
doAssert x[2].kind == nkExprColonExpr
doAssert x[2][0].kind == nkSym
doAssert x[2][0].sym.name.s == "val"
doAssert x[2][1].kind == nkFloatLit
result.val = x[2][1].floatVal
]#

template setStrField(res: var SomeObj, n: PNode, fieldName: string): NimNode =
  doAssert n.kind == nkExprColonExpr
  doAssert n.sons[0].kind == nkSym
  doAssert n.sons[0].sym.name.s == "name"
  doAssert n.sons[1].kind == nkStrLit

proc extractName(n: NimNode): string =
  case n.kind
  of nnkPostfix:
    doAssert n[1].kind == nnkIdent
    result = n[1].strVal
  of nnkIdent:
    result = n.strVal
  else:
    error("extractName??? " & $n.kind)

proc extractType(n: NimNode): NimNode =
  # n is the type node
  result = n

proc extractNameType(n: NimNode): tuple[name: string, dtype: NimNode] =
  result[0] = extractName(n[0])
  result[1] = extractType(n[1])

proc nodeToVal(dtype: NimNode): NimNode =
  doAssert dtype.kind == nnkBracketExpr
  case dtype[1].strVal
  of "float":
    result = ident("floatVal")
  of "int":
    result = ident("intVal")
  of "string":
    result = ident("strVal")
  else:
    error("??? broken")

proc addFloatField(nId: NimNode, idx: int, name: string, dtype: NimNode): NimNode =
  let fieldName = ident(name)
  let resIdent = ident("result")
  result = quote do:
    doAssert `nId`.sons[`idx`].sons[1].kind == nkFloatLit
    `resIdent`.`fieldName` = n.sons[`idx`].sons[1].floatVal

proc addIntField(nId: NimNode, idx: int, name: string, dtype: NimNode): NimNode =
  let fieldName = ident(name)
  let resIdent = ident("result")
  result = quote do:
    doAssert `nId`.sons[`idx`].sons[1].kind == nkIntLit
    `resIdent`.`fieldName` = n.sons[`idx`].sons[1].intVal.int

proc addStringField(nId: NimNode, idx: int, name: string, dtype: NimNode): NimNode =
  let fieldName = ident(name)
  let resIdent = ident("result")
  result = quote do:
    doAssert `nId`.sons[`idx`].sons[1].kind == nkStrLit
    `resIdent`.`fieldName` = n.sons[`idx`].sons[1].strVal

proc handleScalar(nId: NimNode, idx: int, name: string, dtype: NimNode): NimNode =
  let nameLit = newLit name
  result = quote do:
    doAssert `nId`.sons[`idx`].sons[0].kind == nkSym
    doAssert `nId`.sons[`idx`].sons[0].sym.name.s == `nameLit`
  # type specific doAssert and assignment
  case dtype.strVal
  of "float":
    result.add addFloatField(nId, idx, name, dtype)
  of "int":
    result.add addIntField(nId, idx, name, dtype)
  of "string":
    result.add addStringField(nId, idx, name, dtype)
  else:
    error("handleScalar ??? " & $dtype.strVal)

proc handleSeq(nId: NimNode, idx: int, name: string, dtype: NimNode): NimNode =
  let nameLit = newLit name
  let nodeToVal = dtype.nodeToVal
  let fieldName = ident(name)
  let resIdent = ident("result")
  result = quote do:
    doAssert `nId`.sons[`idx`].sons[0].kind == nkSym
    doAssert `nId`.sons[`idx`].sons[0].sym.name.s == `nameLit`
    for j in `nId`.sons[`idx`].sons[1].sons:
      `resIdent`.`fieldName`.add j.`nodeToVal`
  # type specific doAssert and assignment
  # now have to iterate over the seq elements

  #case dtype.strVal
  #of "float":
  #  result.add addFloatField(nId, idx, name, dtype)
  #of "int":
  #  result.add addIntField(nId, idx, name, dtype)
  #of "string":
  #  result.add addStringField(nId, idx, name, dtype)
  #else:
  #  error("handleScalar ??? " & $dtype.strVal)

macro genGetProc(t: typedesc): untyped =
  let tImpl = t.getImpl
  echo "\n\n\n\n\n"
  let tsym = tImpl[0]
  echo tImpl.treeRepr
  # - use name to generate ident for procs
  # - iterate tImpl[2][2] IdentDefs to extract name / type pairs
  let procName = ident("get" & $tSym)
  echo "!!!! ", tImpl[2].treeRepr
  doAssert tImpl[2].kind == nnkObjectTy

  var idxNameType = newSeq[(int, string, NimNode)]()

  var idx = 1 # start from 1, because PNode has one nkEmpty field at idx == 0
  for ch in tImpl[2][2]:
    case ch.kind
    of nnkEmpty:
      discard
    of nnkIdentDefs:
      let (name, dtype) = extractNameType(ch)
      echo "Is ", name, " and ", dtype.repr
      idxNameType.add (idx, name, dtype)
    else:
      error("genGetProc ??? " & $ch.treeRepr)
    inc idx

  echo idxNameType.repr

  # using idxNameType, write the proc
  let
    aId = ident"a"
    iId = ident"i"
    nId = ident"n"
  var procBody = newStmtList()
  procBody.add quote do:
    let `nId` = getVarNode(`aId`, `iId`)
    doAssert `nId`.sons[0].kind == nkEmpty
  # append the `doAssert` and assignments
  let resId = ident("result")
  for (idx, name, dtype) in idxNameType:
    procBody.add quote do:
      doAssert `nId`.sons[`idx`].kind == nkExprColonExpr
    case dtype.kind
    of nnkSym, nnkIdent:
      procBody.add handleScalar(nId, idx, name, dtype)
    of nnkBracketExpr:
      procBody.add handleSeq(nId, idx, name, dtype)
    else:
      echo "No was ", dtype.kind
      discard
  result = quote do:
    proc `procName`(`aId`: VmArgs, `iId`: Natural): `tsym` =
      `procBody`

  echo result.repr

genGetProc(SomeObj)
# genGetProc should generate something roughly like the `getObj` below
proc getObj(a: VmArgs, i: Natural): SomeObj =
  let n = getVarNode(a, i)
  doAssert n.sons[0].kind == nkEmpty
  doAssert n.sons[1].kind == nkExprColonExpr
  doAssert n.sons[1].sons[0].kind == nkSym
  doAssert n.sons[1].sons[0].sym.name.s == "name"
  doAssert n.sons[1].sons[1].kind == nkStrLit
  result.name = n.sons[1].sons[1].strVal
  #result.setStrField(n.sons[1])

  doAssert n.sons[2].kind == nkExprColonExpr
  doAssert n.sons[2].sons[0].kind == nkSym
  doAssert n.sons[2].sons[0].sym.name.s == "val"
  doAssert n.sons[2].sons[1].kind == nkFloatLit, "was " & $n.sons[2].sons[1].kind
  result.val = n.sons[2].sons[1].floatVal
  #for x in n.sons:
  #  case x.kind
  #  of nkExprColonExpr:
  #    echo "Is ", x.kind, " w ", x
  #    # iterate (name: val) pairs
  #    for y in x.sons:
  #      case y.kind
  #      of nkSym:
  #        # this is the field we need to fill
  #        field = y
  #      of nkFloatLit, nkStrLit:
  #        # the value
  #        val = y
  #      else:
  #        echo "also broken ", y.kind
  #      echo "y is ", y.kind, " w ", y
  #  else:
  #    echo "broken ", x.kind
  #echo "F, ", field, " v, ", val


proc exposeScriptApi* (script: Script) =
    template expose (procName, procBody: untyped): untyped {.dirty.} =
      script.context.registerCallback(
        script.moduleName & "." & astToStr(procName),
        proc (a: VmArgs) =
          echo "CALLING from ", astToStr(procName)
          procBody
      )

    expose add2:
        # We need to use procs like getInt to retrieve the argument values from VmArgs
        # Instead of using the return statement we need to use setResult
      let arg1 = getInt(a, 0)
      let arg2 = getInt(a, 1)
      setResult(a, arg1 + arg2)
      echo "CALLING!"

    expose modifyState:
      modifyMe = getString(a, 0)
      echo "`", script.moduleName, "` has changed state.modifyMe to `", modifyMe, "`"

    expose modifyObject:
      var modObj = getSomeObj(a, 0)
      modObj.name = "test"
      echo "`", script.moduleName, "` has changed state.modifyObject to `", modObj, "`"
