import macros
from compiler/idents import IdentCache
from compiler/vmdef import registerCallback, VmArgs, PCtx
from compiler/modulegraphs import ModuleGraph

from compiler/vm import
    # Getting values from VmArgs
    getInt, getFloat, getString, getBool, getNode,
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

macro genGetProc(t: typedesc): untyped =
  let tImpl = t.getImpl
  echo "\n\n\n\n\n"
  let tsym = tImpl[0]
  # - use name to generate ident for procs
  # - iterate tImpl[2] IdentDefs to extract name / type pairs

  #result = quote do:

genGetProc(SomeObj)

proc getObj(a: VmArgs, i: Natural): SomeObj =
  let n = getNode(a, i)
  var field: PNode
  var val: PNode
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
      var modObj = getObj(a, 0)
      modObj.name = "test"
      echo "`", script.moduleName, "` has changed state.modifyObject to `", modObj, "`"
