; fails: O2 O3 O4
; Boogie checks each unit as one query. O2 makes the query of `cubes` run out of resources, and then
; Boogie reports no failing assert of `cubes` at all including O3. `quick` finishes and O4 fails.
; The rerun checks each assert of `cubes` as its own query. O2 runs out of resources on its own and
; counts as failing. O1 holds and O3 fails as usual.
(Unit cubes linear
  [(VarDecl x int) (VarDecl y int) (VarDecl z int)]
  [(Assume 1 (BinOp and (BinOp > (Var x) (Int 1)) (BinOp and (BinOp > (Var y) (Int 1)) (BinOp > (Var z) (Int 1)))))
   (Check 1 (BinOp > (Var x) (Int 0)))
   (Check 2 (BinOp !=
     (BinOp + (BinOp * (BinOp * (Var x) (Var x)) (Var x)) (BinOp * (BinOp * (Var y) (Var y)) (Var y)))
     (BinOp * (BinOp * (Var z) (Var z)) (Var z))))
   (Check 3 (BinOp > (Var y) (Int 5)))])
(Unit quick linear
  [(VarDecl w int)]
  [(Check 4 (BinOp > (Var w) (Int 0)))])

(obligation 1 :kind assert :node 0)
(obligation 2 :kind assert :node 0)
(obligation 3 :kind assert :node 0)
(obligation 4 :kind assert :node 0)

(assumption 1 :kind branch :node 0)
