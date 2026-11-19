procedure {:rlimit 10000000} terms()
{
  var x: int;
  var p: bool;
  var q: bool;

  havoc x;
  assert {:msg "O1"} (3 * (-2)) == (-6);
  assert {:msg "O2"} (x - 1) > (x - 2);
  assert {:msg "O3"} (1 < 2) && (2 >= 2);
  assert {:msg "O4"} (p && q) ==> (p || false);
  assert {:msg "O5"} !((if p then 1 else 2) != (if !p then 2 else 1));
  p := true;
  assert {:msg "O6"} p == (q || !q);
  assert {:msg "O7"} (((-7) mod 3) == 2) && ((7 mod (-3)) == 1);
  assert {:msg "O8"} (((-7) div 3) == (-3)) && ((7 div (-3)) == (-2));
}
