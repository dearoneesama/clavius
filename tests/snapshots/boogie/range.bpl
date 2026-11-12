procedure {:rlimit 10000000} add()
{
  var x: int;
  var y: int;

  assume ((-9007199254740992) <= x) && (x <= 9007199254740992);
  assert {:msg "O1"} ((-9007199254740992) <= (x + 1)) && ((x + 1) <= 9007199254740992);
  y := x + 1;
}

procedure {:rlimit 10000000} add_guarded()
{
  var x: int;
  var y: int;

  assume ((-9007199254740992) <= x) && (x <= 9007199254740992);
  if (x < 100) {
    assert {:msg "O2"} ((-9007199254740992) <= (x + 1)) && ((x + 1) <= 9007199254740992);
    y := x + 1;
  }
}
