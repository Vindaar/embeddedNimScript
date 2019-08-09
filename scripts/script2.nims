
proc update* =
  modifyState("cats")

proc updateObj* =
  var obj = SomeObj(name: "funny", val: 24.0, blublub: 123, ab: @[1.1, 2.2, 3.3])
  modifyObject(obj)
  echo obj.name
