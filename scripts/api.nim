include types

template builtin = discard

proc add2(a, b: int): int = builtin

proc modifyState (str: string) = builtin

#type
#  SomeObj = object
#    name: string
#    val: float

proc modifyObject (obj: var SomeObj) = builtin
