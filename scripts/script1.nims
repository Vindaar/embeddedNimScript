
proc subtract*(a, b: int): int =
  result = a - b

proc someAdd* =
  let args = [8, 12]
  echo "AGAIN: From NIMS to NIM and back:    ", args[0], " + ", args[1], " = ",
    add2(args[0], args[1])
