type S;
function empty(): S;
function size(s: S, k: int): int;
axiom (forall s: S, k: int :: { size(s, k) } k <= size(s, k));

procedure {:rlimit 10000000} sizes()
{
  var t: S;

  havoc t;
  assert {:msg "O1"} size(t, 3) >= 3;
  assert {:msg "O2"} size(empty(), 0) >= 0;
  assert {:msg "O3"} size(empty(), 0) > 0;
  assert {:msg "O4"} (exists k: int :: { size(t, k) } size(t, k) >= k);
}
