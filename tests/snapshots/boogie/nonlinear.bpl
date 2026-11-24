procedure {:rlimit 10000000} area()
{
  var w: int;
  var h: int;

  assume (0 <= w) && (w <= 4096);
  assume (0 <= h) && (h <= 4096);
  assert {:msg "O1"} (w * h) <= 16777216;
}

procedure {:rlimit 10000000} {:smt_option "smt.arith.nl", "true"} nonlinear_area()
{
  var w: int;
  var h: int;

  assume (0 <= w) && (w <= 4096);
  assume (0 <= h) && (h <= 4096);
  assert {:msg "O2"} (w * h) <= 16777216;
}
