procedure {:rlimit 10000000} control()
{
  var x: int;
  var y: int;

  if (x > 0) {
    y := 1;
    goto done;
  }
  if (*) {
    y := 2;
  } else {
    y := 3;
    goto done;
    y := 4;
  }
  assert {:msg "O1"} (x <= 0) && (y == 2);
  done:
  assert {:msg "O2"} (y >= 1) && (y <= 3);
  assert {:msg "O3"} y != 4;
  assert {:msg "O4"} y == 2;
}
