procedure {:rlimit 10000000} several()
{
  var x: int;
  var y: int;

  assert {:msg "O1"} x > 0;
  assert {:msg "O2"} y > 0;
  assert {:msg "O3"} (x + y) > x;
  if (x > 10) {
    assert {:msg "O4"} x > 20;
  } else if (x > 5) {
    assert {:msg "O5"} x <= 10;
  } else if (x > 2) {
    assert {:msg "O6"} x < 5;
  } else {
    assert {:msg "O7"} x <= 2;
  }
}

procedure {:rlimit 10000000} other()
{
  var z: int;

  assert {:msg "O8"} z == 0;
}
