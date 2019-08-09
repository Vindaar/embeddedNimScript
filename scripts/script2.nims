
proc update* =
  modifyState("cats")

proc updateObj* =
  var obj = SomeObj(name: "funny")#, val: 24.0)
  obj.val = 24.0
  modifyObject(obj)
  echo obj.name
