procedure {:rlimit 10000000} cubes()
{
  var x: int;
  var y: int;
  var z: int;

  assume (x > 1) && ((y > 1) && (z > 1));
  assert {:msg "O1"} x > 0;
  assert {:msg "O2"} (((x * x) * x) + ((y * y) * y)) != ((z * z) * z);
  assert {:msg "O3"} y > 5;
}

procedure {:rlimit 10000000} quick()
{
  var w: int;

  assert {:msg "O4"} w > 0;
}
